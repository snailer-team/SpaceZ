import XCTest
@testable import SpaceZCore
@testable import SpaceZRules

final class BuiltInRulesTests: XCTestCase {
    private var nextID: UInt64 = 0

    private func makeNode(
        type: String = "UIView",
        frame: CGRect = CGRect(x: 0, y: 0, width: 200, height: 200),
        alpha: Double = 1,
        hidden: Bool = false,
        clips: Bool = false,
        interactive: Bool = false,
        accessibilityLabel: String? = nil,
        children: [NodeID] = [],
        properties: [String: InspectorValue] = [:]
    ) -> InspectorNode {
        nextID += 1
        return InspectorNode(
            id: NodeID(rawValue: nextID),
            type: type,
            frame: frame,
            alpha: alpha,
            isHidden: hidden,
            clipsToBounds: clips,
            isUserInteractionEnabled: interactive,
            accessibilityLabel: accessibilityLabel,
            children: children,
            properties: properties
        )
    }

    private func makeSnapshot(_ nodes: [InspectorNode], roots: [NodeID]? = nil) -> Snapshot {
        Snapshot(
            version: 1,
            rootIDs: roots ?? [nodes[0].id],
            nodes: Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        )
    }

    // MARK: - InvisibleInteraction

    func testInvisibleInteractiveOverlayIsFlagged() {
        // The lecture's canonical bug: LoadingOverlay alpha 0.01 over PayButton.
        let overlay = makeNode(
            type: "LoadingOverlay",
            frame: CGRect(x: 0, y: 0, width: 393, height: 852),
            alpha: 0.01,
            interactive: true
        )
        let snapshot = makeSnapshot([overlay])
        let issues = RuleEngine(rules: [InvisibleInteractionRule()]).evaluate(snapshot)

        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0].severity, .error)
        XCTAssertEqual(issues[0].nodeID, overlay.id)
    }

    func testVisibleOrInertViewsAreNotFlagged() {
        let visible = makeNode(alpha: 1, interactive: true)
        let inert = makeNode(alpha: 0.01, interactive: false)
        let tiny = makeNode(
            frame: CGRect(x: 0, y: 0, width: 10, height: 10), alpha: 0.01, interactive: true
        )
        let snapshot = makeSnapshot([visible, inert, tiny])
        XCTAssertTrue(RuleEngine(rules: [InvisibleInteractionRule()]).evaluate(snapshot).isEmpty)
    }

    // MARK: - MissingAccessibilityLabel

    func testUnlabeledButtonIsFlagged() {
        let button = makeNode(type: "UIButton", properties: ["title": .null])
        let snapshot = makeSnapshot([button])
        let issues = RuleEngine(rules: [MissingAccessibilityLabelRule()]).evaluate(snapshot)
        XCTAssertEqual(issues.map(\.nodeID), [button.id])
    }

    func testTitledOrLabeledButtonsPass() {
        let titled = makeNode(type: "UIButton", properties: ["title": .string("Pay")])
        let labeled = makeNode(type: "UIButton", accessibilityLabel: "Pay")
        let plainView = makeNode(type: "UIView")
        let snapshot = makeSnapshot([titled, labeled, plainView])
        XCTAssertTrue(
            RuleEngine(rules: [MissingAccessibilityLabelRule()]).evaluate(snapshot).isEmpty
        )
    }

    // MARK: - DeepHierarchy

    func testDepthThresholdFiresExactlyOncePerChain() {
        var nodes: [InspectorNode] = []
        var childID: NodeID?
        for _ in 0..<30 {
            let node = makeNode(children: childID.map { [$0] } ?? [])
            nodes.append(node)
            childID = node.id
        }
        let snapshot = makeSnapshot(nodes.reversed().map { $0 }, roots: [nodes.last!.id])
        let issues = RuleEngine(rules: [DeepHierarchyRule(maxDepth: 25)]).evaluate(snapshot)
        XCTAssertEqual(issues.count, 1, "one report at the crossing node, not per descendant")
    }

    // MARK: - MassiveSiblings

    func testTooManyChildrenIsFlagged() {
        let children = (0..<60).map { _ in makeNode() }
        let parent = makeNode(type: "UIStackView", children: children.map(\.id))
        let snapshot = makeSnapshot([parent] + children)
        let issues = RuleEngine(rules: [MassiveSiblingsRule(maxChildren: 50)]).evaluate(snapshot)
        XCTAssertEqual(issues.map(\.nodeID), [parent.id])
    }

    // MARK: - ClippedChild

    func testChildOutsideClippingParentIsFlagged() {
        let child = makeNode(frame: CGRect(x: 380, y: 0, width: 100, height: 40))
        let parent = makeNode(
            frame: CGRect(x: 0, y: 0, width: 393, height: 100),
            clips: true,
            children: [child.id]
        )
        let snapshot = makeSnapshot([parent, child])
        let issues = RuleEngine(rules: [ClippedChildRule()]).evaluate(snapshot)
        XCTAssertEqual(issues.map(\.nodeID), [child.id])
    }

    func testScrollViewChildrenAreExempt() {
        let child = makeNode(frame: CGRect(x: 0, y: 900, width: 393, height: 44))
        let scroll = makeNode(
            type: "UIScrollView",
            frame: CGRect(x: 0, y: 0, width: 393, height: 852),
            clips: true,
            children: [child.id]
        )
        let snapshot = makeSnapshot([scroll, child])
        XCTAssertTrue(RuleEngine(rules: [ClippedChildRule()]).evaluate(snapshot).isEmpty)
    }

    // MARK: - HiddenSubtree

    func testHiddenViewWithManyDescendantsIsFlaggedOnceAtTop() {
        let leaves = (0..<25).map { _ in makeNode() }
        let hiddenParent = makeNode(hidden: true, children: leaves.map(\.id))
        let root = makeNode(children: [hiddenParent.id])
        let snapshot = makeSnapshot([root, hiddenParent] + leaves, roots: [root.id])
        let issues = RuleEngine(
            rules: [HiddenSubtreeRule(minimumDescendants: 20)]
        ).evaluate(snapshot)
        XCTAssertEqual(issues.map(\.nodeID), [hiddenParent.id])
    }

    // MARK: - Engine ordering & extensibility

    func testIssuesSortedBySeverity() {
        let overlay = makeNode(alpha: 0.01, interactive: true)
        let children = (0..<60).map { _ in makeNode() }
        let crowded = makeNode(children: children.map(\.id))
        let snapshot = makeSnapshot([overlay, crowded] + children)
        let issues = RuleEngine(
            rules: [MassiveSiblingsRule(), InvisibleInteractionRule()]
        ).evaluate(snapshot)
        XCTAssertEqual(issues.first?.severity, .error)
    }

    func testCustomRuleCanBeRegistered() {
        struct DeprecatedComponentRule: UIRule {
            let id = "deprecated-component"
            func inspect(node: InspectorNode, context: InspectionContext) -> [Issue] {
                guard node.type == "DeprecatedPrimaryButton" else { return [] }
                return [Issue(
                    ruleID: id, nodeID: node.id, severity: .warning,
                    message: "Deprecated component", suggestion: "Use DesignSystem.PrimaryButton"
                )]
            }
        }
        let deprecated = makeNode(type: "DeprecatedPrimaryButton")
        var engine = RuleEngine(rules: [])
        engine.register(DeprecatedComponentRule())
        let issues = engine.evaluate(makeSnapshot([deprecated]))
        XCTAssertEqual(issues.map(\.ruleID), ["deprecated-component"])
    }
}
