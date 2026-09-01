import Foundation
import SpaceZCore

/// Context handed to rules alongside each node: precomputed indexes so a rule
/// never walks the whole tree itself (N rules × N nodes must stay O(N·rules),
/// not O(N²)).
public struct InspectionContext: Sendable {
    public let snapshot: Snapshot
    public let depths: [NodeID: Int]
    public let parents: [NodeID: NodeID]

    public init(snapshot: Snapshot) {
        self.snapshot = snapshot
        self.depths = snapshot.depths()
        self.parents = snapshot.parentIndex()
    }

    public func parent(of id: NodeID) -> InspectorNode? {
        parents[id].flatMap { snapshot.nodes[$0] }
    }
}

/// A diagnostic rule. Rules see snapshot values only — they run off-main and
/// are decoupled from the collector, so adding a rule never touches capture.
public protocol UIRule: Sendable {
    var id: String { get }
    func inspect(node: InspectorNode, context: InspectionContext) -> [Issue]
}

/// Evaluates all registered rules against a snapshot.
public struct RuleEngine: Sendable {
    public private(set) var rules: [any UIRule]

    public init(rules: [any UIRule] = RuleEngine.builtInRules) {
        self.rules = rules
    }

    public static var builtInRules: [any UIRule] {
        [
            InvisibleInteractionRule(),
            MissingAccessibilityLabelRule(),
            DeepHierarchyRule(),
            MassiveSiblingsRule(),
            ClippedChildRule(),
            HiddenSubtreeRule(),
        ]
    }

    public mutating func register(_ rule: any UIRule) {
        rules.append(rule)
    }

    public func evaluate(_ snapshot: Snapshot) -> [Issue] {
        let context = InspectionContext(snapshot: snapshot)
        var issues: [Issue] = []
        for node in snapshot.nodes.values {
            for rule in rules {
                issues.append(contentsOf: rule.inspect(node: node, context: context))
            }
        }
        // Stable, severity-first ordering for display.
        return issues.sorted {
            $0.severity == $1.severity ? $0.id < $1.id : $0.severity > $1.severity
        }
    }
}
