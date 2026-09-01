import Foundation

/// Off-main holder of the current snapshot with query support.
///
/// The store answers the inspector protocol's read side: node lookup by ID
/// (O(1)), partial fetch, and search — without ever touching a live view.
public actor NodeStore {
    public private(set) var current: Snapshot?

    public init() {}

    public func update(_ snapshot: Snapshot) {
        current = snapshot
    }

    public func node(_ id: NodeID) -> InspectorNode? {
        current?.nodes[id]
    }

    public func nodes(_ ids: [NodeID]) -> [InspectorNode] {
        guard let current else { return [] }
        return ids.compactMap { current.nodes[$0] }
    }

    public func search(_ query: String) -> [NodeID] {
        current?.search(query) ?? []
    }
}

extension Snapshot {
    /// Search syntax:
    /// - plain text → case-insensitive match on type, label, accessibilityLabel
    /// - `key=value` → attribute match, e.g. `alpha=0`, `accessibilityLabel=nil`,
    ///   `hidden=true`, or any captured property key.
    public func search(_ query: String) -> [NodeID] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        if let separator = trimmed.firstIndex(of: "=") {
            let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
            return nodes.values
                .filter { Self.matches(node: $0, key: key, value: value) }
                .map(\.id)
        }

        let needle = trimmed.lowercased()
        return nodes.values
            .filter { node in
                node.type.lowercased().contains(needle)
                    || node.identifier?.lowercased().contains(needle) == true
                    || node.label?.lowercased().contains(needle) == true
                    || node.accessibilityLabel?.lowercased().contains(needle) == true
            }
            .map(\.id)
    }

    private static func matches(node: InspectorNode, key: String, value: String) -> Bool {
        let lowered = value.lowercased()
        switch key.lowercased() {
        case "alpha":
            return Double(value).map { abs(node.alpha - $0) < 0.001 } ?? false
        case "hidden", "ishidden":
            return node.isHidden == (lowered == "true")
        case "interaction", "isuserinteractionenabled":
            return node.isUserInteractionEnabled == (lowered == "true")
        case "accessibilitylabel":
            if lowered == "nil" { return node.accessibilityLabel == nil }
            return node.accessibilityLabel?.lowercased().contains(lowered) == true
        case "type":
            return node.type.lowercased().contains(lowered)
        default:
            // "key=nil" matches nodes where the property is absent.
            guard let property = node.properties[key] else { return lowered == "nil" }
            return property.displayString.lowercased().contains(lowered)
        }
    }
}
