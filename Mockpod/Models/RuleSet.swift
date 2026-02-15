import Foundation

/// A named collection of mock rules that can be activated together
struct RuleSet: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var rules: [MockRule]
    var isActive: Bool
    var createdAt: Date
    var description: String

    init(name: String, rules: [MockRule] = [], description: String = "") {
        self.id = UUID()
        self.name = name
        self.rules = rules
        self.isActive = false
        self.createdAt = Date()
        self.description = description
    }

    /// Number of enabled rules in this set
    var enabledRuleCount: Int {
        rules.filter(\.isEnabled).count
    }

    /// Get all enabled rules from this set
    var enabledRules: [MockRule] {
        rules.filter(\.isEnabled)
    }
}
