import XCTest
@testable import SpaceZCore

@MainActor
final class SnapshotDiffTests: XCTestCase {
    func testNoChangesProducesEmptyChangeSet() {
        let engine = makeEngine(roots: [TestElement("root", children: [TestElement("a")])])
        let first = engine.captureSnapshot()
        let second = engine.captureSnapshot()

        let changes = SnapshotDiff.changes(from: first, to: second)

        XCTAssertTrue(changes.isEmpty)
        XCTAssertEqual(changes.fromVersion, first.version)
        XCTAssertEqual(changes.toVersion, second.version)
    }

    func testPropertyChangeIsDetectedAsChanged() {
        let child = TestElement("child")
        let root = TestElement("root", children: [child])
        let engine = makeEngine(roots: [root])
        let before = engine.captureSnapshot()
        let childID = before[before.rootIDs[0]]!.children[0]

        child.alpha = 0.3
        let after = engine.captureSnapshot()
        let changes = SnapshotDiff.changes(from: before, to: after)

        XCTAssertEqual(changes.changed, [childID])
        XCTAssertTrue(changes.added.isEmpty)
        XCTAssertTrue(changes.removed.isEmpty)
    }

    func testAddedAndRemovedNodes() {
        let removable = TestElement("removable")
        let root = TestElement("root", children: [removable])
        let engine = makeEngine(roots: [root])
        let before = engine.captureSnapshot()
        let removedID = before[before.rootIDs[0]]!.children[0]

        root.children = [TestElement("fresh")]
        let after = engine.captureSnapshot()
        let changes = SnapshotDiff.changes(from: before, to: after)

        XCTAssertEqual(changes.removed, [removedID])
        XCTAssertEqual(changes.added.count, 1)
        // Parent's children list changed, so the parent is "changed".
        XCTAssertEqual(changes.changed, [before.rootIDs[0]])
        XCTAssertEqual(changes.invalidatedIDs.count, 3)
    }

    func testChangeIsLocalizedToSubtree() {
        // Only the mutated node should be invalidated — this is what makes
        // invalidation cheaper than full-tree transfer.
        let deep = TestElement("deep")
        let mid = TestElement("mid", children: [deep])
        let sibling = TestElement("sibling")
        let root = TestElement("root", children: [mid, sibling])
        let engine = makeEngine(roots: [root])
        let before = engine.captureSnapshot()

        deep.hidden = true
        let after = engine.captureSnapshot()
        let changes = SnapshotDiff.changes(from: before, to: after)

        XCTAssertEqual(changes.changed.count, 1)
        XCTAssertEqual(after[changes.changed.first!]?.type, "deep")
    }
}
