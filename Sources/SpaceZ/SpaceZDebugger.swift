import Foundation
import OSLog
@_exported import SpaceZCore
@_exported import SpaceZRules
import SpaceZOverlay
import SpaceZRemote
import SpaceZSwiftUI
import SpaceZUIKit
import UIKit

/// Public entry point.
///
/// ```swift
/// #if DEBUG
/// import SpaceZ
/// SpaceZDebugger.start()
/// #endif
/// ```
///
/// `start()` is a hard no-op in non-DEBUG builds: the capture engine, overlay
/// and — most importantly — the network server never come up in a release
/// binary even if the call ships by accident. A production UI inspector is a
/// data-exfiltration surface, so "off in release" is enforced here, not left
/// to documentation.
@MainActor
public enum SpaceZDebugger {
    static let logger = Logger(subsystem: "io.spacez", category: "SpaceZ")

    public private(set) static var session: SpaceZSession?

    /// The URL to open in a browser on the same network, once started.
    public static var inspectorURL: URL? { session?.inspectorURL }

    /// Boots capture + overlay + remote server. Safe to call from
    /// `application(_:didFinishLaunchingWithOptions:)` or the SwiftUI
    /// `App.init` — the overlay attaches itself when the first scene activates.
    public static func start(configuration: SpaceZConfiguration = .default) {
        #if DEBUG
        guard session == nil else {
            logger.warning("SpaceZDebugger.start() called twice; ignoring.")
            return
        }
        let session = SpaceZSession(configuration: configuration)
        self.session = session
        session.start()
        #else
        // Deliberately empty. See the type documentation.
        #endif
    }

    public static func stop() {
        session?.stop()
        session = nil
    }

    /// One immediate capture, bypassing the throttle. Also published to the
    /// pipeline, so overlay/remote update too.
    @discardableResult
    public static func captureNow() -> Snapshot? {
        session?.captureNow()
    }

    /// Signal that something changed outside normal run loop activity.
    public static func setNeedsCapture() {
        session?.detector.markDirty()
    }

    /// Opens the on-device inspector panel, exactly as tapping the floating
    /// button does. Useful from a debug menu, a shake-gesture handler, or a
    /// UI-test launch argument. No-op when the overlay is disabled or the
    /// debugger isn't running.
    public static func presentInspector() {
        session?.presentInspector()
    }

    /// Register a custom framework adapter (consulted before built-ins).
    public static func register(descriptor: NodeDescriptor) {
        session?.engine.descriptors.register(descriptor, prepend: true)
    }

    /// Register an additional diagnostic rule.
    public static func register(rule: any UIRule) {
        session?.ruleEngine.register(rule)
    }
}

/// Wires all modules together for one debug session.
@MainActor
public final class SpaceZSession {
    let configuration: SpaceZConfiguration
    let engine: CaptureEngine
    let detector: ChangeDetector
    let pipeline = SnapshotPipeline()
    let store = NodeStore()
    var ruleEngine = RuleEngine()
    let highlight = HighlightController()

    private var overlay: OverlayCoordinator?
    private var bridge: RemoteBridge?
    private var server: DebugServer?
    public private(set) var inspectorURL: URL?

    init(configuration: SpaceZConfiguration) {
        self.configuration = configuration
        self.engine = CaptureEngine()
        self.detector = ChangeDetector(throttle: configuration.captureThrottle)
    }

    func start() {
        // Descriptor order: SwiftUI first (it claims only hosting views),
        // UIKit as the general case, core fallback for everything else.
        engine.descriptors.register(SwiftUIHostingDescriptor())
        engine.descriptors.register(UIKitViewDescriptor())
        engine.addRootProvider(UIKitRootProvider())

        detector.onCaptureNeeded = { [weak self] in
            self?.captureAndPublish()
        }

        if configuration.overlayEnabled {
            let context = OverlayContext(
                pipeline: pipeline,
                registry: engine.registry,
                highlight: highlight,
                ruleEngine: ruleEngine,
                onSelect: { [weak self] nodeID in
                    guard let bridge = self?.bridge else { return }
                    Task { await bridge.pushSelection(nodeID) }
                }
            )
            let overlay = OverlayCoordinator(context: context)
            overlay.show()
            self.overlay = overlay
        }

        if configuration.remoteEnabled {
            startRemote()
        }

        detector.start()
        detector.markDirty()
    }

