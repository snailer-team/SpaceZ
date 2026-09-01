import XCTest
@testable import SpaceZCore

@MainActor
final class CaptureEngineTests: XCTestCase {
    func testCapturesFullTreeNormalized() {
        // root ── a ── (b, c)  +  d
        let b = TestElement("b")
        let c = TestElement("c")
        let a = TestElement("a", children: [b, c])
        let d = TestElement("d")
        let root = TestElement("root", children: [a, d])
        let engine = makeEngine(roots: [root])

        let snapshot = engine.captureSnapshot()

        XCTAssertEqual(snapshot.nodeCount, 5)
        XCTAssertEqual(snapshot.rootIDs.count, 1)
        let rootNode = snapshot[snapshot.rootIDs[0]]!
        XCTAssertEqual(rootNode.type, "root")
        XCTAssertEqual(rootNode.children.count, 2)
        // Children stored as IDs, in declaration (z) order.
        let childTypes = rootNode.children.compactMap { snapshot[$0]?.type }
        XCTAssertEqual(childTypes, ["a", "d"])
        let aNode = snapshot[rootNode.children[0]]!
        XCTAssertEqual(aNode.children.compactMap { snapshot[$0]?.type }, ["b", "c"])
    }

    func testNodeIDsAreStableAcrossCaptures() {
        let child = TestElement("child")
        let root = TestElement("root", children: [child])
        let engine = makeEngine(roots: [root])

        let first = engine.captureSnapshot()
        let second = engine.captureSnapshot()

        XCTAssertEqual(first.rootIDs, second.rootIDs)
        XCTAssertEqual(
            Set(first.nodes.keys),
            Set(second.nodes.keys),
            "Same objects must keep the same NodeIDs across captures"
        )
    }

    func testInsertedSiblingDoesNotShiftExistingIDs() {
        let existing = TestElement("existing")
        let root = TestElement("root", children: [existing])
        let engine = makeEngine(roots: [root])
        let before = engine.captureSnapshot()
        let existingID = before[before.rootIDs[0]]!.children[0]

        root.children.insert(TestElement("inserted"), at: 0)
        let after = engine.captureSnapshot()

        let childIDs = after[after.rootIDs[0]]!.children
        XCTAssertEqual(childIDs.count, 2)
        XCTAssertEqual(childIDs[1], existingID, "existing sibling keeps its ID")
        XCTAssertEqual(after[childIDs[0]]?.type, "inserted")
    }

    func testDeepHierarchyDoesNotOverflowStack() {
        // 10,000 levels would crash a recursive traversal.
        var current = TestElement("leaf")
        for index in 0..<10_000 {
            current = TestElement("n\(index)", children: [current])
        }
        let engine = makeEngine(roots: [current])
        let snapshot = engine.captureSnapshot(maxDepth: 20_000)
        XCTAssertEqual(snapshot.nodeCount, 10_001)
    }

    func testMaxDepthTruncates() {
        var current = TestElement("leaf")
        for index in 0..<10 {
            current = TestElement("n\(index)", children: [current])
        }
        let engine = makeEngine(roots: [current])
        let snapshot = engine.captureSnapshot(maxDepth: 3)
        let depths = snapshot.depths()
        XCTAssertEqual(depths.values.max(), 3)
        // The truncated node is visibly marked, not silently dropped.
        XCTAssertTrue(snapshot.nodes.values.contains { $0.label?.contains("truncated") == true })
    }

    func testVersionIncreasesMonotonically() {
        let engine = makeEngine(roots: [TestElement("root")])
        let v1 = engine.captureSnapshot().version
        let v2 = engine.captureSnapshot().version
        XCTAssertGreaterThan(v2, v1)
    }

    func testSubtreeCaptureReturnsOnlySubtree() {
        let grandchild = TestElement("grandchild")
        let child = TestElement("child", children: [grandchild])
        let root = TestElement("root", children: [child, TestElement("other")])
        let engine = makeEngine(roots: [root])
        let full = engine.captureSnapshot()
        let childID = full[full.rootIDs[0]]!.children[0]

        let subtree = engine.captureSubtree(of: childID)!

        XCTAssertEqual(subtree.count, 2)
        XCTAssertEqual(Set(subtree.values.map(\.type)), ["child", "grandchild"])
    }

    func testFingerprintStableWhenNothingChanges() {
        let root = TestElement("root", children: [TestElement("a"), TestElement("b")])
        let engine = makeEngine(roots: [root])
        let first = engine.captureSnapshot()
        let second = engine.captureSnapshot()
        XCTAssertEqual(first.fingerprint, second.fingerprint)
    }

    func testFingerprintChangesWhenPropertyChanges() {
        let child = TestElement("child")
        let root = TestElement("root", children: [child])
        let engine = makeEngine(roots: [root])
        let before = engine.captureSnapshot()
        child.alpha = 0.5
        let after = engine.captureSnapshot()
        XCTAssertNotEqual(before.fingerprint, after.fingerprint)
    }
}
