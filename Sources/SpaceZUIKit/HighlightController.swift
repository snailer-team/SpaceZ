import SpaceZCore
import UIKit

/// Draws the selection rectangle over the app, Flipper/Xcode style.
///
/// Implemented as its own non-interactive window above everything: it can
/// never affect the inspected hierarchy's layout, and it is excluded from
/// capture via ``SpaceZInternalWindow``.
@MainActor
public final class HighlightController {
    private final class HighlightWindow: UIWindow, SpaceZInternalWindow {
        // Fully transparent to touches — the highlight must never eat a tap.
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    }

    private var window: HighlightWindow?
    private let frameView = UIView()
    private let infoLabel = UILabel()

    public init() {}

    /// Shows a highlight box at `frame` (window coordinates) with a caption.
    public func highlight(frame: CGRect, caption: String) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }

        let window = self.window ?? makeWindow(scene: scene)
        window.isHidden = false

        frameView.frame = frame
        infoLabel.text = " \(caption) "
        infoLabel.sizeToFit()
        var labelFrame = infoLabel.frame
        labelFrame.origin.x = max(4, frame.minX)
        labelFrame.origin.y = frame.minY >= labelFrame.height + 4
            ? frame.minY - labelFrame.height - 2
            : frame.maxY + 2
        infoLabel.frame = labelFrame
    }

    public func clear() {
        window?.isHidden = true
    }

    private func makeWindow(scene: UIWindowScene) -> HighlightWindow {
        let window = HighlightWindow(windowScene: scene)
        window.windowLevel = .statusBar + 90
        window.backgroundColor = .clear
        window.isUserInteractionEnabled = false

        frameView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.18)
        frameView.layer.borderColor = UIColor.systemBlue.cgColor
        frameView.layer.borderWidth = 1.5

        infoLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        infoLabel.textColor = .white
        infoLabel.backgroundColor = UIColor.systemBlue
        infoLabel.layer.cornerRadius = 3
        infoLabel.layer.masksToBounds = true

        window.addSubview(frameView)
        window.addSubview(infoLabel)
        self.window = window
        return window
    }
}
