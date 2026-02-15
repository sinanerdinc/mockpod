import SwiftUI
import UniformTypeIdentifiers

/// View for managing rule sets (collections of rules)
struct RuleSetListView: View {
    @EnvironmentObject var ruleStore: RuleStore
    @EnvironmentObject var proxyManager: ProxyManager
    @State private var showImporter = false
    @State private var importError: String?

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ruleSetList
                    .frame(width: geometry.size.width * 0.2)
                Divider()
                ruleSetDetail
                    .frame(width: geometry.size.width * 0.8)
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json, .mockpodRuleSet, UTType(filenameExtension: "mockpod", conformingTo: .json) ?? .json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let urlToImport = url
                Task { @MainActor in
                    do {
                        try ruleStore.importRuleSetFromFile(url: urlToImport)
                        proxyManager.updateActiveRules(ruleStore.allActiveRules)
                    } catch {
                        importError = error.localizedDescription
                    }
                }
            case .failure(let error):
                Task { @MainActor in
                    importError = error.localizedDescription
                }
            }
        }
        .alert("Import Failed", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private var ruleSetList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Rule Sets")
                    .font(.headline)
                Spacer()
                Button {
                    showImporter = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Import")

                Button {
                    if let selected = ruleStore.selectedRuleSet {
                        exportRuleSet(selected)
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(ruleStore.selectedRuleSet == nil)
                .help("Export")
            }
            .padding(8)
            .background(.bar)
            Divider()

            if ruleStore.ruleSets.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "folder")
                        .font(.system(size: 36))
                        .foregroundStyle(.quaternary)
                    Text("No rule sets")
                        .foregroundStyle(.secondary)
                    Text("Use Record mode to capture traffic\nor import a .mockpod file.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import .mockpod", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
                .padding()
            } else {
                List(ruleStore.ruleSets, selection: $ruleStore.selectedRuleSetID) { ruleSet in
                    RuleSetRowView(ruleSet: ruleSet) {
                        ruleStore.toggleRuleSet(id: ruleSet.id)
                        proxyManager.updateActiveRules(ruleStore.allActiveRules)
                    }
                    .contextMenu {
                        Button("Export...") {
                            exportRuleSet(ruleSet)
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            ruleStore.deleteRuleSet(id: ruleSet.id)
                            proxyManager.updateActiveRules(ruleStore.allActiveRules)
                        }
                    }
                    .tag(ruleSet.id)
                }
                .listStyle(.inset)
            }
        }
    }

    @ViewBuilder
    private var ruleSetDetail: some View {
        if let setID = ruleStore.selectedRuleSetID,
           let ruleSet = ruleStore.ruleSets.first(where: { $0.id == setID }) {
            RuleSetDetailView(ruleSet: Binding(
                get: { ruleStore.ruleSets.first(where: { $0.id == setID }) ?? ruleSet },
                set: {
                    ruleStore.updateRuleSet($0)
                    proxyManager.updateActiveRules(ruleStore.allActiveRules)
                }
            ))
        } else {
            VStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 40))
                    .foregroundStyle(.quaternary)
                Text("Select a rule set")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func exportRuleSet(_ ruleSet: RuleSet) {
        guard let data = try? ruleStore.exportRuleSet(ruleSet) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mockpodRuleSet, .json]
        panel.nameFieldStringValue = "\(ruleSet.name).mockpod"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? data.write(to: url)
            }
        }
    }
}

struct RuleSetRowView: View {
    let ruleSet: RuleSet
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { ruleSet.isActive }, set: { _ in onToggle() }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(ruleSet.name)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text("\(ruleSet.rules.count) rules")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(ruleSet.enabledRuleCount) active")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
            }
        }
        .opacity(ruleSet.isActive ? 1 : 0.7)
    }
}
