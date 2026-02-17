import SwiftUI

/// Filter options for rule status
enum RuleStatusFilter: String, CaseIterable {
    case all = "All"
    case active = "Active"
    case inactive = "Inactive"
}

/// Detail view for editing rules within a rule set
struct RuleSetDetailView: View {
    @Binding var ruleSet: RuleSet
    @State private var selectedRuleID: UUID?
    @State private var statusFilter: RuleStatusFilter = .all
    @State private var methodFilter: String = "ALL"
    @State private var searchText: String = ""

    /// Available HTTP methods extracted from the rule set
    private var availableMethods: [String] {
        let methods = Set(ruleSet.rules.compactMap { $0.matcher.method })
        return ["ALL"] + methods.sorted()
    }

    /// Filtered rules based on current filters
    private var filteredRules: [MockRule] {
        ruleSet.rules.filter { rule in
            // Status filter
            switch statusFilter {
            case .all: break
            case .active: if !rule.isEnabled { return false }
            case .inactive: if rule.isEnabled { return false }
            }

            // Method filter
            if methodFilter != "ALL" {
                guard let method = rule.matcher.method, method.uppercased() == methodFilter.uppercased() else {
                    return false
                }
            }

            // Search filter
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                let matchesName = rule.name.lowercased().contains(query)
                let matchesURL = rule.matcher.urlPattern.lowercased().contains(query)
                if !matchesName && !matchesURL { return false }
            }

            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    TextField("Rule Set Name", text: $ruleSet.name)
                        .font(.title2.bold())
                        .textFieldStyle(.plain)
                    HStack(spacing: 8) {
                        Text("\(ruleSet.rules.count) rules")
                        Text("•")
                        Text("\(ruleSet.enabledRuleCount) enabled")
                            .foregroundStyle(.green)
                        Text("•")
                        Text(ruleSet.createdAt.formattedDDMMYYYY)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(.bar)
            Divider()

            // Filter bar
            HStack(spacing: 12) {
                // Search field
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.body)
                    TextField("Search rules...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.body)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(maxWidth: 260)

                // Status filter
                Picker("Status", selection: $statusFilter) {
                    ForEach(RuleStatusFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                // Method filter
                Picker("Method", selection: $methodFilter) {
                    ForEach(availableMethods, id: \.self) { method in
                        Text(method).tag(method)
                    }
                }
                .frame(width: 150)

                Spacer()

                // Filter result count
                Text("\(filteredRules.count) of \(ruleSet.rules.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
            Divider()

            // Rules within the set
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // Rule list
                    List(filteredRules, selection: $selectedRuleID) { rule in
                        HStack(spacing: 8) {
                            Toggle("", isOn: Binding(
                                get: { rule.isEnabled },
                                set: { newValue in
                                    if let idx = ruleSet.rules.firstIndex(where: { $0.id == rule.id }) {
                                        ruleSet.rules[idx].isEnabled = newValue
                                    }
                                }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                            .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.name)
                                    .lineLimit(1)
                                HStack(spacing: 4) {
                                    MethodBadge(method: rule.matcher.method ?? "ALL")
                                    Text(rule.matcher.urlPattern)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            StatusBadge(code: rule.mockResponse.statusCode)
                        }
                        .padding(.vertical, 2)
                        .opacity(rule.isEnabled ? 1 : 0.5)
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                selectedRuleID = nil
                                ruleSet.rules.removeAll { $0.id == rule.id }
                            }
                        }
                        .tag(rule.id)
                    }
                    .listStyle(.inset)
                    .frame(width: geometry.size.width * 0.5)

                    Divider()

                    // Selected rule editor
                    Group {
                        if let ruleID = selectedRuleID,
                           let rule = ruleSet.rules.first(where: { $0.id == ruleID }) {
                            RuleEditorView(rule: Binding(
                                get: { ruleSet.rules.first(where: { $0.id == ruleID }) ?? rule },
                                set: { newValue in
                                    if let idx = ruleSet.rules.firstIndex(where: { $0.id == ruleID }) {
                                        ruleSet.rules[idx] = newValue
                                    }
                                }
                            ))
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 30))
                                    .foregroundStyle(.quaternary)
                                Text("Select a rule to edit its response")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(width: geometry.size.width * 0.5)
                }
            }
        }
    }
}
