import CoreGraphics
import Foundation
import SpaceZCore

/// The classic "button visible but not tappable" culprit: a nearly transparent
/// view that still consumes touches. A screenshot can't show it; the hierarchy
/// can.
public struct InvisibleInteractionRule: UIRule {
    public let id = "invisible-interaction"
    /// Below this alpha a view is effectively invisible to users.
    public var alphaThreshold: Double
    /// Ignore tiny views — a 10×10 invisible hotspot is usually intentional.
    public var minimumArea: Double
    /// System chrome that legitimately sits at alpha 0 with interaction on
    /// (e.g. the blur background of UIKit bars). Flagging those is pure noise.
    public var exemptTypes: Set<String>

    public init(
        alphaThreshold: Double = 0.05,
        minimumArea: Double = 44 * 44,
        exemptTypes: Set<String> = ["UIVisualEffectView", "_UIBarBackground"]
    ) {
        self.alphaThreshold = alphaThreshold
        self.minimumArea = minimumArea
        self.exemptTypes = exemptTypes
    }

    public func inspect(node: InspectorNode, context: InspectionContext) -> [Issue] {
        guard
            node.isUserInteractionEnabled,
            !node.isHidden,
            node.alpha <= alphaThreshold,
            node.frame.width * node.frame.height >= minimumArea,
            !exemptTypes.contains(node.type)
        else { return [] }
        return [
            Issue(
                ruleID: id,
                nodeID: node.id,
                severity: .error,
                message: "\(node.type) is nearly invisible (alpha=\(node.alpha)) "
                    + "but still receives touches over \(Int(node.frame.width))×"
                    + "\(Int(node.frame.height))pt.",
                suggestion: "Set isUserInteractionEnabled = false while invisible, "
                    + "or remove the view instead of fading it out."
            )
        ]
    }
}

/// Interactive element without an accessibility label — invisible to VoiceOver.
public struct MissingAccessibilityLabelRule: UIRule {
    public let id = "missing-accessibility-label"

    /// Types that are interactive by design.
    public var interactiveTypes: Set<String>

    public init(interactiveTypes: Set<String> = ["UIButton", "UISwitch", "UISegmentedControl"]) {
        self.interactiveTypes = interactiveTypes
    }

    public func inspect(node: InspectorNode, context: InspectionContext) -> [Issue] {
        let isInteractiveType = interactiveTypes.contains { node.type.hasPrefix($0) }
        guard
            isInteractiveType,
            !node.isHidden,
            node.accessibilityLabel == nil,
            // A button whose title is set gets a derived label from UIKit;
            // flag only when there's no textual content at all.
            node.properties["title"] == nil || node.properties["title"] == .null
        else { return [] }
        return [
            Issue(
                ruleID: id,
                nodeID: node.id,
                severity: .warning,
                message: "\(node.type) is interactive but has no accessibility label.",
                suggestion: "Set accessibilityLabel so assistive technologies can name it."
            )
        ]
    }
}

/// Deep nesting slows layout and usually indicates wrapper-view creep.
public struct DeepHierarchyRule: UIRule {
    public let id = "deep-hierarchy"
    public var maxDepth: Int

    public init(maxDepth: Int = 25) {
        self.maxDepth = maxDepth
    }

    public func inspect(node: InspectorNode, context: InspectionContext) -> [Issue] {
        // Report once, at the node that crosses the threshold, not for every
        // descendant below it — one problem, one issue.
        guard context.depths[node.id] == maxDepth else { return [] }
        return [
            Issue(
                ruleID: id,
                nodeID: node.id,
                severity: .warning,
                message: "Hierarchy reaches depth \(maxDepth) at \(node.type).",
                suggestion: "Flatten wrapper views; each level adds layout and rendering cost."
            )
        ]
    }
}

/// Hundreds of siblings usually means cells are being added, not reused.
public struct MassiveSiblingsRule: UIRule {
    public let id = "massive-siblings"
    public var maxChildren: Int

    public init(maxChildren: Int = 50) {
        self.maxChildren = maxChildren
    }

    public func inspect(node: InspectorNode, context: InspectionContext) -> [Issue] {
        guard node.children.count > maxChildren else { return [] }
        return [
            Issue(
                ruleID: id,
                nodeID: node.id,
                severity: .warning,
                message: "\(node.type) has \(node.children.count) direct children.",
                suggestion: "If these are list items, check that cell reuse is working."
            )
        ]
    }
}

/// Child extends outside a clipping parent — content is silently cut off.
public struct ClippedChildRule: UIRule {
    public let id = "clipped-child"
    /// Overhang below this many points is ignored (rounding, shadows).
    public var tolerance: Double

    public init(tolerance: Double = 2) {
        self.tolerance = tolerance
    }

    public func inspect(node: InspectorNode, context: InspectionContext) -> [Issue] {
        guard
            let parent = context.parent(of: node.id),
            parent.clipsToBounds,
            !node.isHidden, !parent.isHidden,
            !node.frame.isEmpty, !parent.frame.isEmpty
        else { return [] }
        // Scroll views clip by design; their children live outside the bounds.
        guard !parent.type.contains("ScrollView"),
              !parent.type.contains("TableView"),
              !parent.type.contains("CollectionView")
        else { return [] }

        let inset = parent.frame.insetBy(dx: -tolerance, dy: -tolerance)
        guard !inset.contains(node.frame) else { return [] }
        return [
            Issue(
                ruleID: id,
                nodeID: node.id,
                severity: .warning,
                message: "\(node.type) extends outside its clipping parent \(parent.type); "
                    + "part of it is not rendered.",
                suggestion: "Check constraints/intrinsic size, or disable clipsToBounds on the parent."
            )
        ]
    }
}

/// A hidden view still holding a big live subtree wastes memory and often
/// signals "we hide instead of removing".
public struct HiddenSubtreeRule: UIRule {
    public let id = "hidden-subtree"
    public var minimumDescendants: Int

    public init(minimumDescendants: Int = 20) {
        self.minimumDescendants = minimumDescendants
    }

    public func inspect(node: InspectorNode, context: InspectionContext) -> [Issue] {
        guard node.isHidden else { return [] }
        // Only flag the topmost hidden node of a hidden region.
        if let parent = context.parent(of: node.id), parent.isHidden { return [] }

        var count = 0
        var stack = node.children
        while let id = stack.popLast() {
            count += 1
            if count >= minimumDescendants { break }
            if let child = context.snapshot.nodes[id] {
                stack.append(contentsOf: child.children)
            }
        }
        guard count >= minimumDescendants else { return [] }
        return [
            Issue(
                ruleID: id,
                nodeID: node.id,
                severity: .info,
                message: "\(node.type) is hidden but keeps \(minimumDescendants)+ live descendants.",
                suggestion: "Remove the subtree instead of hiding it if it stays hidden for long."
            )
        ]
    }
}
