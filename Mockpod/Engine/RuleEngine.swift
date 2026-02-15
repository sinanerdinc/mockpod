import Foundation

/// Thread-safe rule matching engine used by proxy handlers
final class RuleEngine {
    private let lock = NSLock()
    private var _activeRules: [MockRule] = []

    var activeRules: [MockRule] {
        lock.lock()
        defer { lock.unlock() }
        return _activeRules
    }

    func updateRules(_ rules: [MockRule]) {
        lock.lock()
        _activeRules = rules
        lock.unlock()
    }

    /// Find the first matching rule for a request
    func matchRule(method: String, url: String) -> MockRule? {
        let rules = activeRules
        return rules.first { rule in
            rule.isEnabled && rule.matcher.matches(requestMethod: method, requestURL: url)
        }
    }
}
