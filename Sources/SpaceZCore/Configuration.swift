import Foundation

/// All the knobs, with defaults chosen for "drop into a debug build and go".
public struct SpaceZConfiguration: Sendable {
    /// Minimum interval between live captures. 250 ms ≈ 4 captures/s: fast
    /// enough to follow interactive debugging, and with a ~2 ms capture cost
    /// (5,000 nodes) it stays under 1% of main-thread time.
    public var captureThrottle: TimeInterval

    /// Hard traversal depth limit — guards against cyclic descriptors.
    public var maxDepth: Int

    /// Show the floating in-app inspector button.
    public var overlayEnabled: Bool

    /// Start the HTTP + WebSocket server for the browser inspector.
    public var remoteEnabled: Bool

    /// HTTP port serving the web client. WebSocket uses `httpPort + 1`.
    public var httpPort: UInt16

    /// Applied to every snapshot before it leaves the process.
    /// The in-app overlay always shows unredacted values.
    public var remoteRedaction: RedactionPolicy

    /// Property keys the remote `setProperty` command may mutate.
    /// A remote write API into a live app must be an allowlist, never open.
    public var writablePropertyKeys: Set<String>

    /// Warn-level budget for one main-thread capture pass. Exceeding it logs
    /// a warning with the node count so regressions surface immediately.
    public var captureBudget: TimeInterval

    public init(
        captureThrottle: TimeInterval = 0.25,
        maxDepth: Int = 512,
        overlayEnabled: Bool = true,
        remoteEnabled: Bool = true,
        httpPort: UInt16 = 9394,
        remoteRedaction: RedactionPolicy = .strict,
        writablePropertyKeys: Set<String> = ["alpha", "isHidden", "backgroundColor"],
        captureBudget: TimeInterval = 0.008
    ) {
        self.captureThrottle = captureThrottle
        self.maxDepth = maxDepth
        self.overlayEnabled = overlayEnabled
        self.remoteEnabled = remoteEnabled
        self.httpPort = httpPort
        self.remoteRedaction = remoteRedaction
        self.writablePropertyKeys = writablePropertyKeys
        self.captureBudget = captureBudget
    }

    public static let `default` = SpaceZConfiguration()

    /// Overlay only, no server — for environments where opening a port is
    /// unacceptable (e.g. dogfood builds).
    public static let overlayOnly = SpaceZConfiguration(remoteEnabled: false)
}
