import Foundation
import SpaceZCore
import SpaceZRules

/// Handlers that must run against live UI objects. Injected by the host
/// (umbrella target) so this module stays free of UIKit.
public struct RemoteUIHandlers: Sendable {
    /// Show/clear the on-device highlight for a node.
    public var highlight: @Sendable (NodeID?) async -> Void
    /// Apply an allowlisted property write. Returns success.
    public var setProperty: @Sendable (NodeID, String, InspectorValue) async -> Bool

    public init(
        highlight: @escaping @Sendable (NodeID?) async -> Void,
        setProperty: @escaping @Sendable (NodeID, String, InspectorValue) async -> Bool
    ) {
        self.highlight = highlight
        self.setProperty = setProperty
    }
}

/// Where a snapshot came from — device, OS, app build, locale.
///
/// A hierarchy snapshot without its environment can't explain
/// device-specific bugs ("text clips only on that customer's phone"):
/// the same screen renders differently per Dynamic Type, locale, and OS.
/// This rides along in `/snapshot.json` so a saved snapshot is a complete
/// field report, not just a tree.
public struct SnapshotEnvironment: Sendable, Codable {
    public var appName: String
    public var appVersion: String
    public var osVersion: String
    public var deviceModel: String
    public var locale: String
    public var preferredContentSize: String

    public init(
        appName: String = ProcessInfo.processInfo.processName,
        appVersion: String = "unknown",
        osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
        deviceModel: String = "unknown",
        locale: String = Locale.current.identifier,
        preferredContentSize: String = "unknown"
    ) {
        self.appName = appName
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.locale = locale
        self.preferredContentSize = preferredContentSize
    }
}

/// Inspector logic between the snapshot pipeline and the transport.
///
/// Owns the *redacted* copy of the world: snapshots enter through
/// `ingest(_:)`, get redacted once, diffed against the previous redacted
/// snapshot, and only then talk to clients. Raw values never reach this actor,
/// so a transport bug can't leak what redaction removed.
public actor RemoteBridge {
    private let redaction: RedactionPolicy
    private let writableKeys: Set<String>
    private let ruleEngine: RuleEngine
    private let handlers: RemoteUIHandlers
    private let environment: SnapshotEnvironment
    private var appName: String { environment.appName }

    private var current: Snapshot?
    private var broadcast: (@Sendable (InspectorResponse) -> Void)?

    public init(
        redaction: RedactionPolicy,
        writableKeys: Set<String>,
        ruleEngine: RuleEngine = RuleEngine(),
        handlers: RemoteUIHandlers,
        environment: SnapshotEnvironment = SnapshotEnvironment()
    ) {
        self.redaction = redaction
        self.writableKeys = writableKeys
        self.ruleEngine = ruleEngine
        self.handlers = handlers
        self.environment = environment
    }

    /// Wire the push channel (server broadcast). Called once by the server.
    public func setBroadcast(_ send: @escaping @Sendable (InspectorResponse) -> Void) {
        broadcast = send
    }

    // MARK: - Snapshot ingestion (pipeline consumer)

    public func ingest(_ raw: Snapshot) {
        let redacted = Redactor.redact(raw, policy: redaction)
        defer { current = redacted }

        guard let previous = current else {
            // First snapshot of the session: clients that already connected
            // learn about it through the root push.
            broadcast?(.root(
                version: redacted.version,
                rootIDs: redacted.rootIDs,
                nodeCount: redacted.nodeCount
            ))
            return
        }

        let changes = SnapshotDiff.changes(from: previous, to: redacted)
        guard !changes.isEmpty else { return }
        // Push invalidation, not content: clients refetch only what they
        // display. added+changed are refetchable; removed is a local prune.
        broadcast?(.invalidate(
            version: redacted.version,
            invalidated: changes.added.union(changes.changed).sorted { $0.rawValue < $1.rawValue },
            removed: changes.removed.sorted { $0.rawValue < $1.rawValue },
            rootIDs: redacted.rootIDs
        ))
    }

    /// Device-side selection (tap-to-select) forwarded to connected tools.
    public func pushSelection(_ id: NodeID) {
        broadcast?(.select(id: id))
    }

    // MARK: - Request handling

    public func handle(_ request: InspectorRequest) async -> InspectorResponse {
        switch request {
        case .hello:
            // Token verification happens in the server layer before requests
            // reach the bridge; hello here just acknowledges.
            return .helloAck(appName: appName, version: current?.version ?? 0)

        case .getRoot:
            guard let current else { return .error(message: "No snapshot captured yet") }
            return .root(
                version: current.version,
                rootIDs: current.rootIDs,
                nodeCount: current.nodeCount
            )

        case .getNodes(let ids):
            guard let current else { return .error(message: "No snapshot captured yet") }
            return .nodes(version: current.version, nodes: ids.compactMap { current.nodes[$0] })

        case .getTree:
            guard let current else { return .error(message: "No snapshot captured yet") }
            return .tree(
                version: current.version,
                rootIDs: current.rootIDs,
                nodes: Array(current.nodes.values)
            )

        case .search(let query):
            guard let current else { return .error(message: "No snapshot captured yet") }
            return .searchResults(version: current.version, ids: current.search(query))

        case .highlight(let id):
            await handlers.highlight(id)
            return .ack(ok: true, detail: nil)

        case .setProperty(let id, let key, let value):
            // The allowlist is the security boundary for the write API: a remote
            // tool must never gain arbitrary mutation over a live app.
            guard writableKeys.contains(key) else {
                return .ack(ok: false, detail: "Property '\(key)' is not writable")
            }
            let ok = await handlers.setProperty(id, key, value)
            return .ack(ok: ok, detail: ok ? nil : "Set failed (node gone or unsupported)")

        case .getIssues:
            guard let current else { return .error(message: "No snapshot captured yet") }
            return .issues(version: current.version, issues: ruleEngine.evaluate(current))
        }
    }

    public func currentSnapshotJSON() throws -> Data {
        struct Export: Encodable {
            let version: UInt64
            let capturedAt: Date
            let environment: SnapshotEnvironment
            let rootIds: [NodeID]
            let nodes: [InspectorNode]
        }
        guard let current else { return Data("{}".utf8) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Export(
            version: current.version,
            capturedAt: current.capturedAt,
            environment: environment,
            rootIds: current.rootIDs,
            nodes: Array(current.nodes.values)
        ))
    }
}
