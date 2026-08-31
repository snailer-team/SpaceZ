import CoreGraphics
import Foundation

/// Everything a descriptor reads from one UI object, as plain values.
public struct CapturedNodeContent: Sendable {
    public var type: String
    /// Developer-authored identifier — survives redaction.
    public var identifier: String?
    /// Content-derived preview — redacted before transport.
    public var label: String?
    public var frame: CGRect
    public var alpha: Double
    public var isHidden: Bool
    public var clipsToBounds: Bool
    public var isUserInteractionEnabled: Bool
    public var accessibilityLabel: String?
    public var properties: [String: InspectorValue]

    public init(
        type: String,
        identifier: String? = nil,
        label: String? = nil,
        frame: CGRect = .zero,
        alpha: Double = 1,
        isHidden: Bool = false,
        clipsToBounds: Bool = false,
        isUserInteractionEnabled: Bool = false,
        accessibilityLabel: String? = nil,
        properties: [String: InspectorValue] = [:]
    ) {
        self.type = type
        self.identifier = identifier
        self.label = label
        self.frame = frame
        self.alpha = alpha
        self.isHidden = isHidden
        self.clipsToBounds = clipsToBounds
        self.isUserInteractionEnabled = isUserInteractionEnabled
        self.accessibilityLabel = accessibilityLabel
        self.properties = properties
    }
}

/// Adapter that teaches the capture engine one UI framework.
///
/// The engine itself never imports UIKit/SwiftUI — supporting a new framework
/// (or a company-internal one) is implementing this protocol and registering
/// it. Runs on the main actor because UI objects may only be read there.
@MainActor
public protocol NodeDescriptor: AnyObject {
    /// First descriptor (in registration order) that returns true wins.
    func supports(_ object: AnyObject) -> Bool
    /// Read the object's displayable state as plain values. Must not retain
    /// `object` or any of its properties beyond the call.
    func capture(_ object: AnyObject) -> CapturedNodeContent
    /// Child objects in z-order (back to front).
    func children(of object: AnyObject) -> [AnyObject]
    /// Best-effort mutation for the property-editing API. Only allowlisted
    /// keys ever reach this. Return false if the key is unsupported.
    func setProperty(_ key: String, to value: InspectorValue, on object: AnyObject) -> Bool
}

extension NodeDescriptor {
    public func setProperty(_ key: String, to value: InspectorValue, on object: AnyObject) -> Bool {
        false
    }
}

/// Ordered registry. Custom descriptors are consulted before built-ins so a
/// host app can override how its own component types are presented.
@MainActor
public final class DescriptorRegistry {
    private var descriptors: [NodeDescriptor] = []
    private let fallback = FallbackDescriptor()

    public init() {}

    public func register(_ descriptor: NodeDescriptor, prepend: Bool = false) {
        if prepend {
            descriptors.insert(descriptor, at: 0)
        } else {
            descriptors.append(descriptor)
        }
    }

    public func descriptor(for object: AnyObject) -> NodeDescriptor {
        descriptors.first { $0.supports(object) } ?? fallback
    }
}

/// Used when no registered descriptor claims an object: shows the type name
/// and stops traversal. Keeps unknown objects visible instead of crashing or
/// silently dropping the subtree.
@MainActor
final class FallbackDescriptor: NodeDescriptor {
    func supports(_ object: AnyObject) -> Bool { true }

    func capture(_ object: AnyObject) -> CapturedNodeContent {
        CapturedNodeContent(type: String(describing: Swift.type(of: object)))
    }

    func children(of object: AnyObject) -> [AnyObject] { [] }
}

/// Supplies the root objects of a capture (the app's windows on UIKit).
@MainActor
public protocol RootProvider: AnyObject {
    func rootObjects() -> [AnyObject]
}
