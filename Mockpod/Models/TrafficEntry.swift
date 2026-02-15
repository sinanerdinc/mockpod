import Foundation

/// Represents a captured HTTP request/response pair
struct TrafficEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let method: String
    let url: String
    let host: String
    let path: String
    let scheme: String

    // Request
    var requestHeaders: [HTTPHeader]
    var requestBody: Data?

    // Response
    var responseStatusCode: Int?
    var responseHeaders: [HTTPHeader]?
    var responseBody: Data?

    // Timing
    var duration: TimeInterval?
    var isComplete: Bool

    init(
        method: String,
        url: String,
        host: String,
        path: String,
        scheme: String = "https",
        requestHeaders: [HTTPHeader] = [],
        requestBody: Data? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.method = method
        self.url = url
        self.host = host
        self.path = path
        self.scheme = scheme
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.responseStatusCode = nil
        self.responseHeaders = nil
        self.responseBody = nil
        self.duration = nil
        self.isComplete = false
    }

    /// Generate a cURL command string for this request
    func toCurl() -> String {
        var parts = ["curl"]

        // Method
        if method != "GET" {
            parts.append("-X \(method)")
        }

        // Headers
        for header in requestHeaders {
            let value = header.value.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("-H '\(header.name): \(value)'")
        }

        // Body
        if let body = requestBody, let bodyString = String(data: body, encoding: .utf8) {
            let escaped = bodyString.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("-d '\(escaped)'")
        }

        // URL
        parts.append("'\(url)'")

        return parts.joined(separator: " \\\n  ")
    }

    /// Pretty-printed request body if JSON
    var prettyRequestBody: String? {
        guard let data = requestBody else { return nil }
        return Self.prettyPrintJSON(data) ?? String(data: data, encoding: .utf8)
    }

    /// Pretty-printed response body if JSON
    var prettyResponseBody: String? {
        guard let data = responseBody else { return nil }
        return Self.prettyPrintJSON(data) ?? String(data: data, encoding: .utf8)
    }

    var responseBodySize: String {
        guard let data = responseBody else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }

    var formattedDuration: String {
        guard let d = duration else { return "—" }
        if d < 1 {
            return String(format: "%.0f ms", d * 1000)
        }
        return String(format: "%.2f s", d)
    }

    static func == (lhs: TrafficEntry, rhs: TrafficEntry) -> Bool {
        lhs.id == rhs.id
    }

    private static func prettyPrintJSON(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8)
        else { return nil }
        return str
    }
}

struct HTTPHeader: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var value: String

    init(name: String, value: String) {
        self.id = UUID()
        self.name = name
        self.value = value
    }
}
