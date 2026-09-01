import XCTest
@testable import SpaceZCore
@testable import SpaceZRemote
@testable import SpaceZRules

final class InspectorProtocolTests: XCTestCase {
    private func roundTripRequest(_ request: InspectorRequest) throws -> InspectorRequest {
        let data = try JSONEncoder().encode(request)
        return try InspectorCodec.decodeRequest(data)
    }

    func testRequestRoundTrips() throws {
        let requests: [InspectorRequest] = [
            .hello(token: "abc123"),
            .getRoot,
            .getNodes(ids: [NodeID(rawValue: 1), NodeID(rawValue: 27)]),
            .getTree,
            .search(query: "alpha=0"),
            .highlight(id: NodeID(rawValue: 42)),
            .highlight(id: nil),
            .setProperty(id: NodeID(rawValue: 5), key: "alpha", value: .number(0.5)),
            .getIssues,
        ]
        for request in requests {
            XCTAssertEqual(try roundTripRequest(request), request)
        }
    }

    func testResponseEncodesJSTypedFields() throws {
        let node = InspectorNode(
            id: NodeID(rawValue: 9),
            type: "UIButton",
            frame: CGRect(x: 1, y: 2, width: 3, height: 4),
            children: [NodeID(rawValue: 10)]
        )
        let data = try InspectorCodec.encode(.nodes(version: 7, nodes: [node]))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "nodes")
        XCTAssertEqual(json["version"] as? UInt64, 7)
        let first = (json["nodes"] as! [[String: Any]])[0]
        // NodeID must serialize as a bare number (the web client uses it as a
        // Map key), and CGRect as [[x, y], [w, h]].
        XCTAssertEqual(first["id"] as? UInt64, 9)
        XCTAssertEqual(first["children"] as? [UInt64], [10])
        let frame = first["frame"] as! [[Double]]
        XCTAssertEqual(frame, [[1, 2], [3, 4]])
    }

    func testUnknownRequestTypeThrows() {
        let data = Data(#"{"type":"formatDisk"}"#.utf8)
        XCTAssertThrowsError(try InspectorCodec.decodeRequest(data))
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try InspectorCodec.decodeRequest(Data("not json".utf8)))
    }

    func testIssueSerializes() throws {
        let issue = Issue(
            ruleID: "invisible-interaction",
            nodeID: NodeID(rawValue: 3),
            severity: .error,
            message: "covered",
            suggestion: "fix it"
        )
        let data = try InspectorCodec.encode(.issues(version: 1, issues: [issue]))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let first = (json["issues"] as! [[String: Any]])[0]
        XCTAssertEqual(first["severity"] as? String, "error")
        XCTAssertEqual(first["nodeID"] as? UInt64, 3)
    }
}

final class HTTPRequestTests: XCTestCase {
    func testParsesRequestLineAndQuery() {
        let raw = Data("GET /?token=abc%20d&x=1 HTTP/1.1\r\nHost: x\r\n\r\n".utf8)
        let request = HTTPRequest.parse(raw)
        XCTAssertEqual(request?.method, "GET")
        XCTAssertEqual(request?.path, "/")
        XCTAssertEqual(request?.query["token"], "abc d")
        XCTAssertEqual(request?.query["x"], "1")
    }

    func testIncompleteHeadReturnsNil() {
        XCTAssertNil(HTTPRequest.parse(Data("GET / HTTP/1.1\r\nHost:".utf8)))
    }

    func testResponseFormatting() {
        let response = HTTPResponse.ok(contentType: "text/html", body: Data("hi".utf8))
        let text = String(data: response, encoding: .utf8)!
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(text.contains("Content-Length: 2"))
        XCTAssertTrue(text.hasSuffix("\r\n\r\nhi"))
    }
}

final class RemoteBridgeTests: XCTestCase {
    private func makeBridge(
        writable: Set<String> = ["alpha"],
        onSet: (@Sendable (NodeID, String, InspectorValue) -> Bool)? = nil
    ) -> RemoteBridge {
        RemoteBridge(
            redaction: .strict,
            writableKeys: writable,
            handlers: RemoteUIHandlers(
                highlight: { _ in },
                setProperty: { id, key, value in onSet?(id, key, value) ?? true }
            )
        )
    }

    private func snapshot(
        version: UInt64 = 1, text: String = "secret", alpha: Double = 1
    ) -> Snapshot {
        let id = NodeID(rawValue: 1)
        return Snapshot(
            version: version,
            rootIDs: [id],
            nodes: [id: InspectorNode(
                id: id, type: "UILabel", alpha: alpha,
                properties: ["text": .string(text)]
            )]
        )
    }

    func testIngestRedactsBeforeServing() async {
        let bridge = makeBridge()
        await bridge.ingest(snapshot())

        let response = await bridge.handle(.getNodes(ids: [NodeID(rawValue: 1)]))
        guard case .nodes(_, let nodes) = response else {
            return XCTFail("expected nodes response")
        }
        XCTAssertEqual(
            nodes[0].properties["text"], .redacted,
            "raw text must never be servable from the bridge"
        )
    }

    func testSetPropertyRejectsNonAllowlistedKey() async {
        let bridge = makeBridge(writable: ["alpha"])
        await bridge.ingest(snapshot())

        let response = await bridge.handle(
            .setProperty(id: NodeID(rawValue: 1), key: "text", value: .string("pwned"))
        )
        guard case .ack(let ok, _) = response else { return XCTFail("expected ack") }
        XCTAssertFalse(ok)
    }

    func testSetPropertyAllowsAllowlistedKey() async {
        let bridge = makeBridge(writable: ["alpha"])
        await bridge.ingest(snapshot())

        let response = await bridge.handle(
            .setProperty(id: NodeID(rawValue: 1), key: "alpha", value: .number(0.5))
        )
        guard case .ack(let ok, _) = response else { return XCTFail("expected ack") }
        XCTAssertTrue(ok)
    }

    func testChangePushesInvalidationNotContent() async {
        let bridge = makeBridge()
        let received = ReceivedBox()
        // Append synchronously so push order is preserved deterministically.
        await bridge.setBroadcast { response in
            received.append(response)
        }

        await bridge.ingest(snapshot(version: 1, text: "a"))
        // Redaction maps both texts to [REDACTED]; redacted content is
        // identical, so this change is invisible to clients → no push.
        await bridge.ingest(snapshot(version: 2, text: "b"))
        // A visible change (alpha) must push an invalidation carrying IDs,
        // never node content.
        await bridge.ingest(snapshot(version: 3, text: "b", alpha: 0.4))

        let messages = received.snapshotMessages()
        XCTAssertEqual(messages.count, 2)
        guard case .root = messages[0] else { return XCTFail("expected root push first") }
        guard case .invalidate(let version, let invalidated, let removed, _) = messages[1] else {
            return XCTFail("expected invalidate push")
        }
        XCTAssertEqual(version, 3)
        XCTAssertEqual(invalidated, [NodeID(rawValue: 1)])
        XCTAssertTrue(removed.isEmpty)
    }
}

private final class ReceivedBox: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [InspectorResponse] = []

    func append(_ response: InspectorResponse) {
        lock.lock()
        defer { lock.unlock() }
        messages.append(response)
    }

    func snapshotMessages() -> [InspectorResponse] {
        lock.lock()
        defer { lock.unlock() }
        return messages
    }
}
