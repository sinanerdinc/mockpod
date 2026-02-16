import SwiftUI

/// View for managing standalone mock rules
struct RuleListView: View {
    @EnvironmentObject var ruleStore: RuleStore
    @State private var showEditor = false
    @State private var editingRule: MockRule?

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
                Text("\(ruleStore.rules.count) rules, \(ruleStore.rules.filter(\.isEnabled).count) enabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
                List(ruleStore.rules, selection: $ruleStore.selectedRuleID) { rule in
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
