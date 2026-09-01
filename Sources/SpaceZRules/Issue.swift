import Foundation
import SpaceZCore

/// One problem a rule found in a snapshot.
public struct Issue: Sendable, Codable, Equatable, Identifiable {
    public enum Severity: String, Sendable, Codable, Comparable {
        case info, warning, error

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            let order: [Severity] = [.info, .warning, .error]
            return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
        }
    }

    public let id: String
    /// Rule that produced this issue (e.g. `invisible-interaction`).
    public let ruleID: String
    public let nodeID: NodeID
    public let severity: Severity
    public let message: String
    /// Suggested fix, when the rule can offer one.
    public let suggestion: String?

    public init(
        ruleID: String,
        nodeID: NodeID,
        severity: Severity,
        message: String,
        suggestion: String? = nil
    ) {
        self.id = "\(ruleID)/\(nodeID.rawValue)"
        self.ruleID = ruleID
        self.nodeID = nodeID
        self.severity = severity
        self.message = message
        self.suggestion = suggestion
    }
}
