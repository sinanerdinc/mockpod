import SwiftUI

/// View for managing standalone mock rules
struct RuleListView: View {
    @EnvironmentObject var ruleStore: RuleStore
    @State private var showEditor = false
    @State private var editingRule: MockRule?
    @State private var searchText = ""
    @State private var statusFilter: Bool? = nil // nil = All, true = Active, false = Inactive
    @State private var methodFilter: String = "ALL"

    var filteredRules: [MockRule] {
        ruleStore.rules.filter { rule in
            // Status Filter
            if let status = statusFilter {
                if rule.isEnabled != status { return false }
            }

            // Method Filter
            if methodFilter != "ALL" {
                if rule.matcher.method != methodFilter { return false }
            }

            // Search Filter
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                let matchesName = rule.name.lowercased().contains(query)
                let matchesURL = rule.matcher.urlPattern.lowercased().contains(query)
                return matchesName || matchesURL
            }

            return true
        }
    }

    var body: some View {
        GeometryReader { geometry in
            HSplitView {
                ruleList
                    .frame(minWidth: 200, idealWidth: geometry.size.width * 0.35, maxWidth: .infinity)
                
                ruleDetail
                    .frame(minWidth: 300, idealWidth: geometry.size.width * 0.65, maxWidth: .infinity)
            }
        }
    }

    private var ruleList: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Rules")
                    .font(.headline)
                Spacer()
                Text("\(ruleStore.rules.count) rules, \(ruleStore.rules.filter(\.isEnabled).count) active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(.bar)
            .background(.bar)
            Divider()

            // Filter bar
            GeometryReader { geo in
                let totalWidth = geo.size.width - 16 // 8 padding on each side
                let spacing: CGFloat = 8
                let availableWidth = totalWidth - (spacing * 2)
                let searchWidth = availableWidth * 0.5
                let pickerWidth = availableWidth * 0.25

                HStack(spacing: spacing) {
                    // Search field (60%)
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.body)
                        TextField("Search rules...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.body)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(width: searchWidth)

                    // Status filter (20%)
                    Picker("Status", selection: $statusFilter) {
                        Text("All").tag(Optional<Bool>.none)
                        Text("Active").tag(Optional(true))
                        Text("Inactive").tag(Optional(false))
                    }
                    .pickerStyle(.menu)
                    .frame(width: pickerWidth)

                    // Method filter (20%)
                    Picker("Method", selection: $methodFilter) {
                        Text("All").tag("ALL")
                        ForEach(["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"], id: \.self) { method in
                            Text(method).tag(method)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: pickerWidth)
                }
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .frame(height: 50) // Fixed height for filter bar area
            .padding(8)
            .background(.bar)
            Divider()

            if ruleStore.rules.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 36))
                        .foregroundStyle(.quaternary)
                    Text("No rules yet")
                        .foregroundStyle(.secondary)
                    Text("Save a request as a rule from the Traffic view,\nor record traffic to create rule sets.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding()
            } else {
                List(filteredRules, selection: $ruleStore.selectedRuleID) { rule in
                    RuleRowView(rule: rule) {
                        ruleStore.toggleRule(id: rule.id)
                    }
                    .contextMenu {
                        Button("Edit") {
                            editingRule = rule
                            showEditor = true
                        }
                        Button("Delete", role: .destructive) {
                            ruleStore.deleteRule(id: rule.id)
                        }
                    }
                    .tag(rule.id)
                }
                .listStyle(.inset)
            }
        }
    }

    @ViewBuilder
    private var ruleDetail: some View {
        ZStack(alignment: .center) {
            if let ruleID = ruleStore.selectedRuleID,
               let rule = ruleStore.rules.first(where: { $0.id == ruleID }) {
                RuleEditorView(rule: Binding(
                    get: { ruleStore.rules.first(where: { $0.id == ruleID }) ?? rule },
                    set: { ruleStore.updateRule($0) }
                ))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "pencil.and.list.clipboard")
                        .font(.system(size: 40))
                        .foregroundStyle(.quaternary)
                    Text("Select a rule to edit")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Force HSplitView to respect this view as a stable item
        .id("RuleDetailContainer") 
    }
}

struct RuleRowView: View {
    let rule: MockRule
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { rule.isEnabled }, set: { _ in onToggle() }))
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.7)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                    .font(.system(.body))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    MethodBadge(method: rule.matcher.method ?? "ALL")
                    Text(rule.matcher.urlPattern)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(rule.formattedDisplayDate)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                StatusBadge(code: rule.mockResponse.statusCode)
            }
        }
        .opacity(rule.isEnabled ? 1 : 0.5)
    }
}
