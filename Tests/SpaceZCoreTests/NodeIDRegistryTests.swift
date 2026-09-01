import XCTest
@testable import SpaceZCore

@MainActor
final class NodeIDRegistryTests: XCTestCase {
    func testSameObjectKeepsSameID() {
        let registry = NodeIDRegistry()
        let object = NSObject()
        let first = registry.id(for: object)
        let second = registry.id(for: object)
        XCTAssertEqual(first, second)
    }

    func testDistinctObjectsGetDistinctIDs() {
        let registry = NodeIDRegistry()
        let a = NSObject()
        let b = NSObject()
        XCTAssertNotEqual(registry.id(for: a), registry.id(for: b))
    }

    func testReverseLookupReturnsLiveObject() {
        let registry = NodeIDRegistry()
        let object = NSObject()
        let id = registry.id(for: object)
        XCTAssertTrue(registry.object(for: id) === object)
    }

    func testReverseLookupIsNilAfterDeallocation() {
        let registry = NodeIDRegistry()
        var id: NodeID?
        autoreleasepool {
            let object = NSObject()
            id = registry.id(for: object)
        }
        // Weak value: once the object is gone the mapping must not resurrect it.
        XCTAssertNil(registry.object(for: id!))
    }

    func testIDsSurviveSiblingReordering() {
        // Identity-based IDs must not depend on traversal position — this is
        // the property positional IDs ("0.1.3") lack.
        let registry = NodeIDRegistry()
        let a = NSObject()
        let b = NSObject()
        let idA = registry.id(for: a)
        let idB = registry.id(for: b)
        // "Reorder": query in the opposite order.
        XCTAssertEqual(registry.id(for: b), idB)
        XCTAssertEqual(registry.id(for: a), idA)
    }

    func testResetForgetsEverything() {
        let registry = NodeIDRegistry()
        let object = NSObject()
        let before = registry.id(for: object)
        registry.reset()
        let after = registry.id(for: object)
        XCTAssertEqual(after.rawValue, 1)
        XCTAssertEqual(before.rawValue, 1)
    }
}
