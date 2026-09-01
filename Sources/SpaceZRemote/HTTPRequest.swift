import Foundation

/// Minimal HTTP/1.1 request head parser — just enough to serve the embedded
/// web client and a snapshot export. Not a general web server and must never
/// become one; anything more belongs behind the WebSocket protocol.
struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]

    /// Parses the request head. Returns nil until a full head
    /// (terminated by CRLFCRLF) is present.
    static func parse(_ data: Data) -> HTTPRequest? {
        guard let headEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let head = String(data: data[..<headEnd.lowerBound], encoding: .utf8),
              let requestLine = head.split(separator: "\r\n").first
        else { return nil }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let target = String(parts[1])

        let pathAndQuery = target.split(separator: "?", maxSplits: 1)
        let path = pathAndQuery.first.map(String.init) ?? "/"
        var query: [String: String] = [:]
        if pathAndQuery.count == 2 {
            for pair in pathAndQuery[1].split(separator: "&") {
                let keyValue = pair.split(separator: "=", maxSplits: 1)
                guard let key = keyValue.first else { continue }
                let value = keyValue.count == 2 ? String(keyValue[1]) : ""
                query[String(key)] = value.removingPercentEncoding ?? value
            }
        }
        return HTTPRequest(method: method, path: path, query: query)
    }
}

enum HTTPResponse {
    static func ok(contentType: String, body: Data) -> Data {
        var response = "HTTP/1.1 200 OK\r\n"
        response += "Content-Type: \(contentType)\r\n"
        response += "Content-Length: \(body.count)\r\n"
        response += "Cache-Control: no-store\r\n"
        response += "Connection: close\r\n\r\n"
        return Data(response.utf8) + body
    }

    static func status(_ code: Int, _ reason: String, body: String = "") -> Data {
        let content = Data(body.utf8)
        var response = "HTTP/1.1 \(code) \(reason)\r\n"
        response += "Content-Type: text/plain; charset=utf-8\r\n"
        response += "Content-Length: \(content.count)\r\n"
        response += "Connection: close\r\n\r\n"
        return Data(response.utf8) + content
    }
}
