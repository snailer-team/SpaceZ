import Foundation

/// Strips user content from snapshots before they leave the device.
///
/// A UI hierarchy carries more PII than it looks: `UILabel.text`,
/// `UITextField.text`, `accessibilityLabel` can hold card numbers, emails,
/// medical text. The on-device overlay shows raw values (the developer already
/// sees the screen); anything crossing the process boundary goes through this
/// first, and remote transport redacts **by default** — opting out is the
/// explicit act.
public struct RedactionPolicy: Sendable {
    /// Property keys whose values are replaced with `.redacted`.
    public var sensitiveKeys: Set<String>
    /// Also blank the free-text node fields (`label`, `accessibilityLabel`).
    public var redactsTextualFields: Bool

    public init(
        sensitiveKeys: Set<String> = RedactionPolicy.defaultSensitiveKeys,
        redactsTextualFields: Bool = true
    ) {
        self.sensitiveKeys = sensitiveKeys
        self.redactsTextualFields = redactsTextualFields
    }

    public static let defaultSensitiveKeys: Set<String> = [
        "text", "attributedText", "placeholder", "title", "accessibilityValue",
    ]

    /// Redact everything textual. Default for remote transport.
    public static let strict = RedactionPolicy()

    /// No redaction. Only reasonable for a developer's own debug build on a
    /// trusted network — never make this a library default.
    public static let none = RedactionPolicy(sensitiveKeys: [], redactsTextualFields: false)
}

public enum Redactor {
    public static func redact(_ snapshot: Snapshot, policy: RedactionPolicy) -> Snapshot {
        guard policy.redactsTextualFields || !policy.sensitiveKeys.isEmpty else {
            return snapshot
        }
        var redactedNodes: [NodeID: InspectorNode] = [:]
        redactedNodes.reserveCapacity(snapshot.nodes.count)
        for (id, node) in snapshot.nodes {
            redactedNodes[id] = redact(node, policy: policy)
        }
        return Snapshot(
            version: snapshot.version,
            capturedAt: snapshot.capturedAt,
            rootIDs: snapshot.rootIDs,
            nodes: redactedNodes,
            captureDuration: snapshot.captureDuration
        )
    }

    public static func redact(_ node: InspectorNode, policy: RedactionPolicy) -> InspectorNode {
        var properties = node.properties
        for key in policy.sensitiveKeys where properties[key] != nil {
            properties[key] = .redacted
        }
        return InspectorNode(
            id: node.id,
            type: node.type,
            // `identifier` is developer-authored (accessibilityIdentifier),
            // not user content — it survives redaction so remote search by
            // identifier keeps working.
            identifier: node.identifier,
            // `label` embeds content previews, so it falls under textual
            // fields. nil-ness is preserved — "has no accessibility label" is
            // itself diagnostic data and not sensitive.
            label: policy.redactsTextualFields ? node.label.map { _ in "***" } : node.label,
            frame: node.frame,
            alpha: node.alpha,
            isHidden: node.isHidden,
            clipsToBounds: node.clipsToBounds,
            isUserInteractionEnabled: node.isUserInteractionEnabled,
            accessibilityLabel: policy.redactsTextualFields
                ? node.accessibilityLabel.map { _ in "***" }
                : node.accessibilityLabel,
            children: node.children,
            properties: properties
        )
    }
}
