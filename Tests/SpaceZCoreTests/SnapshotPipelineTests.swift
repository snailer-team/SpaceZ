import XCTest
@testable import SpaceZCore

final class SnapshotPipelineTests: XCTestCase {
    private func snapshot(version: UInt64, alpha: Double = 1) -> Snapshot {
        let id = NodeID(rawValue: 1)
        return Snapshot(
            version: version,
            rootIDs: [id],
            nodes: [id: InspectorNode(id: id, type: "root", alpha: alpha)]
        )
    }

    func testSubscriberReceivesLatestOnSubscribe() async {
        let pipeline = SnapshotPipeline()
        await pipeline.publish(snapshot(version: 1))

        let stream = await pipeline.subscribe()
        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()

        XCTAssertEqual(received?.version, 1)
    }

    func testIdenticalSnapshotIsSuppressed() async {
        let pipeline = SnapshotPipeline()
        let forwarded1 = await pipeline.publish(snapshot(version: 1))
        // Same content, new version — renders identically, so no forward.
        let forwarded2 = await pipeline.publish(snapshot(version: 2))
        let forwarded3 = await pipeline.publish(snapshot(version: 3, alpha: 0.5))

        XCTAssertTrue(forwarded1)
        XCTAssertFalse(forwarded2)
        XCTAssertTrue(forwarded3)
        let suppressed = await pipeline.suppressedNoOpCount
        XCTAssertEqual(suppressed, 1)
    }

    func testLatestStateWinsUnderBackpressure() async {
        // A slow consumer must see the newest state, not a backlog: publish a
        // burst before the consumer reads anything.
        let pipeline = SnapshotPipeline()
        let stream = await pipeline.subscribe()

        for version in 1...50 {
            await pipeline.publish(snapshot(version: UInt64(version), alpha: Double(version) / 100))
        }

        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        // bufferingNewest(1): the single buffered element is the newest one.
        XCTAssertEqual(first?.version, 50)
    }
}
