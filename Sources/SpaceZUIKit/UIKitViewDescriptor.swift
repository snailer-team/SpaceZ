import SpaceZCore
import UIKit

/// Teaches the capture engine about `UIView`.
///
/// Reads only primitive values and copies them out — the returned
/// `CapturedNodeContent` holds no reference to the view. Cost per node is a
/// dozen objc property reads (~tens of ns each), which is what keeps a
/// 5,000-node capture around the 2 ms design budget.
@MainActor
public final class UIKitViewDescriptor: NodeDescriptor {
    public init() {}

    public func supports(_ object: AnyObject) -> Bool {
        object is UIView
    }

    public func children(of object: AnyObject) -> [AnyObject] {
        guard let view = object as? UIView else { return [] }
        return view.subviews
    }

    public func capture(_ object: AnyObject) -> CapturedNodeContent {
        guard let view = object as? UIView else {
            return CapturedNodeContent(type: String(describing: type(of: object)))
        }

        var properties: [String: InspectorValue] = [:]

        // Frame in window coordinates so the desktop canvas and the on-device
        // highlight agree on geometry regardless of nesting.
        let frameInWindow: CGRect
        if let window = view.window {
            frameInWindow = view.convert(view.bounds, to: window)
        } else {
            frameInWindow = view.frame
        }

        properties["bounds"] = .rect(view.bounds)
        properties["frame"] = .rect(view.frame)
        properties["tag"] = .number(Double(view.tag))
        if let backgroundColor = view.backgroundColor {
            properties["backgroundColor"] = .color(backgroundColor.spacezHexString)
        }
        properties["layer.zPosition"] = .number(Double(view.layer.zPosition))
        properties["contentMode"] = .string(view.contentMode.spacezName)

        var identifier: String?
        if let accessibilityIdentifier = view.accessibilityIdentifier,
           !accessibilityIdentifier.isEmpty {
            identifier = accessibilityIdentifier
        }
        var label: String?

        // Type-specific extras. Kept inline (not per-class descriptors) while
        // the list is this short; split when a class needs real logic.
        switch view {
        case let labelView as UILabel:
            properties["text"] = labelView.text.map(InspectorValue.string) ?? .null
            properties["font"] = .string(labelView.font.spacezDescription)
            properties["numberOfLines"] = .number(Double(labelView.numberOfLines))
            label = labelView.text.map { "\"\($0.spacezTruncated(40))\"" }
        case let button as UIButton:
            let title = button.title(for: .normal) ?? button.configuration?.title
            properties["title"] = title.map(InspectorValue.string) ?? .null
            properties["isEnabled"] = .bool(button.isEnabled)
            label = title.map { "\"\($0.spacezTruncated(40))\"" }
        case let textField as UITextField:
            properties["text"] = textField.text.map(InspectorValue.string) ?? .null
            properties["placeholder"] = textField.placeholder.map(InspectorValue.string) ?? .null
            properties["isSecureTextEntry"] = .bool(textField.isSecureTextEntry)
        case let imageView as UIImageView:
            properties["imageSize"] = imageView.image.map { .size($0.size) } ?? .null
        case let scrollView as UIScrollView:
            properties["contentOffset"] = .point(scrollView.contentOffset)
            properties["contentSize"] = .size(scrollView.contentSize)
        case let stack as UIStackView:
            properties["axis"] = .string(stack.axis == .vertical ? "vertical" : "horizontal")
            properties["spacing"] = .number(Double(stack.spacing))
        default:
            break
        }

        if !view.gestureRecognizers.isNilOrEmpty {
            properties["gestureRecognizers"] = .string(
                (view.gestureRecognizers ?? [])
                    .map { String(describing: type(of: $0)) }
                    .joined(separator: ", ")
            )
        }

        return CapturedNodeContent(
            type: String(describing: type(of: view)),
            identifier: identifier,
            label: label,
            frame: frameInWindow,
            alpha: Double(view.alpha),
            isHidden: view.isHidden,
            clipsToBounds: view.clipsToBounds,
            isUserInteractionEnabled: view.isUserInteractionEnabled,
            accessibilityLabel: view.accessibilityLabel,
            properties: properties
        )
    }

    public func setProperty(
        _ key: String, to value: InspectorValue, on object: AnyObject
    ) -> Bool {
        guard let view = object as? UIView else { return false }
        switch (key, value) {
        case ("alpha", .number(let number)):
            view.alpha = CGFloat(number)
        case ("isHidden", .bool(let flag)):
            view.isHidden = flag
        case ("backgroundColor", .color(let hex)), ("backgroundColor", .string(let hex)):
            guard let color = UIColor(spacezHex: hex) else { return false }
            view.backgroundColor = color
        default:
            return false
        }
        return true
    }
}

extension Optional where Wrapped: Collection {
    var isNilOrEmpty: Bool {
        self?.isEmpty ?? true
    }
}

extension String {
    package func spacezTruncated(_ limit: Int) -> String {
        count <= limit ? self : String(prefix(limit)) + "…"
    }
}

extension UIFont {
    var spacezDescription: String {
        "\(fontName) \(String(format: "%.1f", pointSize))pt"
    }
}

extension UIView.ContentMode {
    var spacezName: String {
        switch self {
        case .scaleToFill: return "scaleToFill"
        case .scaleAspectFit: return "scaleAspectFit"
        case .scaleAspectFill: return "scaleAspectFill"
        case .redraw: return "redraw"
        case .center: return "center"
        case .top: return "top"
        case .bottom: return "bottom"
        case .left: return "left"
        case .right: return "right"
        case .topLeft: return "topLeft"
        case .topRight: return "topRight"
        case .bottomLeft: return "bottomLeft"
        case .bottomRight: return "bottomRight"
        @unknown default: return "unknown"
        }
    }
}

extension UIColor {
    public var spacezHexString: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func clamp(_ component: CGFloat) -> Int {
            Int((max(0, min(1, component)) * 255).rounded())
        }
        return String(
            format: "#%02X%02X%02X%02X",
            clamp(red), clamp(green), clamp(blue), clamp(alpha)
        )
    }

    public convenience init?(spacezHex: String) {
        var hex = spacezHex.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else {
            return nil
        }
        let hasAlpha = hex.count == 8
        let divisor: CGFloat = 255
        let alpha = hasAlpha ? CGFloat(value & 0xFF) / divisor : 1
        let shift = hasAlpha ? 8 : 0
        self.init(
            red: CGFloat((value >> (16 + shift)) & 0xFF) / divisor,
            green: CGFloat((value >> (8 + shift)) & 0xFF) / divisor,
            blue: CGFloat((value >> shift) & 0xFF) / divisor,
            alpha: alpha
        )
    }
}
