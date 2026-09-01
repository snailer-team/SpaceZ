import SpaceZCore
import SpaceZRules
import UIKit

/// Property inspector for one node: core attributes, captured properties, and
/// any rule issues attached to it. Shows unredacted values — this screen never
/// leaves the device.
@MainActor
final class NodeDetailViewController: UIViewController, UITableViewDataSource {
    private struct Entry {
        let key: String
        let value: String
    }

    private struct Section {
        let title: String
        let entries: [Entry]
    }

    private let node: InspectorNode
    private let sections: [Section]
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    init(node: InspectorNode, snapshot: Snapshot, context: OverlayContext) {
        self.node = node

        var attributeEntries: [Entry] = [
            Entry(key: "id", value: node.id.description),
            Entry(key: "type", value: node.type),
            Entry(key: "identifier", value: node.identifier ?? "nil"),
            Entry(key: "frame", value: InspectorValue.rect(node.frame).displayString),
            Entry(key: "alpha", value: String(format: "%.2f", node.alpha)),
            Entry(key: "hidden", value: node.isHidden ? "true" : "false"),
            Entry(key: "clipsToBounds", value: node.clipsToBounds ? "true" : "false"),
            Entry(
                key: "userInteractionEnabled",
                value: node.isUserInteractionEnabled ? "true" : "false"
            ),
            Entry(key: "accessibilityLabel", value: node.accessibilityLabel ?? "nil"),
            Entry(key: "children", value: String(node.children.count)),
        ]
        if let label = node.label {
            attributeEntries.insert(Entry(key: "label", value: label), at: 2)
        }

        let propertyEntries = node.properties.keys.sorted().map { key in
            Entry(key: key, value: node.properties[key]?.displayString ?? "nil")
        }

        // Inspect only this node — no need to evaluate the whole snapshot to
        // render one detail screen.
        let inspection = InspectionContext(snapshot: snapshot)
        let issues = context.ruleEngine.rules.flatMap {
            $0.inspect(node: node, context: inspection)
        }
        let issueEntries = issues.map { issue in
            Entry(key: "⚠ \(issue.ruleID)", value: issue.message)
        }

        var built: [Section] = [Section(title: "Attributes", entries: attributeEntries)]
        if !propertyEntries.isEmpty {
            built.append(Section(title: "Properties", entries: propertyEntries))
        }
        if !issueEntries.isEmpty {
            built.append(Section(title: "Issues", entries: issueEntries))
        }
        self.sections = built

        super.init(nibName: nil, bundle: nil)
        title = node.type
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unsupported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "entry")
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(tableView)
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].entries.count
    }

    func tableView(
        _ tableView: UITableView, cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "entry", for: indexPath)
        let entry = sections[indexPath.section].entries[indexPath.row]
        var configuration = cell.defaultContentConfiguration()
        configuration.text = entry.key
        configuration.textProperties.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        configuration.secondaryText = entry.value
        configuration.secondaryTextProperties.font = .monospacedSystemFont(
            ofSize: 12, weight: .regular
        )
        cell.contentConfiguration = configuration
        cell.selectionStyle = .none
        return cell
    }
}
