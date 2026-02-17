import SwiftUI

/// Traffic view with split list and detail
struct TrafficView: View {
    @EnvironmentObject var proxyManager: ProxyManager
    @EnvironmentObject var ruleStore: RuleStore

    var body: some View {
        GeometryReader { geometry in
            HSplitView {
                TrafficListView()
                    .frame(width: geometry.size.width * 0.5)
                    .frame(minWidth: 300)
                TrafficDetailView()
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// List of captured HTTP traffic entries
struct TrafficListView: View {
    @EnvironmentObject var proxyManager: ProxyManager

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("Filter requests...", text: $proxyManager.searchText)
                    .textFieldStyle(.plain)
                if !proxyManager.searchText.isEmpty {
                    Button {
                        proxyManager.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.bar)

            Divider()

            // Entry list
            if proxyManager.filteredEntries.isEmpty {
                emptyState
            } else {
                List(proxyManager.filteredEntries, selection: $proxyManager.selectedEntryID) { entry in
                    TrafficRowView(entry: entry)
                        .tag(entry.id)
                }
                .listStyle(.inset)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)
            Text(proxyManager.isRunning ? "Waiting for traffic..." : "Proxy is not running")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(proxyManager.isRunning
                 ? "Configure your iOS device to use proxy \(proxyManager.localIP):\(proxyManager.port)"
                 : "Click the play button to start the proxy server")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

/// A single row in the traffic list
struct TrafficRowView: View {
    let entry: TrafficEntry

    var body: some View {
        HStack(spacing: 8) {
            MethodBadge(method: entry.method)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.path)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                Text(entry.host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let code = entry.responseStatusCode {
                    StatusBadge(code: code)
                } else {
                    ProgressView()
                        .scaleEffect(0.5)
                }
                Text(entry.formattedDuration)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
