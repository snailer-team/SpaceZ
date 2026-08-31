import XCTest
@testable import SpaceZCore

final class RedactorTests: XCTestCase {
    private func node(text: String?) -> InspectorNode {
        InspectorNode(
            id: NodeID(rawValue: 1),
            type: "UILabel",
            identifier: "CardNumberLabel",
            label: text,
            accessibilityLabel: text,
            properties: text.map { ["text": .string($0), "tag": .number(3)] } ?? [:]
        )
    }

    func testStrictPolicyRedactsSensitiveKeysAndTextualFields() {
        let redacted = Redactor.redact(node(text: "4242 4242 4242 4242"), policy: .strict)

        XCTAssertEqual(redacted.properties["text"], .redacted)
        XCTAssertEqual(redacted.properties["tag"], .number(3), "non-sensitive keys untouched")
        XCTAssertEqual(redacted.label, "***")
        XCTAssertEqual(redacted.accessibilityLabel, "***")
        XCTAssertEqual(
            redacted.identifier, "CardNumberLabel",
            "developer-authored identifiers are not user content — search must keep working"
        )
    }

    func testNilTextualFieldsStayNil() {
        // "has no accessibility label" is diagnostic data; redaction must not
        // fabricate a value where none existed.
        let redacted = Redactor.redact(node(text: nil), policy: .strict)
        XCTAssertNil(redacted.label)
        XCTAssertNil(redacted.accessibilityLabel)
    }

    func testNonePolicyPassesThrough() {
        let original = node(text: "hello")
        let redacted = Redactor.redact(original, policy: .none)
        XCTAssertEqual(redacted, original)
    }

    func testStructureSurvivesRedaction() {
        let id = NodeID(rawValue: 7)
        let child = NodeID(rawValue: 8)
        let snapshot = Snapshot(
            version: 1,
            rootIDs: [id],
            nodes: [
                id: InspectorNode(id: id, type: "root", children: [child]),
                child: InspectorNode(id: child, type: "leaf"),
            ]
        )
        let redacted = Redactor.redact(snapshot, policy: .strict)
        XCTAssertEqual(redacted.nodes[id]?.children, [child])
        XCTAssertEqual(redacted.version, snapshot.version)
        XCTAssertEqual(redacted.nodeCount, 2)
    }
}

final class SnapshotSearchTests: XCTestCase {
    private var snapshot: Snapshot {
        let button = InspectorNode(
            id: NodeID(rawValue: 1),
            type: "UIButton",
            identifier: "PayButton",
            alpha: 1,
            isUserInteractionEnabled: true
        )
        let overlay = InspectorNode(
            id: NodeID(rawValue: 2),
            type: "LoadingOverlay",
            alpha: 0,
            isUserInteractionEnabled: true
        )
        let label = InspectorNode(
            id: NodeID(rawValue: 3),
            type: "UILabel",
            accessibilityLabel: "Price",
            properties: ["text": .string("₩10,000")]
        )
        return Snapshot(
            version: 1,
            rootIDs: [button.id],
            nodes: [button.id: button, overlay.id: overlay, label.id: label]
        )
    }

    func testPlainTextMatchesTypeAndIdentifier() {
        // "PayButton" lives in `identifier` — the redaction-surviving field —
        // so this exact search works over the remote protocol too.
        XCTAssertEqual(snapshot.search("paybutton"), [NodeID(rawValue: 1)])
        XCTAssertEqual(Set(snapshot.search("UI")), [NodeID(rawValue: 1), NodeID(rawValue: 3)])
    }

    func testAttributeQueries() {
        XCTAssertEqual(snapshot.search("alpha=0"), [NodeID(rawValue: 2)])
        XCTAssertEqual(
            Set(snapshot.search("accessibilityLabel=nil")),
            [NodeID(rawValue: 1), NodeID(rawValue: 2)]
        )
        XCTAssertEqual(
            Set(snapshot.search("interaction=true")),
            [NodeID(rawValue: 1), NodeID(rawValue: 2)]
        )
        XCTAssertEqual(snapshot.search("text=10,000"), [NodeID(rawValue: 3)])
    }

    func testEmptyQueryReturnsNothing() {
        XCTAssertEqual(snapshot.search("  "), [])
    }
}
