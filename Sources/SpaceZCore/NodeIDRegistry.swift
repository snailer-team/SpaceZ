import Foundation

/// Assigns session-stable ``NodeID``s to live object identities.
///
/// Position-derived IDs ("0.1.3") shift when a sibling is inserted; identity
/// IDs survive any reordering, which is what makes cross-snapshot diffing and
/// subtree invalidation possible.
///
/// Both maps hold the UI object weakly, so the registry never extends an
/// object's lifetime and entries vanish when views are deallocated.
@MainActor
public final class NodeIDRegistry {
    // object → id. Weak keys: entries are purged by NSMapTable after dealloc.
    private let idsByObject = NSMapTable<AnyObject, NSNumber>(
        keyOptions: [.weakMemory, .objectPointerPersonality],
        valueOptions: .strongMemory
    )
    // id → object. Weak values for the same reason; used by highlight and
    // setProperty to get back from a NodeID to the live view.
    private let objectsByID = NSMapTable<NSNumber, AnyObject>(
        keyOptions: .strongMemory,
        valueOptions: [.weakMemory, .objectPointerPersonality]
    )
    private var nextID: UInt64 = 1

    public init() {}

    /// Returns the stable ID for `object`, minting one on first sight.
    public func id(for object: AnyObject) -> NodeID {
        if let existing = idsByObject.object(forKey: object) {
            return NodeID(rawValue: existing.uint64Value)
        }
        let id = NodeID(rawValue: nextID)
        nextID += 1
        let boxed = NSNumber(value: id.rawValue)
        idsByObject.setObject(boxed, forKey: object)
        objectsByID.setObject(object, forKey: boxed)
        return id
    }

    /// The live object for an ID, or nil if it was deallocated.
    public func object(for id: NodeID) -> AnyObject? {
        objectsByID.object(forKey: NSNumber(value: id.rawValue))
    }

    public func reset() {
        idsByObject.removeAllObjects()
        objectsByID.removeAllObjects()
        nextID = 1
    }
}
