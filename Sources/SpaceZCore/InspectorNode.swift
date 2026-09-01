import CoreGraphics
import Foundation

/// One captured UI object, normalized for the node store.
///
/// Children are stored as IDs (`children: [NodeID]`), never as nested nodes.
/// This is what makes O(1) lookup, partial fetch, and subtree invalidation
/// possible — the same normalization Flipper's Layout Inspector protocol uses.
public struct InspectorNode: Sendable, Codable, Equatable, Identifiable {
    public let id: NodeID
    /// Short type name, e.g. `UILabel` or `SwiftUI:VStack`.
    public let type: String
    /// Developer-authored identifier (`accessibilityIdentifier`). Not user
    /// content, so redaction leaves it alone — remote search by identifier
    /// ("PayButton") must keep working with strict redaction on.
    public let identifier: String?
    /// Human hint derived from content (text/title preview). User data —
    /// redacted before leaving the device.
    public let label: String?
    /// Frame converted to window coordinates.
    public let frame: CGRect
    public let alpha: Double
    public let isHidden: Bool
    public let clipsToBounds: Bool
    public let isUserInteractionEnabled: Bool
    public let accessibilityLabel: String?
    public let children: [NodeID]
    /// Framework-specific extras, keyed by property name.
    public let properties: [String: InspectorValue]

    public init(
        id: NodeID,
        type: String,
        identifier: String? = nil,
        label: String? = nil,
        frame: CGRect = .zero,
        alpha: Double = 1,
        isHidden: Bool = false,
        clipsToBounds: Bool = false,
        isUserInteractionEnabled: Bool = false,
        accessibilityLabel: String? = nil,
        children: [NodeID] = [],
        properties: [String: InspectorValue] = [:]
    ) {
        self.id = id
        self.type = type
        self.identifier = identifier
        self.label = label
        self.frame = frame
        self.alpha = alpha
        self.isHidden = isHidden
        self.clipsToBounds = clipsToBounds
        self.isUserInteractionEnabled = isUserInteractionEnabled
        self.accessibilityLabel = accessibilityLabel
        self.children = children
        self.properties = properties
    }

    /// Cheap content hash used by the change detector to drop no-op captures
    /// and by the differ to find changed nodes without deep Equatable walks
    /// over the `properties` dictionary ordering.
    public var contentFingerprint: UInt64 {
        var hasher = FNV1a()
        hasher.combine(id.rawValue)
        hasher.combine(type)
        hasher.combine(identifier ?? "")
        hasher.combine(label ?? "")
        hasher.combine(frame)
        hasher.combine(alpha.bitPattern)
        hasher.combine(isHidden ? 1 : 0)
        hasher.combine(clipsToBounds ? 1 : 0)
        hasher.combine(isUserInteractionEnabled ? 1 : 0)
        hasher.combine(accessibilityLabel ?? "")
        for child in children { hasher.combine(child.rawValue) }
        // Properties participate via sorted keys so dictionary order is stable.
        for key in properties.keys.sorted() {
            hasher.combine(key)
            hasher.combine(properties[key]?.displayString ?? "")
        }
        return hasher.value
    }
}

/// FNV-1a: deterministic across launches, unlike Swift's seeded `Hasher`.
/// Determinism matters because fingerprints are compared across snapshots
/// and may be logged for debugging.
public struct FNV1a: Sendable {
    public private(set) var value: UInt64 = 0xcbf29ce484222325

    public init() {}

    public mutating func combine(_ int: UInt64) {
        for shift in stride(from: 0, to: 64, by: 8) {
            value ^= (int >> shift) & 0xFF
            value = value &* 0x100000001b3
        }
    }

    public mutating func combine(_ int: Int) {
        combine(UInt64(bitPattern: Int64(int)))
    }

    public mutating func combine(_ string: String) {
        for byte in string.utf8 {
            value ^= UInt64(byte)
            value = value &* 0x100000001b3
        }
    }

    public mutating func combine(_ rect: CGRect) {
        combine(rect.origin.x.native.bitPattern)
        combine(rect.origin.y.native.bitPattern)
        combine(rect.size.width.native.bitPattern)
        combine(rect.size.height.native.bitPattern)
    }
}
