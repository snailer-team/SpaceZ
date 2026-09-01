import CoreGraphics
import Foundation

/// A property value captured from a UI object.
///
/// Values are plain data so a snapshot can cross the main-thread boundary and
/// the process boundary (JSON) without retaining any UI object.
public enum InspectorValue: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case rect(CGRect)
    case size(CGSize)
    case point(CGPoint)
    /// CSS-style color, e.g. `#RRGGBBAA`.
    case color(String)
    /// A value that was removed by the redaction policy before transport.
    case redacted
    case null

    public var displayString: String {
        switch self {
        case .string(let value): return value
        case .number(let value):
            return value == value.rounded() && abs(value) < 1e12
                ? String(Int64(value))
                : String(format: "%.2f", value)
        case .bool(let value): return value ? "true" : "false"
        case .rect(let rect):
            return String(
                format: "(%.1f, %.1f, %.1f, %.1f)",
                rect.origin.x, rect.origin.y, rect.size.width, rect.size.height
            )
        case .size(let size): return String(format: "(%.1f, %.1f)", size.width, size.height)
        case .point(let point): return String(format: "(%.1f, %.1f)", point.x, point.y)
        case .color(let hex): return hex
        case .redacted: return "[REDACTED]"
        case .null: return "nil"
        }
    }
}

extension InspectorValue: Codable {
    private enum Kind: String, Codable {
        case string, number, bool, rect, size, point, color, redacted, null
    }

    private enum CodingKeys: String, CodingKey {
        case kind = "k"
        case value = "v"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .string: self = .string(try container.decode(String.self, forKey: .value))
        case .number: self = .number(try container.decode(Double.self, forKey: .value))
        case .bool: self = .bool(try container.decode(Bool.self, forKey: .value))
        case .rect:
            let values = try container.decode([Double].self, forKey: .value)
            self = .rect(CGRect(x: values[0], y: values[1], width: values[2], height: values[3]))
        case .size:
            let values = try container.decode([Double].self, forKey: .value)
            self = .size(CGSize(width: values[0], height: values[1]))
        case .point:
            let values = try container.decode([Double].self, forKey: .value)
            self = .point(CGPoint(x: values[0], y: values[1]))
        case .color: self = .color(try container.decode(String.self, forKey: .value))
        case .redacted: self = .redacted
        case .null: self = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let value):
            try container.encode(Kind.string, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .number(let value):
            try container.encode(Kind.number, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .bool(let value):
            try container.encode(Kind.bool, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .rect(let rect):
            try container.encode(Kind.rect, forKey: .kind)
            try container.encode(
                [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height],
                forKey: .value
            )
        case .size(let size):
            try container.encode(Kind.size, forKey: .kind)
            try container.encode([size.width, size.height], forKey: .value)
        case .point(let point):
            try container.encode(Kind.point, forKey: .kind)
            try container.encode([point.x, point.y], forKey: .value)
        case .color(let hex):
            try container.encode(Kind.color, forKey: .kind)
            try container.encode(hex, forKey: .value)
        case .redacted:
            try container.encode(Kind.redacted, forKey: .kind)
        case .null:
            try container.encode(Kind.null, forKey: .kind)
        }
    }
}
