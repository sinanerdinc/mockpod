import SwiftUI

/// Detail view for a selected traffic entry with tabs for Overview, Request, Response, and cURL
struct TrafficDetailView: View {
    @EnvironmentObject var proxyManager: ProxyManager
    @EnvironmentObject var ruleStore: RuleStore

    enum Tab: String, CaseIterable {
        case overview = "Overview"
        case request = "Request"
        case response = "Response"
        case curl = "cURL"
    }

    @State private var selectedTab: Tab = .overview

    private var entry: TrafficEntry? { proxyManager.selectedEntry }

    private func isAlreadySavedAsRule(_ entry: TrafficEntry) -> Bool {
        ruleStore.rules.contains {
            ($0.matcher.method?.uppercased() ?? "ALL") == entry.method.uppercased() &&
            $0.matcher.matchType == .exact &&
            $0.matcher.urlPattern == entry.url
        }
    }

    var body: some View {
        if let entry = entry {
            VStack(spacing: 0) {
                // Tab bar
                HStack(spacing: 0) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            Text(tab.rawValue)
                                .font(.subheadline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : .clear)
                                .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    // Save as Rule button
                    Button {
                        ruleStore.createRuleFromEntry(entry)
                        proxyManager.updateActiveRules(ruleStore.allActiveRules)
                    } label: {
                        Label("Save as Rule", systemImage: "bookmark.fill")
                            .font(.caption)
                    }
                    .disabled(isAlreadySavedAsRule(entry))
                    .help(isAlreadySavedAsRule(entry) ? "Already saved as a rule" : "Save as Rule")
                    .padding(.trailing, 8)
                }
                .background(.bar)
                Divider()

                // Tab content
                ScrollView {
                    switch selectedTab {
                    case .overview:
                        overviewTab(entry)
                    case .request:
                        requestTab(entry)
                    case .response:
                        responseTab(entry)
                    case .curl:
                        curlTab(entry)
                    }
                }
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundStyle(.quaternary)
                Text("Select a request")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Overview Tab

    private func overviewTab(_ entry: TrafficEntry) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            infoSection("General") {
                infoRow("URL", entry.url)
                infoRow("Method", entry.method)
                infoRow("Host", entry.host)
                infoRow("Path", entry.path)
                infoRow("Scheme", entry.scheme)
                if let code = entry.responseStatusCode {
                    HStack {
                        Text("Status").foregroundStyle(.secondary).frame(width: 100, alignment: .trailing)
                        StatusBadge(code: code)
                        Text(NetworkUtils.statusCodeDescription(code)).foregroundStyle(.secondary)
                    }
                }
                infoRow("Duration", entry.formattedDuration)
                infoRow("Response Size", entry.responseBodySize)
                infoRow("Time", entry.timestamp.formatted(.dateTime))
            }
        }
        .padding()
    }

    // MARK: - Request Tab

    private func requestTab(_ entry: TrafficEntry) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            infoSection("Request Headers") {
                headersList(entry.requestHeaders)
            }
            if let body = entry.prettyRequestBody, !body.isEmpty {
                infoSection("Request Body") {
                    codeBlock(body)
                }
            }
        }
        .padding()
    }

    // MARK: - Response Tab

    private func responseTab(_ entry: TrafficEntry) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let headers = entry.responseHeaders {
                infoSection("Response Headers") {
                    headersList(headers)
                }
            }
            if let body = entry.prettyResponseBody, !body.isEmpty {
                infoSection("Response Body") {
                    codeBlock(body)
                }
            }
        }
        .padding()
    }

    // MARK: - cURL Tab

    private func curlTab(_ entry: TrafficEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("cURL Command")
                    .font(.headline)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.toCurl(), forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
            codeBlock(entry.toCurl())
        }
        .padding()
    }

    // MARK: - Helper Views

    private func infoSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
            Text(value)
                .textSelection(.enabled)
                .font(.system(.body, design: .monospaced))
            Spacer()
        }
    }

    private func headersList(_ headers: [HTTPHeader]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(headers) { header in
                HStack(alignment: .top) {
                    Text(header.name)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.blue)
                    Text(header.value)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .padding(8)
        .background(Color(.textBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func codeBlock(_ text: String) -> some View {
        ScrollView(.horizontal) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
        }
        .background(Color(.textBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
