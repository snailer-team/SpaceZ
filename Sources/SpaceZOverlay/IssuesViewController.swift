import SpaceZCore
import SpaceZRules
import UIKit

/// Live diagnostics list. Rule evaluation runs off-main on the snapshot; the
/// table only renders results.
@MainActor
final class IssuesViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let context: OverlayContext
    private let tableView = UITableView()
    private var issues: [Issue] = []
    private var snapshot: Snapshot?
    private var subscription: Task<Void, Never>?

    init(context: OverlayContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unsupported") }

    deinit {
        subscription?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "issue")
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(tableView)

        let ruleEngine = context.ruleEngine
        subscription = Task { [weak self] in
            guard let pipeline = self?.context.pipeline else { return }
            for await snapshot in await pipeline.subscribe() {
                // Rule evaluation is O(nodes × rules); keep it off the main
                // actor so a 5,000-node pass can't stutter the app.
                let evaluated = await Task.detached(priority: .utility) {
                    ruleEngine.evaluate(snapshot)
                }.value
                guard let self else { return }
                self.snapshot = snapshot
                self.issues = evaluated
                self.tableView.reloadData()
            }
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(issues.count, 1)
    }

    func tableView(
        _ tableView: UITableView, cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "issue", for: indexPath)
        var configuration = cell.defaultContentConfiguration()

        if issues.isEmpty {
            configuration.text = "No issues found"
            configuration.textProperties.color = .secondaryLabel
            cell.contentConfiguration = configuration
            cell.selectionStyle = .none
            return cell
        }

        let issue = issues[indexPath.row]
        let badge: String
        switch issue.severity {
        case .error: badge = "🔴"
        case .warning: badge = "🟠"
        case .info: badge = "🔵"
        }
        configuration.text = "\(badge) \(issue.ruleID)"
        configuration.textProperties.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        configuration.secondaryText = issue.message
        configuration.secondaryTextProperties.font = .systemFont(ofSize: 12)
        configuration.secondaryTextProperties.numberOfLines = 0
        cell.contentConfiguration = configuration
        cell.selectionStyle = .default
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        guard !issues.isEmpty, let snapshot else { return }
        let issue = issues[indexPath.row]
        guard let node = snapshot.nodes[issue.nodeID] else { return }
        context.highlight.highlight(
            frame: node.frame,
            caption: "\(node.type) \(node.id)"
        )
        context.onSelect(node.id)
    }
}
