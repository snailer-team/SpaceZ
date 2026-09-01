import UIKit

/// Structural smells for the rule engine and a live-update playground:
/// - a 30-level wrapper chain (`deep-hierarchy`)
/// - 80 direct children in one container (`massive-siblings`)
/// - a hidden subtree with dozens of live views (`hidden-subtree`)
/// - a timer that mutates a view every second, to watch incremental
///   invalidation flow into the web inspector.
final class StressViewController: UIViewController {
    private let pulseView = UIView()
    private var timer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Stress"
        view.backgroundColor = .systemBackground

        // Deep wrapper chain.
        var current = view!
        for depth in 0..<30 {
            let wrapper = UIView()
            wrapper.accessibilityIdentifier = "Wrapper\(depth)"
            wrapper.frame = current.bounds.insetBy(dx: 1, dy: 1)
            wrapper.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            current.addSubview(wrapper)
            current = wrapper
        }

        // Sibling flood.
        let crowd = UIStackView()
        crowd.accessibilityIdentifier = "SiblingFlood"
        crowd.axis = .vertical
        for index in 0..<80 {
            let row = UILabel()
            row.text = "row \(index)"
            row.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            crowd.addArrangedSubview(row)
        }
        crowd.frame = CGRect(x: 16, y: 120, width: 120, height: 400)
        crowd.clipsToBounds = true
        current.addSubview(crowd)

        // Hidden but alive.
        let ghost = UIView()
        ghost.accessibilityIdentifier = "GhostContainer"
        ghost.isHidden = true
        for _ in 0..<25 {
            ghost.addSubview(UIView())
        }
        current.addSubview(ghost)

        // Live mutation source.
        pulseView.accessibilityIdentifier = "PulseView"
        pulseView.backgroundColor = .systemTeal
        pulseView.frame = CGRect(x: 180, y: 160, width: 120, height: 120)
        pulseView.layer.cornerRadius = 12
        current.addSubview(pulseView)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pulseView.alpha = self.pulseView.alpha > 0.5 ? 0.3 : 1.0
                self.pulseView.frame.origin.y = self.pulseView.frame.origin.y > 200 ? 160 : 240
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timer?.invalidate()
        timer = nil
    }
}
