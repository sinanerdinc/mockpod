import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Manages all rules and rule sets with persistence
@MainActor
final class RuleStore: ObservableObject {
    @Published var rules: [MockRule] = []
    @Published var ruleSets: [RuleSet] = []
    @Published var selectedRuleID: UUID?
    @Published var selectedRuleSetID: UUID?

    private let storageDir: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var selectedRule: MockRule? {
        guard let id = selectedRuleID else { return nil }
        return rules.first { $0.id == id }
    }

    var selectedRuleSet: RuleSet? {
        guard let id = selectedRuleSetID else { return nil }
        return ruleSets.first { $0.id == id }
    }

    /// All currently active rules (standalone + from active rule sets)
    var allActiveRules: [MockRule] {
        let standaloneRules = rules.filter(\.isEnabled)
        let setRules = ruleSets.filter(\.isActive).flatMap(\.enabledRules)
        return standaloneRules + setRules
    }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageDir = appSupport.appendingPathComponent("Mockpod/Data", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        loadFromDisk()
    }

    // MARK: - Rule CRUD

    func addRule(_ rule: MockRule) {
        rules.append(rule)
        saveToDisk()
    }

    func updateRule(_ rule: MockRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            var updated = rule
            updated.updatedAt = Date()
            rules[index] = updated
            saveToDisk()
        }
    }

    func deleteRule(id: UUID) {
        if selectedRuleID == id { selectedRuleID = nil }
        rules.removeAll { $0.id == id }
        saveToDisk()
    }

    func toggleRule(id: UUID) {
        if let index = rules.firstIndex(where: { $0.id == id }) {
            rules[index].isEnabled.toggle()
            saveToDisk()
        }
    }

    // MARK: - Rule Set CRUD

    func addRuleSet(_ ruleSet: RuleSet) {
        var rs = ruleSet
        rs.name = uniqueRuleSetName(from: rs.name)
        ruleSets.append(rs)
        saveToDisk()
    }

    func updateRuleSet(_ ruleSet: RuleSet) {
        if let index = ruleSets.firstIndex(where: { $0.id == ruleSet.id }) {
            ruleSets[index] = ruleSet
            saveToDisk()
        }
    }

    func deleteRuleSet(id: UUID) {
        if selectedRuleSetID == id { selectedRuleSetID = nil }
        ruleSets.removeAll { $0.id == id }
        saveToDisk()
    }

    func toggleRuleSet(id: UUID) {
        if let index = ruleSets.firstIndex(where: { $0.id == id }) {
            ruleSets[index].isActive.toggle()
            saveToDisk()
        }
    }

    // MARK: - Create Rule Set from Recording

    func createRuleSetFromRecording(name: String, entries: [TrafficEntry]) {
        let uniqueName = uniqueRuleSetName(from: name)
        // Deduplicate by (method + url). Keep the latest captured entry for each key.
        var latestEntryByKey: [String: TrafficEntry] = [:]
        var keyOrder: [String] = []

        for entry in entries {
            let dedupeKey = "\(entry.method.uppercased()) \(entry.url)"
            if latestEntryByKey[dedupeKey] == nil {
                keyOrder.append(dedupeKey)
            }
            latestEntryByKey[dedupeKey] = entry
        }

        let dedupedEntries = keyOrder.compactMap { latestEntryByKey[$0] }
        let rules = dedupedEntries.map { MockRule.from(entry: $0) }
        let ruleSet = RuleSet(name: uniqueName, rules: rules, description: "Recorded on \(Date().formattedDDMMYYYY)")
        addRuleSet(ruleSet)
    }

    /// Returns a unique name for a rule set; appends " - 2", " - 3", etc. if the base name already exists
    func uniqueRuleSetName(from baseName: String) -> String {
        let trimmed = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingNames = Set(ruleSets.map { $0.name })
        let (base, _) = parseRuleSetNameSuffix(trimmed)
        if !existingNames.contains(trimmed) {
            return trimmed
        }
        var counter = 2
        while existingNames.contains("\(base) - \(counter)") {
            counter += 1
        }
        return "\(base) - \(counter)"
    }

    /// Extracts base name and optional suffix number from "Name - 2" format
    private func parseRuleSetNameSuffix(_ name: String) -> (base: String, number: Int?) {
        let pattern = #"^(.+)\s+-\s+(\d+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let baseRange = Range(match.range(at: 1), in: name),
              let numRange = Range(match.range(at: 2), in: name),
              let num = Int(name[numRange]) else {
            return (name, nil)
        }
        return (String(name[baseRange]).trimmingCharacters(in: .whitespaces), num)
    }

    // MARK: - Create Rule from Traffic Entry

    func createRuleFromEntry(_ entry: TrafficEntry) {
        let rule = MockRule.from(entry: entry)
        addRule(rule)
    }

    // MARK: - Export / Import

    func exportRuleSet(_ ruleSet: RuleSet) throws -> Data {
        try encoder.encode(ruleSet)
    }

    func importRuleSet(from data: Data) throws {
        var ruleSet = try decoder.decode(RuleSet.self, from: data)
        ruleSet.id = UUID()
        ruleSet.isActive = false
        addRuleSet(ruleSet)
    }

    func importRuleSetFromFile(url: URL) throws {
        let needsSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if needsSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let data = try Data(contentsOf: url)
        try importRuleSet(from: data)
    }

    // MARK: - Persistence

    private func saveToDisk() {
        do {
            let rulesData = try encoder.encode(rules)
            try rulesData.write(to: storageDir.appendingPathComponent("rules.json"))

            let setsData = try encoder.encode(ruleSets)
            try setsData.write(to: storageDir.appendingPathComponent("rulesets.json"))
        } catch {
            print("Failed to save rules: \(error)")
        }
    }

    private func loadFromDisk() {
        let rulesFile = storageDir.appendingPathComponent("rules.json")
        let setsFile = storageDir.appendingPathComponent("rulesets.json")

        if let data = try? Data(contentsOf: rulesFile) {
            rules = (try? decoder.decode([MockRule].self, from: data)) ?? []
        }

        if let data = try? Data(contentsOf: setsFile) {
            ruleSets = (try? decoder.decode([RuleSet].self, from: data)) ?? []
        }
    }
}

// MARK: - Mockpod Document Type

extension UTType {
    static let mockpodRuleSet = UTType(exportedAs: "com.mockpod.ruleset")
}
