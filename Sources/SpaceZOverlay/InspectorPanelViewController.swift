import SpaceZCore
import UIKit

/// Sheet container: [Tree | Issues] segmented switcher.
@MainActor
final class InspectorPanelViewController: UIViewController {
    var onDismiss: (() -> Void)?

    private let context: OverlayContext
    private let segmented = UISegmentedControl(items: ["Tree", "Issues"])
    private lazy var treeController = TreeViewController(context: context)
    private lazy var issuesController = IssuesViewController(context: context)
    private var currentChild: UIViewController?

    init(context: OverlayContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unsupported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.titleView = segmented
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
        segmented.selectedSegmentIndex = 0
        segmented.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        showChild(treeController)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            onDismiss?()
        }
    }

    func reveal(_ nodeID: NodeID) {
        segmented.selectedSegmentIndex = 0
        showChild(treeController)
        treeController.reveal(nodeID)
    }

    @objc private func segmentChanged() {
        showChild(segmented.selectedSegmentIndex == 0 ? treeController : issuesController)
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func showChild(_ child: UIViewController) {
        guard currentChild !== child else { return }
        currentChild?.willMove(toParent: nil)
        currentChild?.view.removeFromSuperview()
        currentChild?.removeFromParent()

        addChild(child)
        child.view.frame = view.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(child.view)
        child.didMove(toParent: self)
        currentChild = child
    }
}
