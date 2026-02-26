import SwiftUI

/// Main application layout with sidebar navigation and content area
struct ContentView: View {
    @EnvironmentObject var proxyManager: ProxyManager
    @EnvironmentObject var ruleStore: RuleStore
    @EnvironmentObject var updateChecker: UpdateChecker

    enum SidebarSection: String, CaseIterable {
        case traffic = "Traffic"
        case rules = "Rules"
        case ruleSets = "Rule Sets"
        case setup = "Setup"

        var icon: String {
            switch self {
            case .traffic: return "antenna.radiowaves.left.and.right"
            case .rules: return "list.bullet.rectangle"
            case .ruleSets: return "folder"
            case .setup: return "gear"
            }
        }
    }

    @State private var selectedSection: SidebarSection = .traffic
    @State private var showRecordingSheet = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
        }
        .toolbar {
            toolbarContent
        }
        .sheet(isPresented: $showRecordingSheet) {
            RecordingSheet(
                isPresented: $showRecordingSheet,
                proxyManager: proxyManager,
                ruleStore: ruleStore
            )
        }
        .overlay(alignment: .bottomTrailing) {
            if updateChecker.shouldShowBanner {
                updateToast
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(SidebarSection.allCases, id: \.self, selection: $selectedSection) { section in
            Label {
                HStack {
                    Text(section.rawValue)
                    Spacer()
                    badge(for: section)
                }
            } icon: {
                Image(systemName: section.icon)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180)
    }

    @ViewBuilder
    private func badge(for section: SidebarSection) -> some View {
        switch section {
        case .traffic:
            if !proxyManager.trafficEntries.isEmpty {
                Text(verbatim: "\(proxyManager.trafficEntries.count)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
        case .rules:
            let activeRules = ruleStore.rules.filter(\.isEnabled).count
            if activeRules > 0 {
                Text(verbatim: "\(activeRules)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.2))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
            }
        case .ruleSets:
            let active = ruleStore.ruleSets.filter(\.isActive).count
            if active > 0 {
                Text(verbatim: "\(active)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.2))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
            }
        case .setup:
            EmptyView()
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        switch selectedSection {
        case .traffic:
            TrafficView()
        case .rules:
            RuleListView()
        case .ruleSets:
            RuleSetListView()
        case .setup:
            SetupGuideView()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // Proxy status
            HStack(spacing: 6) {
                Circle()
                    .fill(proxyManager.isRunning ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(verbatim: proxyManager.isRunning ? "\(proxyManager.localIP):\(String(proxyManager.port))" : "Stopped")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                proxyManager.toggleProxy()
            } label: {
                Image(systemName: proxyManager.isRunning ? "stop.fill" : "play.fill")
            }
            .help(proxyManager.isRunning ? "Stop Proxy" : "Start Proxy")

            Divider()

            // Record button
            Button {
                if proxyManager.isRecording {
                    let entries = proxyManager.stopRecording()
                    if !entries.isEmpty {
                        ruleStore.createRuleSetFromRecording(
                            name: proxyManager.recordingName,
                            entries: entries
                        )
                        proxyManager.updateActiveRules(ruleStore.allActiveRules)
                    }
                } else {
                    showRecordingSheet = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: proxyManager.isRecording ? "record.circle.fill" : "record.circle")
                        .foregroundStyle(proxyManager.isRecording ? .red : .primary)
                    if proxyManager.isRecording {
                        Text(proxyManager.recordingName)
                            .font(.caption)
                            .foregroundStyle(.red)
                        Text(verbatim: "(\(proxyManager.recordedEntries.count))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .help(proxyManager.isRecording ? "Stop Recording" : "Start Recording")


        }
    }

    // MARK: - Update Toast

    private var updateToast: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("A new version (\(updateChecker.latestVersion)) is available.")
                    .font(.subheadline)
                if let url = updateChecker.releaseURL {
                    Link("View details", destination: url)
                        .font(.caption.weight(.medium))
                }
            }
            Button {
                updateChecker.dismissBanner()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.orange.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .padding(24)
    }
}
