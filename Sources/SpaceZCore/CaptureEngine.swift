import Foundation

/// Walks the live UI and produces an immutable ``Snapshot``.
///
/// This is the only component that touches UI objects, and it runs entirely on
/// the main actor. Its job ends at "copy primitive values out"; everything
/// else (diff, rules, redaction, encoding, transport) happens off-main on
/// snapshot values. That split is a correctness constraint (UIKit is
/// main-thread-only), not just an optimization.
@MainActor
public final class CaptureEngine {
    public let registry: NodeIDRegistry
    public let descriptors: DescriptorRegistry

    private var rootProviders: [RootProvider] = []
    private var version: UInt64 = 0
    // Rolling size estimate so the node dictionary doesn't rehash its way up
    // from empty on every capture (~5,000 inserts otherwise rehash ~12 times).
    private var lastNodeCount = 256

    public init(
        registry: NodeIDRegistry = NodeIDRegistry(),
        descriptors: DescriptorRegistry = DescriptorRegistry()
    ) {
        self.registry = registry
        self.descriptors = descriptors
    }

    public func addRootProvider(_ provider: RootProvider) {
        rootProviders.append(provider)
    }

    /// Captures the full hierarchy. Iterative traversal (explicit stack): a
    /// pathological 10,000-deep hierarchy must not overflow the real stack —
    /// the debugger surviving broken UIs is the whole point.
    public func captureSnapshot(maxDepth: Int = 512) -> Snapshot {
        let start = ContinuousClock.now
        version += 1

        var nodes: [NodeID: InspectorNode] = [:]
        nodes.reserveCapacity(lastNodeCount + lastNodeCount / 4)
        var rootIDs: [NodeID] = []

        for provider in rootProviders {
            for root in provider.rootObjects() {
                let id = capture(object: root, into: &nodes, maxDepth: maxDepth)
                rootIDs.append(id)
            }
        }

        lastNodeCount = nodes.count
        let elapsed = start.duration(to: .now)
        return Snapshot(
            version: version,
            rootIDs: rootIDs,
            nodes: nodes,
            captureDuration: Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18
        )
    }

    /// Captures a single subtree rooted at the object behind `id`.
    /// Used by the live-update path: after an invalidation only the dirty
    /// subtree is re-read, not the whole hierarchy.
    public func captureSubtree(of id: NodeID, maxDepth: Int = 512) -> [NodeID: InspectorNode]? {
        guard let object = registry.object(for: id) else { return nil }
        var nodes: [NodeID: InspectorNode] = [:]
        _ = capture(object: object, into: &nodes, maxDepth: maxDepth)
        return nodes
    }

    private func capture(
        object rootObject: AnyObject,
        into nodes: inout [NodeID: InspectorNode],
        maxDepth: Int
    ) -> NodeID {
        // Post-order via explicit stack: children must be captured before the
        // parent node is finalized, because the parent stores child IDs.
        struct Frame {
            let object: AnyObject
            let id: NodeID
            let depth: Int
            var pendingChildren: [AnyObject]
            var childIDs: [NodeID] = []
        }

        // pendingChildren is kept reversed so the next child comes from
        // popLast() (O(1)) instead of removeFirst() (O(n) per sibling).
        let rootID = registry.id(for: rootObject)
        let rootDescriptor = descriptors.descriptor(for: rootObject)
        var stack: [Frame] = [
            Frame(
                object: rootObject,
                id: rootID,
                depth: 0,
                pendingChildren: rootDescriptor.children(of: rootObject).reversed()
            )
        ]

        while !stack.isEmpty {
            if stack[stack.count - 1].pendingChildren.isEmpty {
                // All children done → finalize this node.
                let frame = stack.removeLast()
                let descriptor = descriptors.descriptor(for: frame.object)
                let content = descriptor.capture(frame.object)
                nodes[frame.id] = InspectorNode(
                    id: frame.id,
                    type: content.type,
                    identifier: content.identifier,
                    label: content.label,
                    frame: content.frame,
                    alpha: content.alpha,
                    isHidden: content.isHidden,
                    clipsToBounds: content.clipsToBounds,
                    isUserInteractionEnabled: content.isUserInteractionEnabled,
                    accessibilityLabel: content.accessibilityLabel,
                    children: frame.childIDs,
                    properties: content.properties
                )
                if !stack.isEmpty {
                    stack[stack.count - 1].childIDs.append(frame.id)
                }
            } else {
                let child = stack[stack.count - 1].pendingChildren.removeLast()
                let depth = stack[stack.count - 1].depth + 1
                let childID = registry.id(for: child)
                if depth >= maxDepth {
                    // Truncate instead of recursing forever on cyclic or
                    // absurdly deep hierarchies.
                    nodes[childID] = InspectorNode(
                        id: childID,
                        type: String(describing: Swift.type(of: child)),
                        label: "⚠ truncated at depth \(maxDepth)"
                    )
                    stack[stack.count - 1].childIDs.append(childID)
                    continue
                }
                let descriptor = descriptors.descriptor(for: child)
                stack.append(
                    Frame(
                        object: child,
                        id: childID,
                        depth: depth,
                        pendingChildren: descriptor.children(of: child).reversed()
                    )
                )
            }
        }

        return rootID
    }
}
