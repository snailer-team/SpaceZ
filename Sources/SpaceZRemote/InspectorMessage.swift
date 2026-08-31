import Foundation
import SpaceZCore
import SpaceZRules

// The wire protocol between the device SDK and the browser inspector.
//
// Transport-agnostic by design: these are plain Codable values, currently
// carried over WebSocket JSON. Swapping the transport (USB, socket file)
// must never require touching inspector logic.
//
// The read side follows the partial-fetch model: `getRoot` + `getNodes(ids)` +
// pushed `invalidate` — never "stream the whole tree on every change"
// (5,000 nodes × 300 B × 10 Hz ≈ 15 MB/s; invalidation is ~tens of bytes).

// MARK: - Client → Device

public enum InspectorRequest: Sendable, Equatable {
    /// Must be the first message; carries the session token.
    case hello(token: String)
    case getRoot
    case getNodes(ids: [NodeID])
    /// Full tree in one response — initial load and manual refresh.
    case getTree
    case search(query: String)
    case highlight(id: NodeID?)
    case setProperty(id: NodeID, key: String, value: InspectorValue)
    case getIssues
}

extension InspectorRequest: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, token, ids, query, id, key, value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "hello":
            self = .hello(token: try container.decode(String.self, forKey: .token))
        case "getRoot":
            self = .getRoot
        case "getNodes":
            self = .getNodes(ids: try container.decode([NodeID].self, forKey: .ids))
        case "getTree":
            self = .getTree
        case "search":
            self = .search(query: try container.decode(String.self, forKey: .query))
        case "highlight":
            self = .highlight(id: try container.decodeIfPresent(NodeID.self, forKey: .id))
        case "setProperty":
            self = .setProperty(
                id: try container.decode(NodeID.self, forKey: .id),
                key: try container.decode(String.self, forKey: .key),
                value: try container.decode(InspectorValue.self, forKey: .value)
            )
        case "getIssues":
            self = .getIssues
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container, debugDescription: "Unknown request type '\(type)'"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .hello(let token):
            try container.encode("hello", forKey: .type)
            try container.encode(token, forKey: .token)
        case .getRoot:
            try container.encode("getRoot", forKey: .type)
        case .getNodes(let ids):
            try container.encode("getNodes", forKey: .type)
            try container.encode(ids, forKey: .ids)
        case .getTree:
            try container.encode("getTree", forKey: .type)
        case .search(let query):
            try container.encode("search", forKey: .type)
            try container.encode(query, forKey: .query)
        case .highlight(let id):
            try container.encode("highlight", forKey: .type)
            try container.encodeIfPresent(id, forKey: .id)
        case .setProperty(let id, let key, let value):
            try container.encode("setProperty", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(key, forKey: .key)
            try container.encode(value, forKey: .value)
        case .getIssues:
            try container.encode("getIssues", forKey: .type)
        }
    }
}

// MARK: - Device → Client

public enum InspectorResponse: Sendable {
    case helloAck(appName: String, version: UInt64)
    case root(version: UInt64, rootIDs: [NodeID], nodeCount: Int)
    case nodes(version: UInt64, nodes: [InspectorNode])
    /// Whole tree: roots plus every node. Initial load / refresh only.
    case tree(version: UInt64, rootIDs: [NodeID], nodes: [InspectorNode])
    /// The listed IDs changed (added/changed/removed); cached copies are
    /// stale. `removed` may be pruned locally without a refetch.
    case invalidate(version: UInt64, invalidated: [NodeID], removed: [NodeID], rootIDs: [NodeID])
    case searchResults(version: UInt64, ids: [NodeID])
    case issues(version: UInt64, issues: [Issue])
    /// Device-initiated selection (tap-to-select on the phone).
    case select(id: NodeID)
    case ack(ok: Bool, detail: String?)
    case error(message: String)
}

