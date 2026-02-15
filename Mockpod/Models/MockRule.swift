import Foundation

/// A single mock rule that matches requests and returns custom responses
struct MockRule: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var matcher: RequestMatcher
    var mockResponse: MockResponse
    var createdAt: Date
    var updatedAt: Date?

    /// Display date: updatedAt if available, otherwise createdAt
    var displayDate: Date {
        updatedAt ?? createdAt
    }

    /// Formatted display date as "dd/MM/yyyy, HH:mm"
    var formattedDisplayDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy, HH:mm"
        return formatter.string(from: displayDate)
    }

    init(name: String, matcher: RequestMatcher, mockResponse: MockResponse) {
        self.id = UUID()
        self.name = name
        self.isEnabled = true
        self.matcher = matcher
        self.mockResponse = mockResponse
        self.createdAt = Date()
        self.updatedAt = nil
    }

    /// Create a rule from a captured traffic entry
    static func from(entry: TrafficEntry) -> MockRule {
        let matcher = RequestMatcher(
            urlPattern: entry.url,
            method: entry.method,
            matchType: .exact
        )

        let response = MockResponse(
            statusCode: entry.responseStatusCode ?? 200,
            headers: entry.responseHeaders ?? [],
            body: entry.responseBody.flatMap { String(data: $0, encoding: .utf8) } ?? "{}",
            delay: nil
        )

        let pathComponent = URL(string: entry.url)?.lastPathComponent ?? entry.path
        return MockRule(
            name: "\(entry.method) \(pathComponent)",
            matcher: matcher,
            mockResponse: response
        )
    }
}

/// Defines how to match incoming requests
struct RequestMatcher: Codable, Equatable {
    var urlPattern: String
    var method: String?
    var matchType: MatchType

    enum MatchType: String, Codable, CaseIterable {
        case exact = "Exact"
        case contains = "Contains"
        case regex = "Regex"
    }

    func matches(requestMethod: String, requestURL: String) -> Bool {
        // Check method if specified
        if let m = method, m.uppercased() != requestMethod.uppercased() {
            return false
        }

        // Check URL pattern
        switch matchType {
        case .exact:
            return requestURL == urlPattern
        case .contains:
            return requestURL.contains(urlPattern)
        case .regex:
            return (try? NSRegularExpression(pattern: urlPattern))
                .map { regex in
                    let range = NSRange(requestURL.startIndex..., in: requestURL)
                    return regex.firstMatch(in: requestURL, range: range) != nil
                } ?? false
        }
    }
}

/// The mock response to return when a rule matches
struct MockResponse: Codable, Equatable {
    var statusCode: Int
    var headers: [HTTPHeader]
    var body: String
    var delay: TimeInterval?

    /// Parse body as pretty JSON, or return as-is
    var prettyBody: String {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8)
        else { return body }
        return str
    }
}
