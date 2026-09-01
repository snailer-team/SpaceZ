import Foundation
import Network
import SpaceZCore

/// The device-side endpoint of the remote inspector.
///
/// Two listeners on adjacent ports, both plain Network.framework (zero
/// third-party dependencies):
/// - `httpPort`: serves the embedded single-file web client and
///   `/snapshot.json` (redacted export).
/// - `httpPort + 1`: WebSocket carrying ``InspectorRequest`` /
///   ``InspectorResponse`` JSON.
///
/// Security posture (this is a *debug* tool, and it opens a LAN port):
/// - The umbrella target's `SpaceZDebugger.start()` is a no-op outside DEBUG
///   builds, so in a release binary this server is never started.
/// - Every HTTP route and the first WebSocket message require the per-launch
///   random session token. Without the token URL printed to the console, a
///   peer on the network gets 403 and the socket closes.
/// - Snapshots arrive here already redacted by ``RemoteBridge``.
public actor DebugServer {
    public nonisolated let httpPort: UInt16
    public nonisolated let token: String

    private let bridge: RemoteBridge
    private var httpListener: NWListener?
    private var wsListener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var authenticated: Set<ObjectIdentifier> = []

    public init(httpPort: UInt16, bridge: RemoteBridge) {
        self.httpPort = httpPort
        self.bridge = bridge
        // 16 hex chars ≈ 64 bits — unguessable over a LAN session lifetime.
        self.token = String(format: "%08x%08x", UInt32.random(in: .min ... .max),
                            UInt32.random(in: .min ... .max))
    }

    public var webSocketPort: UInt16 { httpPort + 1 }

    public func start() async throws {
        guard httpListener == nil else { return }

        await bridge.setBroadcast { [weak self] response in
            Task { await self?.broadcastToClients(response) }
        }

        let http = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: httpPort)!)
        http.newConnectionHandler = { [weak self] connection in
            Task { await self?.acceptHTTP(connection) }
        }
        // Bonjour lets tools discover the app without typing an IP.
        http.service = NWListener.Service(name: nil, type: "_spacez._tcp")

        let wsParams = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        wsParams.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        let ws = try NWListener(using: wsParams, on: NWEndpoint.Port(rawValue: webSocketPort)!)
        ws.newConnectionHandler = { [weak self] connection in
            Task { await self?.acceptWebSocket(connection) }
        }

        // NWListener reports bind failures (EADDRINUSE etc.) asynchronously
        // through its state, not from start(). Without waiting for .ready,
        // start() would "succeed" against an occupied port and the caller
        // would print an inspector URL that can never work.
        do {
            try await startAndAwaitReady(http)
            httpListener = http
            try await startAndAwaitReady(ws)
            wsListener = ws
        } catch {
            http.cancel()
            ws.cancel()
            httpListener = nil
            wsListener = nil
            throw error
        }
    }

    private func startAndAwaitReady(_ listener: NWListener) async throws {
        // The state handler keeps firing after readiness; the guard makes the
        // continuation one-shot.
        let once = OneShot()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.claim() { continuation.resume() }
                case .failed(let error):
                    if once.claim() { continuation.resume(throwing: error) }
                case .cancelled:
                    if once.claim() { continuation.resume(throwing: CancellationError()) }
                default:
                    break
                }
            }
            listener.start(queue: .global(qos: .utility))
        }
    }

    public func stop() {
        httpListener?.cancel()
        wsListener?.cancel()
        httpListener = nil
        wsListener = nil
        for connection in connections.values {
            connection.cancel()
        }
        connections.removeAll()
        authenticated.removeAll()
    }

    // MARK: - HTTP

    private func acceptHTTP(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        receiveHTTPHead(connection, buffered: Data())
    }

    private nonisolated func receiveHTTPHead(_ connection: NWConnection, buffered: Data) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 16 * 1024
        ) { [weak self] data, _, isComplete, error in
            guard let self, error == nil, let data, !data.isEmpty else {
                connection.cancel()
                return
            }
            let combined = buffered + data
            if let request = HTTPRequest.parse(combined) {
                Task { await self.respondHTTP(request, on: connection) }
            } else if isComplete || combined.count > 64 * 1024 {
                connection.cancel()
            } else {
                self.receiveHTTPHead(connection, buffered: combined)
            }
        }
    }

    private func respondHTTP(_ request: HTTPRequest, on connection: NWConnection) async {
        let response: Data
        switch (request.method, request.path) {
        case ("GET", "/"), ("GET", "/index.html"):
            if request.query["token"] != token {
                response = HTTPResponse.status(
                    403, "Forbidden",
                    body: "SpaceZ: open the exact URL printed in the app's console "
                        + "(it includes the session token)."
                )
            } else if let page = Self.webClientHTML(wsPort: webSocketPort, token: token) {
                response = HTTPResponse.ok(contentType: "text/html; charset=utf-8", body: page)
            } else {
                response = HTTPResponse.status(500, "Internal Server Error",
                                               body: "inspector.html missing from bundle")
            }
        case ("GET", "/snapshot.json"):
            if request.query["token"] != token {
                response = HTTPResponse.status(403, "Forbidden")
            } else {
                let json = (try? await bridge.currentSnapshotJSON()) ?? Data("{}".utf8)
                response = HTTPResponse.ok(contentType: "application/json", body: json)
            }
        default:
            response = HTTPResponse.status(404, "Not Found")
        }
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func webClientHTML(wsPort: UInt16, token: String) -> Data? {
        guard let url = Bundle.module.url(forResource: "inspector", withExtension: "html"),
              var html = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        html = html.replacingOccurrences(of: "__SPACEZ_WS_PORT__", with: String(wsPort))
        html = html.replacingOccurrences(of: "__SPACEZ_TOKEN__", with: token)
        return Data(html.utf8)
    }

    // MARK: - WebSocket

    private func acceptWebSocket(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                Task { await self?.dropConnection(id) }
            } else if case .cancelled = state {
                Task { await self?.dropConnection(id) }
            }
        }
        connection.start(queue: .global(qos: .utility))
        receiveWSMessage(connection, id: id)
    }

    private nonisolated func receiveWSMessage(_ connection: NWConnection, id: ObjectIdentifier) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self, error == nil, let data else {
                connection.cancel()
                return
            }
            Task {
                await self.handleWSMessage(data, connection: connection, id: id)
                self.receiveWSMessage(connection, id: id)
            }
        }
    }

    private func handleWSMessage(
        _ data: Data, connection: NWConnection, id: ObjectIdentifier
    ) async {
        guard let request = try? InspectorCodec.decodeRequest(data) else {
            send(.error(message: "Malformed request"), over: connection)
            return
        }

        // First message must be a valid hello; everything else before
        // authentication kills the connection.
        guard authenticated.contains(id) else {
            if case .hello(let clientToken) = request, clientToken == token {
                authenticated.insert(id)
                send(await bridge.handle(request), over: connection)
            } else {
                send(.error(message: "Unauthorized"), over: connection)
                connection.cancel()
            }
            return
        }

        send(await bridge.handle(request), over: connection)
    }

    private func broadcastToClients(_ response: InspectorResponse) {
        guard !authenticated.isEmpty, let data = try? InspectorCodec.encode(response) else {
            return
        }
        for (id, connection) in connections where authenticated.contains(id) {
            sendRaw(data, over: connection)
        }
    }

    private func send(_ response: InspectorResponse, over connection: NWConnection) {
        guard let data = try? InspectorCodec.encode(response) else { return }
        sendRaw(data, over: connection)
    }

    private nonisolated func sendRaw(_ data: Data, over connection: NWConnection) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "spacez", metadata: [metadata])
        connection.send(
            content: data,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { _ in }
        )
    }

    private func dropConnection(_ id: ObjectIdentifier) {
        connections[id] = nil
        authenticated.remove(id)
    }
}

/// Lock-guarded single-claim flag, usable from any queue.
private final class OneShot: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