    func stop() {
        detector.stop()
        overlay?.hide()
        highlight.clear()
        let server = self.server
        Task { await server?.stop() }
        self.server = nil
        bridge = nil
    }

    @discardableResult
    func captureNow() -> Snapshot? {
        captureAndPublish()
    }

    func presentInspector() {
        overlay?.presentInspector()
    }

    @discardableResult
    private func captureAndPublish() -> Snapshot {
        let snapshot = engine.captureSnapshot(maxDepth: configuration.maxDepth)

        if snapshot.captureDuration > configuration.captureBudget {
            SpaceZDebugger.logger.warning(
                """
                Capture exceeded budget: \(Int(snapshot.captureDuration * 1000))ms \
                for \(snapshot.nodeCount) nodes (budget \
                \(Int(self.configuration.captureBudget * 1000))ms). Consider raising \
                captureThrottle or reporting this with the hierarchy shape.
                """
            )
        }

        let bridge = self.bridge
        Task.detached(priority: .utility) { [pipeline, store] in
            await store.update(snapshot)
            await pipeline.publish(snapshot)
            await bridge?.ingest(snapshot)
        }
        return snapshot
    }

    private func startRemote() {
        let registry = engine.registry
        let descriptors = engine.descriptors
        let highlight = self.highlight
        let writableKeys = configuration.writablePropertyKeys

        let handlers = RemoteUIHandlers(
            highlight: { nodeID in
                await MainActor.run {
                    guard let nodeID,
                          let view = registry.object(for: nodeID) as? UIView,
                          let window = view.window
                    else {
                        highlight.clear()
                        return
                    }
                    let frame = view.convert(view.bounds, to: window)
                    highlight.highlight(
                        frame: frame,
                        caption: "\(String(describing: type(of: view))) \(nodeID)"
                    )
                }
            },
            setProperty: { nodeID, key, value in
                await MainActor.run {
                    guard let object = registry.object(for: nodeID) else { return false }
                    let descriptor = descriptors.descriptor(for: object)
                    return descriptor.setProperty(key, to: value, on: object)
                }
            }
        )

        let bundle = Bundle.main
        let shortVersion = bundle.object(
            forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let buildNumber = bundle.object(
            forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let environment = SnapshotEnvironment(
            appName: bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? ProcessInfo.processInfo.processName,
            appVersion: "\(shortVersion) (\(buildNumber))",
            osVersion: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            deviceModel: UIDevice.current.model,
            locale: Locale.current.identifier,
            preferredContentSize: UIApplication.shared.preferredContentSizeCategory.rawValue
        )

        let bridge = RemoteBridge(
            redaction: configuration.remoteRedaction,
            writableKeys: writableKeys,
            ruleEngine: ruleEngine,
            handlers: handlers,
            environment: environment
        )
        self.bridge = bridge

        let server = DebugServer(httpPort: configuration.httpPort, bridge: bridge)
        self.server = server

        let host = NetworkInterfaces.primaryIPv4Address() ?? "localhost"
        let url = URL(string: "http://\(host):\(configuration.httpPort)/?token=\(server.token)")
        let port = configuration.httpPort

        Task { [weak self] in
            do {
                try await server.start()
                // Only advertise the URL once both listeners are actually
                // bound — printing it earlier would hand out a dead link when
                // the port is taken.
                await MainActor.run { self?.inspectorURL = url }
                SpaceZDebugger.logger.info(
                    "Remote inspector ready → \(url?.absoluteString ?? "?", privacy: .public)"
                )
                // Also print: the console is where developers will look first.
                print("[SpaceZ] Inspector → \(url?.absoluteString ?? "?")")
            } catch {
                SpaceZDebugger.logger.error(
                    "Remote inspector failed to start on port \(port): \(error, privacy: .public)"
                )
                print(
                    "[SpaceZ] Remote inspector failed to start on port \(port) "
                    + "(\(error)). Another app may hold it — set "
                    + "SpaceZConfiguration.httpPort to a free port. "
                    + "The in-app overlay still works."
                )
            }
        }
    }
}
