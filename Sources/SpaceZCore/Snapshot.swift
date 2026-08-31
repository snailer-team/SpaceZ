import Foundation

/// Immutable capture of the whole UI at one instant.
///
/// This is the value that crosses the main-thread boundary: everything past
/// the capture engine (diff, rules, redaction, encoding, transport) works on
/// `Snapshot` and never touches a live UI object.
public struct Snapshot: Sendable {
    /// Monotonically increasing per session. Lets a remote client detect that
    /// nodes fetched at different times belong to different UI states.
    public let version: UInt64
    public let capturedAt: Date
    /// Root nodes — one per window, in back-to-front order.
    public let rootIDs: [NodeID]
    public let nodes: [NodeID: InspectorNode]
    /// Wall-clock cost of the main-thread capture pass, for budget tracking.
    public let captureDuration: TimeInterval

    public init(
        version: UInt64,
        capturedAt: Date = Date(),
        rootIDs: [NodeID],
        nodes: [NodeID: InspectorNode],
        captureDuration: TimeInterval = 0
    ) {
        self.version = version
        self.capturedAt = capturedAt
        self.rootIDs = rootIDs
        self.nodes = nodes
        self.captureDuration = captureDuration
    }

    public var nodeCount: Int { nodes.count }

    public subscript(id: NodeID) -> InspectorNode? { nodes[id] }

    /// Combined fingerprint of every node. Two snapshots with equal
    /// fingerprints render identically, so publishing the newer one is a no-op.
    public var fingerprint: UInt64 {
        // XOR keeps the fold order-independent so we can iterate the dictionary
        // without sorting 5,000 keys on every capture.
        var combined: UInt64 = 0
        for node in nodes.values {
            combined ^= node.contentFingerprint
        }
        var hasher = FNV1a()
        hasher.combine(combined)
        for root in rootIDs { hasher.combine(root.rawValue) }
        return hasher.value
    }

    /// Depth of a node from its root, walking the parent index lazily.
    public func depths() -> [NodeID: Int] {
        var result: [NodeID: Int] = [:]
        result.reserveCapacity(nodes.count)
        var stack: [(NodeID, Int)] = rootIDs.map { ($0, 0) }
        while let (id, depth) = stack.popLast() {
            result[id] = depth
            guard let node = nodes[id] else { continue }
            for child in node.children {
                stack.append((child, depth + 1))
            }
        }
        return result
    }

    /// Parent lookup table built from the children lists.
    public func parentIndex() -> [NodeID: NodeID] {
        var result: [NodeID: NodeID] = [:]
        result.reserveCapacity(nodes.count)
        for node in nodes.values {
            for child in node.children {
                result[child] = node.id
            }
        }
        return result
    }
}
