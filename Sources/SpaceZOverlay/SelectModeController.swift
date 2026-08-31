import SpaceZCore
import SpaceZUIKit
import UIKit

/// Full-screen transparent layer that captures one tap and resolves it to the
/// deepest inspectable view at that point (device → tool selection).
@MainActor
final class SelectModeView: UIView {}

@MainActor
final class SelectModeController {
    var onPicked: ((NodeID) -> Void)?
    var onCancelled: (() -> Void)?

    private weak var window: UIWindow?
    private let registry: NodeIDRegistry
    private let highlight: HighlightController
    private var selectView: SelectModeView?

    init(window: UIWindow, registry: NodeIDRegistry, highlight: HighlightController) {
        self.window = window
        self.registry = registry
        self.highlight = highlight
    }

    func begin() {
        guard let window, let root = window.rootViewController?.view else { return }
        let view = SelectModeView(frame: root.bounds)
        view.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.06)
        view.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(handleTap))
        )

        let hint = UILabel()
        hint.text = "Tap a view to inspect · tap here to cancel"
        hint.font = .systemFont(ofSize: 13, weight: .semibold)
        hint.textColor = .white
        hint.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        hint.textAlignment = .center
        hint.layer.cornerRadius = 8
        hint.layer.masksToBounds = true
        hint.frame = CGRect(x: 40, y: root.safeAreaInsets.top + 8,
                            width: root.bounds.width - 80, height: 32)
        hint.autoresizingMask = [.flexibleWidth]
        hint.tag = 0xCA7CE1
        view.addSubview(hint)

        root.addSubview(view)
        selectView = view
    }

    func end() {
        selectView?.removeFromSuperview()
        selectView = nil
        highlight.clear()
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let selectView, let window else { return }
        let point = gesture.location(in: selectView)

        if let hint = selectView.viewWithTag(0xCA7CE1), hint.frame.contains(point) {
            onCancelled?()
            return
        }

        guard let scene = window.windowScene else {
            onCancelled?()
            return
        }
        // Hit-test the app's windows front-to-back, skipping our own.
        let appWindows = scene.windows
            .filter { !($0 is SpaceZInternalWindow) && !$0.isHidden }
            .sorted { $0.windowLevel > $1.windowLevel }

        for appWindow in appWindows {
            let converted = appWindow.convert(point, from: window)
            if let hit = deepestHit(in: appWindow, at: converted) {
                let nodeID = registry.id(for: hit)
                let frame = hit.convert(hit.bounds, to: appWindow)
                highlight.highlight(
                    frame: frame,
                    caption: "\(String(describing: type(of: hit))) \(nodeID)"
                )
                onPicked?(nodeID)
                return
            }
        }
        onCancelled?()
    }

    /// `hitTest` skips non-interactive views, which are exactly the ones we
    /// often need to inspect — so walk the tree manually, deepest-last-subview
    /// first (top of z-order), ignoring only hidden/zero-alpha branches.
    private func deepestHit(in view: UIView, at point: CGPoint) -> UIView? {
        guard !view.isHidden, view.alpha > 0.01, view.point(inside: point, with: nil)
        else { return nil }
        for subview in view.subviews.reversed() {
            let converted = subview.convert(point, from: view)
            if let hit = deepestHit(in: subview, at: converted) {
                return hit
            }
        }
        return view
    }
}
