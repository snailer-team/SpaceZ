import UIKit

/// Draggable round entry point. Tap opens the panel, long-press starts
/// tap-to-select.
@MainActor
final class FloatingButton: UIView {
    var onTap: (() -> Void)?
    var onLongPress: (() -> Void)?

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.72)
        layer.cornerRadius = 24
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 2)

        label.text = "Z"
        label.textColor = .white
        label.font = .monospacedSystemFont(ofSize: 20, weight: .bold)
        label.textAlignment = .center
        addSubview(label)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        addGestureRecognizer(
            UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        )
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan)))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unsupported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
    }

    @objc private func handleTap() {
        onTap?()
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        onLongPress?()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let superview else { return }
        let translation = gesture.translation(in: superview)
        center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
        gesture.setTranslation(.zero, in: superview)
        if gesture.state == .ended {
            // Snap inside safe bounds so the button can't be dragged offscreen.
            let bounds = superview.bounds.insetBy(dx: 28, dy: 60)
            center = CGPoint(
                x: min(max(center.x, bounds.minX), bounds.maxX),
                y: min(max(center.y, bounds.minY), bounds.maxY)
            )
        }
    }
}
