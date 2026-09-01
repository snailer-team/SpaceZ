import SpaceZCore
import UIKit

/// The on-device hierarchy browser.
///
/// Renders the *snapshot*, never live views — the table can safely reload on a
/// background-published update because it only reads immutable values. Rows
/// are the flattened visible portion of the tree (expanded nodes only), so a
/// 5,000-node hierarchy costs table rows proportional to what's open, not N.
@MainActor
final class TreeViewController: UIViewController, UITableViewDataSource, UITableViewDelegate,
    UISearchBarDelegate {
    private struct Row {
        let node: InspectorNode
        let depth: Int
        let hasChildren: Bool
        let isExpanded: Bool
    }

    private let context: OverlayContext
    private let tableView = UITableView()
    private let searchBar = UISearchBar()

    private var snapshot: Snapshot?
    private var expanded: Set<NodeID> = []
    private var rows: [Row] = []
    private var selectedID: NodeID?
    private var searchResults: [NodeID]?
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

        searchBar.placeholder = "PayButton, alpha=0, accessibilityLabel=nil…"
        searchBar.delegate = self
        searchBar.autocapitalizationType = .none
        searchBar.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 52)
        searchBar.autoresizingMask = [.flexibleWidth]

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "node")
        tableView.tableHeaderView = searchBar
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(tableView)

        subscription = Task { [weak self] in
            guard let pipeline = self?.context.pipeline else { return }
            for await snapshot in await pipeline.subscribe() {
                guard let self else { return }
                self.apply(snapshot)
            }
        }
    }

    private func apply(_ snapshot: Snapshot) {
        self.snapshot = snapshot
        if expanded.isEmpty {
            // First snapshot: open the top levels so the tree isn't a bare root.
            for rootID in snapshot.rootIDs {
                expanded.insert(rootID)
                if let root = snapshot.nodes[rootID] {
                    expanded.formUnion(root.children)
                }
            }
        }
        rebuildRows()
    }

    private func rebuildRows() {
        guard let snapshot else { return }

        if let searchResults {
            rows = searchResults.compactMap { id in
                snapshot.nodes[id].map {
                    Row(node: $0, depth: 0, hasChildren: false, isExpanded: false)
                }
            }
            tableView.reloadData()
            return
        }

        var result: [Row] = []
        // Depth-first over expanded nodes only.
        var stack: [(NodeID, Int)] = snapshot.rootIDs.reversed().map { ($0, 0) }
        while let (id, depth) = stack.popLast() {
            guard let node = snapshot.nodes[id] else { continue }
            let isExpanded = expanded.contains(id)
            result.append(Row(
                node: node,
                depth: depth,
                hasChildren: !node.children.isEmpty,
                isExpanded: isExpanded
            ))
            if isExpanded {
                for child in node.children.reversed() {
                    stack.append((child, depth + 1))
                }
            }
        }
        rows = result
        tableView.reloadData()
    }

    func reveal(_ nodeID: NodeID) {
        guard let snapshot else { return }
        searchResults = nil
        searchBar.text = nil
        // Expand every ancestor so the node's row exists.
        let parents = snapshot.parentIndex()
        var current: NodeID? = nodeID
        while let id = current {
            expanded.insert(id)
            current = parents[id]
        }
        selectedID = nodeID
        rebuildRows()
        if let index = rows.firstIndex(where: { $0.node.id == nodeID }) {
            tableView.scrollToRow(
                at: IndexPath(row: index, section: 0), at: .middle, animated: false
            )
        }
    }

    // MARK: - Table

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(
        _ tableView: UITableView, cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "node", for: indexPath)
        let row = rows[indexPath.row]
        let node = row.node

        var text = ""
        if row.hasChildren {
            text += row.isExpanded ? "▾ " : "▸ "
        } else {
            text += "  "
        }
        text += node.type
        if let identifier = node.identifier {
            text += "  [\(identifier)]"
        }
        if let label = node.label {
            text += "  \(label)"
        }

        var configuration = cell.defaultContentConfiguration()
        configuration.text = text
        configuration.textProperties.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        configuration.textProperties.color = node.isHidden || node.alpha < 0.05
            ? .tertiaryLabel
            : .label
        configuration.secondaryText = String(
            format: "%@ · (%.0f, %.0f, %.0f×%.0f)",
            node.id.description,
            node.frame.origin.x, node.frame.origin.y, node.frame.width, node.frame.height
        )
        configuration.secondaryTextProperties.font = .monospacedSystemFont(
            ofSize: 10, weight: .regular
        )
        configuration.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = configuration

        cell.indentationLevel = row.depth
        cell.indentationWidth = 12
        cell.accessoryType = .detailButton
        cell.backgroundColor = node.id == selectedID
            ? UIColor.systemBlue.withAlphaComponent(0.12)
            : .clear
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        let row = rows[indexPath.row]
        let node = row.node

        selectedID = node.id
        if row.hasChildren, searchResults == nil {
            if expanded.contains(node.id) {
                expanded.remove(node.id)
            } else {
                expanded.insert(node.id)
            }
        }
        context.highlight.highlight(
            frame: node.frame,
            caption: "\(node.type) \(node.id)"
        )
        context.onSelect(node.id)
        rebuildRows()
    }

    func tableView(
        _ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath
    ) {
        guard let snapshot else { return }
        let node = rows[indexPath.row].node
        let detail = NodeDetailViewController(node: node, snapshot: snapshot, context: context)
        navigationController?.pushViewController(detail, animated: true)
    }

    // MARK: - Search

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            searchResults = nil
        } else {
            searchResults = snapshot?.search(query) ?? []
        }
        rebuildRows()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}
