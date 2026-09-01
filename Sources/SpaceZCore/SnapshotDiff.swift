import Foundation

/// Which nodes changed between two snapshots.
///
/// Because NodeIDs are identity-stable, diffing is a dictionary walk —
/// O(N) with a small constant — not a tree-edit-distance computation. The
/// debugger doesn't need the minimal edit script, only "which IDs should the
/// client refetch", which turns the tree-diff problem into cache invalidation.
public struct SnapshotChangeSet: Sendable, Equatable {
    public let fromVersion: UInt64
    public let toVersion: UInt64
    public let added: Set<NodeID>
    public let removed: Set<NodeID>
    public let changed: Set<NodeID>

    public var isEmpty: Bool { added.isEmpty && removed.isEmpty && changed.isEmpty }

    /// All IDs a remote client should invalidate in its cache.
    public var invalidatedIDs: Set<NodeID> {
        added.union(removed).union(changed)
    }
}

public enum SnapshotDiff {
    public static func changes(from old: Snapshot, to new: Snapshot) -> SnapshotChangeSet {
        var added: Set<NodeID> = []
        var removed: Set<NodeID> = []
        var changed: Set<NodeID> = []

        for (id, newNode) in new.nodes {
            if let oldNode = old.nodes[id] {
                if oldNode.contentFingerprint != newNode.contentFingerprint {
                    changed.insert(id)
                }
            } else {
                added.insert(id)
            }
        }
        for id in old.nodes.keys where new.nodes[id] == nil {
            removed.insert(id)
        }

        return SnapshotChangeSet(
            fromVersion: old.version,
            toVersion: new.version,
            added: added,
            removed: removed,
            changed: changed
        )
    }
}