extension InspectorResponse: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, appName, version, rootIds, nodeCount, nodes, invalidated, removed
        case ids, issues, id, ok, detail, message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "helloAck":
            self = .helloAck(
                appName: try container.decode(String.self, forKey: .appName),
                version: try container.decode(UInt64.self, forKey: .version)
            )
        case "root":
            self = .root(
                version: try container.decode(UInt64.self, forKey: .version),
                rootIDs: try container.decode([NodeID].self, forKey: .rootIds),
                nodeCount: try container.decode(Int.self, forKey: .nodeCount)
            )
        case "nodes":
            self = .nodes(
                version: try container.decode(UInt64.self, forKey: .version),
                nodes: try container.decode([InspectorNode].self, forKey: .nodes)
            )
        case "tree":
            self = .tree(
                version: try container.decode(UInt64.self, forKey: .version),
                rootIDs: try container.decode([NodeID].self, forKey: .rootIds),
                nodes: try container.decode([InspectorNode].self, forKey: .nodes)
            )
        case "invalidate":
            self = .invalidate(
                version: try container.decode(UInt64.self, forKey: .version),
                invalidated: try container.decode([NodeID].self, forKey: .invalidated),
                removed: try container.decode([NodeID].self, forKey: .removed),
                rootIDs: try container.decode([NodeID].self, forKey: .rootIds)
            )
        case "searchResults":
            self = .searchResults(
                version: try container.decode(UInt64.self, forKey: .version),
                ids: try container.decode([NodeID].self, forKey: .ids)
            )
        case "issues":
            self = .issues(
                version: try container.decode(UInt64.self, forKey: .version),
                issues: try container.decode([Issue].self, forKey: .issues)
            )
        case "select":
            self = .select(id: try container.decode(NodeID.self, forKey: .id))
        case "ack":
            self = .ack(
                ok: try container.decode(Bool.self, forKey: .ok),
                detail: try container.decodeIfPresent(String.self, forKey: .detail)
            )
        case "error":
            self = .error(message: try container.decode(String.self, forKey: .message))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container, debugDescription: "Unknown response type '\(type)'"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .helloAck(let appName, let version):
            try container.encode("helloAck", forKey: .type)
            try container.encode(appName, forKey: .appName)
            try container.encode(version, forKey: .version)
        case .root(let version, let rootIDs, let nodeCount):
            try container.encode("root", forKey: .type)
            try container.encode(version, forKey: .version)
            try container.encode(rootIDs, forKey: .rootIds)
            try container.encode(nodeCount, forKey: .nodeCount)
        case .nodes(let version, let nodes):
            try container.encode("nodes", forKey: .type)
            try container.encode(version, forKey: .version)
            try container.encode(nodes, forKey: .nodes)
        case .tree(let version, let rootIDs, let nodes):
            try container.encode("tree", forKey: .type)
            try container.encode(version, forKey: .version)
            try container.encode(rootIDs, forKey: .rootIds)
            try container.encode(nodes, forKey: .nodes)
        case .invalidate(let version, let invalidated, let removed, let rootIDs):
            try container.encode("invalidate", forKey: .type)
            try container.encode(version, forKey: .version)
            try container.encode(invalidated, forKey: .invalidated)
            try container.encode(removed, forKey: .removed)
            try container.encode(rootIDs, forKey: .rootIds)
        case .searchResults(let version, let ids):
            try container.encode("searchResults", forKey: .type)
            try container.encode(version, forKey: .version)
            try container.encode(ids, forKey: .ids)
        case .issues(let version, let issues):
            try container.encode("issues", forKey: .type)
            try container.encode(version, forKey: .version)
            try container.encode(issues, forKey: .issues)
        case .select(let id):
            try container.encode("select", forKey: .type)
            try container.encode(id, forKey: .id)
        case .ack(let ok, let detail):
            try container.encode("ack", forKey: .type)
            try container.encode(ok, forKey: .ok)
            try container.encodeIfPresent(detail, forKey: .detail)
        case .error(let message):
            try container.encode("error", forKey: .type)
            try container.encode(message, forKey: .message)
        }
    }
}

public enum InspectorCodec {
    public static func encode(_ response: InspectorResponse) throws -> Data {
        try JSONEncoder().encode(response)
    }

    public static func decodeRequest(_ data: Data) throws -> InspectorRequest {
        try JSONDecoder().decode(InspectorRequest.self, from: data)
    }
}
