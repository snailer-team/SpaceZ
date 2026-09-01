import SpaceZCore
import SpaceZRules
import SpaceZUIKit
import UIKit

/// Everything the overlay needs from the session, injected once.
@MainActor
public struct OverlayContext {
    public let pipeline: SnapshotPipeline
    public let registry: NodeIDRegistry
    public let highlight: HighlightController
    public let ruleEngine: RuleEngine
    /// Called when the user picks a node on-device (tree tap or select mode),
    /// so the session can forward the selection to remote inspectors.
    public let onSelect: (NodeID) -> Void

    public init(
        pipeline: SnapshotPipeline,
        registry: NodeIDRegistry,
        highlight: HighlightController,
        ruleEngine: RuleEngine,
        onSelect: @escaping (NodeID) -> Void
    ) {
        self.pipeline = pipeline
        self.registry = registry
        self.highlight = highlight
        self.ruleEngine = ruleEngine
        self.onSelect = onSelect
    }
}

/// Owns the floating entry button and the inspector panel.
///
/// Lives in its own window (marked ``SpaceZInternalWindow`` → excluded from
/// capture). The window passes every touch through except over the button or
/// an open panel, so the debugger never steals a tap from the app.
@MainActor
public final class OverlayCoordinator {
    private final class PassthroughWindow: UIWindow, SpaceZInternalWindow {
        var interactiveWhenPanelOpen = false

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard let hit = super.hitTest(point, with: event) else { return nil }
            if interactiveWhenPanelOpen { return hit }
            // Only the floating button (and its subviews) are interactive.
            return hit.spacezIsInteractiveOverlayElement ? hit : nil
        }
    }

    private let context: OverlayContext
    private var window: PassthroughWindow?
    private var button: FloatingButton?
    private var selectMode: SelectModeController?
    private var sceneObserver: NSObjectProtocol?

    public init(context: OverlayContext) {
        self.context = context
    }

    public func show() {
        if attachToActiveScene() { return }
        // App may still be launching; wait for the first scene activation.
        sceneObserver = NotificationCenter.default.addObserver(
            forName: UIScene.didActivateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.window == nil else { return }
                if self.attachToActiveScene(), let observer = self.sceneObserver {
                    NotificationCenter.default.removeObserver(observer)
                    self.sceneObserver = nil
                }
            }
        }
    }

    public func hide() {
        window?.isHidden = true
        window = nil
        button = nil
    }

    /// Opens the inspector panel programmatically — the same panel the
    /// floating button presents. Lets hosts wire it to their own trigger
    /// (debug menu item, shake gesture, UI test launch argument).
    public func presentInspector() {
        presentPanel()
    }

    private func attachToActiveScene() -> Bool {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return false }

        let window = PassthroughWindow(windowScene: scene)
        window.windowLevel = .statusBar + 100
        window.backgroundColor = .clear
        let root = UIViewController()
        root.view.backgroundColor = .clear
        window.rootViewController = root
        window.isHidden = false

        let button = FloatingButton()
        button.onTap = { [weak self] in self?.presentPanel() }
        button.onLongPress = { [weak self] in self?.enterSelectMode() }
        root.view.addSubview(button)
        button.frame = CGRect(
            x: root.view.bounds.maxX - 68,
            y: root.view.bounds.midY - 100,
            width: 48,
            height: 48
        )

        self.window = window
        self.button = button
        return true
    }

    private func presentPanel() {
        guard let window, let root = window.rootViewController,
              root.presentedViewController == nil else { return }
        window.interactiveWhenPanelOpen = true

        let panel = InspectorPanelViewController(context: context)
        panel.onDismiss = { [weak self] in
            self?.window?.interactiveWhenPanelOpen = false
        }
        let navigation = UINavigationController(rootViewController: panel)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            // Keep the app visible above the sheet — inspecting while seeing
            // the UI is the point.
            sheet.largestUndimmedDetentIdentifier = .medium
        }
        root.present(navigation, animated: true)
    }

    private func enterSelectMode() {
        guard let window, selectMode == nil else { return }
        window.interactiveWhenPanelOpen = true
        let controller = SelectModeController(
            window: window,
            registry: context.registry,
            highlight: context.highlight
        )
        controller.onPicked = { [weak self] nodeID in
            guard let self else { return }
            self.exitSelectMode()
            self.context.onSelect(nodeID)
            self.presentPanel()
        }
        controller.onCancelled = { [weak self] in self?.exitSelectMode() }
        controller.begin()
        selectMode = controller
    }

    private func exitSelectMode() {
        selectMode?.end()
        selectMode = nil
        window?.interactiveWhenPanelOpen = false
    }
}

extension UIView {
    /// Marks views that should receive touches while the overlay window is in
    /// passthrough mode.
    @objc var spacezIsInteractiveOverlayElement: Bool {
        var current: UIView? = self
        while let view = current {
            if view is FloatingButton || view is SelectModeView { return true }
            current = view.superview
        }
        return false
    }
}
