import UIKit

/// The lecture's canonical bug, reproduced on purpose:
/// "결제 버튼이 화면에는 보이는데 눌리지 않습니다."
///
/// A LoadingOverlay with alpha 0.01 covers the whole screen and swallows every
/// touch. A screenshot looks fine; the SpaceZ issues tab flags it as
/// `invisible-interaction`, and the tree shows the overlay above PayButton.
final class CheckoutViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Checkout"
        view.backgroundColor = .systemBackground

        let priceLabel = UILabel()
        priceLabel.text = "₩1,299,000"
        priceLabel.font = .systemFont(ofSize: 34, weight: .bold)
        priceLabel.accessibilityIdentifier = "PriceLabel"

        // Bug 2: clipped text — container too small + clipsToBounds.
        let badgeContainer = UIView()
        badgeContainer.backgroundColor = .systemYellow.withAlphaComponent(0.3)
        badgeContainer.clipsToBounds = true
        badgeContainer.accessibilityIdentifier = "BadgeContainer"
        let badgeLabel = UILabel()
        badgeLabel.text = "Limited launch discount — today only!"
        badgeLabel.font = .systemFont(ofSize: 14)
        badgeContainer.addSubview(badgeLabel)
        badgeLabel.frame = CGRect(x: 8, y: 4, width: 280, height: 20)

        let payButton = UIButton(configuration: .filled())
        payButton.configuration?.title = "Pay Now"
        payButton.accessibilityIdentifier = "PayButton"
        payButton.addAction(
            UIAction { [weak self] _ in
                let alert = UIAlertController(
                    title: "Paid!", message: "The button worked.", preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self?.present(alert, animated: true)
            },
            for: .touchUpInside
        )

        // Bug 3: icon-only button with no accessibility label.
        let helpButton = UIButton(type: .system)
        helpButton.setImage(UIImage(systemName: "questionmark.circle"), for: .normal)

        let stack = UIStackView(arrangedSubviews: [priceLabel, badgeContainer, payButton, helpButton])
        stack.axis = .vertical
        stack.spacing = 20
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            badgeContainer.heightAnchor.constraint(equalToConstant: 24),
        ])

        // Bug 1: the invisible touch-eating overlay. It was "temporarily"
        // faded to 0.01 instead of removed — the classic.
        let loadingOverlay = UIView()
        loadingOverlay.accessibilityIdentifier = "LoadingOverlay"
        loadingOverlay.backgroundColor = .black
        loadingOverlay.alpha = 0.01
        loadingOverlay.isUserInteractionEnabled = true
        loadingOverlay.frame = view.bounds
        loadingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(loadingOverlay)
    }
}
