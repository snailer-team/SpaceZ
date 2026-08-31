import Foundation

/// Stable identifier for a UI object within one debug session.
///
/// IDs are assigned by ``NodeIDRegistry`` per live object identity, so the same
/// view keeps the same ID across captures. IDs are **not** persistent across
/// process launches.
public struct NodeID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public var description: String { "#\(rawValue)" }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UInt64.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
