//
//  SPMCPHTTP.swift
//  Sequel Ace
//
//  HTTP request parsing and the loopback Origin allow-list used by the MCP
//  server. Kept free of app dependencies so it can be unit-tested in isolation.
//

import Foundation

enum SPMCPHTTP {

    /// `true` if `origin` points at a loopback host.
    static func isLoopbackOrigin(_ origin: String) -> Bool {
        guard var host = URLComponents(string: origin)?.host else { return false }
        if host.hasPrefix("[") && host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }
}

struct HTTPRequest {
    let method:  String
    let path:    String
    let headers: [String: String]
    let body:    Data?

    /// Returns a parsed request if `data` contains a complete HTTP/1.1 request,
    /// or `nil` if more data is needed.
    init?(data: Data) {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            return nil   // Incomplete headers.
        }

        let headerData = data[data.startIndex..<headerEnd.lowerBound]
        guard let headerStr = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerStr.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }
        method = parts[0]

        // Split path and query string.
        let fullPath = parts[1]
        path = fullPath.components(separatedBy: "?").first ?? fullPath

        var hdrs = [String: String]()
        for line in lines.dropFirst() {
            let kv = line.components(separatedBy: ": ")
            if kv.count >= 2 {
                hdrs[kv[0].lowercased()] = kv.dropFirst().joined(separator: ": ")
            }
        }
        headers = hdrs

        // Parse query string from the full path.
        if fullPath.contains("?") {
            let qs = fullPath.components(separatedBy: "?").dropFirst().joined(separator: "?")
            queryString = qs
        } else {
            queryString = nil
        }

        let bodyStart = data.index(headerEnd.upperBound, offsetBy: 0)
        let expectedLength = Int(hdrs["content-length"] ?? "0") ?? 0
        let remaining = data.distance(from: bodyStart, to: data.endIndex)

        if expectedLength > 0 {
            if remaining < expectedLength { return nil }   // Body not fully arrived.
            body = Data(data[bodyStart..<data.index(bodyStart, offsetBy: expectedLength)])
        } else {
            body = nil
        }
    }

    private let queryString: String?

    func queryParam(_ key: String) -> String? {
        guard let qs = queryString else { return nil }
        for pair in qs.components(separatedBy: "&") {
            let kv = pair.components(separatedBy: "=")
            if kv.count == 2, kv[0] == key {
                return kv[1].removingPercentEncoding
            }
        }
        return nil
    }
}
