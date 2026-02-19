import SwiftUI

/// Popover for advanced traffic filtering by host, method, and status code
struct AdvancedFilterView: View {
    @EnvironmentObject var proxyManager: ProxyManager

    @State private var hostExpanded = true
    @State private var methodExpanded = true
    @State private var statusExpanded = true
    @State private var customHost = ""

    private let allMethods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Advanced Filters")
                    .font(.headline)
                Spacer()
                if proxyManager.advancedFilter.isActive {
                    Button("Clear All") {
                        proxyManager.advancedFilter.clearAll()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .font(.caption)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    // MARK: - Host Filter
                    DisclosureGroup(isExpanded: $hostExpanded) {
                        VStack(alignment: .leading, spacing: 6) {
                            Picker("Mode", selection: $proxyManager.advancedFilter.hostFilterMode) {
                                ForEach(FilterMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()

                            if proxyManager.uniqueHosts.isEmpty {
                                Text("No hosts captured yet")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .padding(.vertical, 4)
                            } else {
                                ForEach(proxyManager.uniqueHosts, id: \.self) { host in
                                    FilterCheckbox(
                                        label: host,
                                        isChecked: proxyManager.advancedFilter.hostFilters.contains(host)
                                    ) { checked in
                                        if checked {
                                            proxyManager.advancedFilter.hostFilters.insert(host)
                                        } else {
                                            proxyManager.advancedFilter.hostFilters.remove(host)
                                        }
                                    }
                                }
                            }

                            // Custom host input
                            HStack(spacing: 4) {
                                TextField("Add host...", text: $customHost)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)
                                    .onSubmit {
                                        addCustomHost()
                                    }
                                Button {
                                    addCustomHost()
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .disabled(customHost.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                        .padding(.top, 4)
                    } label: {
                        filterSectionLabel("Host", icon: "server.rack", count: proxyManager.advancedFilter.hostFilters.count)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)

                    Divider().padding(.horizontal, 12)

                    // MARK: - Method Filter
                    DisclosureGroup(isExpanded: $methodExpanded) {
                        VStack(alignment: .leading, spacing: 6) {
                            Picker("Mode", selection: $proxyManager.advancedFilter.methodFilterMode) {
                                ForEach(FilterMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()

                            ForEach(allMethods, id: \.self) { method in
                                FilterCheckbox(
                                    label: method,
                                    isChecked: proxyManager.advancedFilter.methodFilters.contains(method),
                                    badge: AnyView(MethodBadge(method: method))
                                ) { checked in
                                    if checked {
                                        proxyManager.advancedFilter.methodFilters.insert(method)
                                    } else {
                                        proxyManager.advancedFilter.methodFilters.remove(method)
                                    }
                                }
                            }
                        }
                        .padding(.top, 4)
                    } label: {
                        filterSectionLabel("HTTP Method", icon: "arrow.left.arrow.right", count: proxyManager.advancedFilter.methodFilters.count)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)

                    Divider().padding(.horizontal, 12)

                    // MARK: - Status Code Filter
                    DisclosureGroup(isExpanded: $statusExpanded) {
                        VStack(alignment: .leading, spacing: 6) {
                            Picker("Mode", selection: $proxyManager.advancedFilter.statusCodeFilterMode) {
                                ForEach(FilterMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()

                            if proxyManager.uniqueStatusCodes.isEmpty {
                                Text("No status codes captured yet")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .padding(.vertical, 4)
                            } else {
                                let grouped = Dictionary(grouping: proxyManager.uniqueStatusCodes) { ($0 / 100) * 100 }
                                ForEach(grouped.keys.sorted(), id: \.self) { group in
                                    Text(statusGroupLabel(group))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 4)

                                    ForEach(grouped[group] ?? [], id: \.self) { code in
                                        FilterCheckbox(
                                            label: "\(code)",
                                            isChecked: proxyManager.advancedFilter.statusCodeFilters.contains(code),
                                            badge: AnyView(StatusBadge(code: code))
                                        ) { checked in
                                            if checked {
                                                proxyManager.advancedFilter.statusCodeFilters.insert(code)
                                            } else {
                                                proxyManager.advancedFilter.statusCodeFilters.remove(code)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.top, 4)
                    } label: {
                        filterSectionLabel("Status Code", icon: "number", count: proxyManager.advancedFilter.statusCodeFilters.count)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
                .padding(.vertical, 4)
            }
        }
        .frame(width: 280)
        .frame(maxHeight: 460)
    }

    // MARK: - Helpers

    private func addCustomHost() {
        let trimmed = customHost.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        proxyManager.advancedFilter.hostFilters.insert(trimmed)
        customHost = ""
    }

    private func filterSectionLabel(_ title: String, icon: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(title)
                .font(.subheadline.weight(.medium))
            if count > 0 {
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            }
        }
    }

    private func statusGroupLabel(_ group: Int) -> String {
        switch group {
        case 200: return "2xx — Success"
        case 300: return "3xx — Redirection"
        case 400: return "4xx — Client Error"
        case 500: return "5xx — Server Error"
        default: return "\(group / 100)xx"
        }
    }
}

/// Reusable checkbox row for filter items
struct FilterCheckbox: View {
    let label: String
    let isChecked: Bool
    var badge: AnyView? = nil
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!isChecked)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isChecked ? Color.accentColor : .secondary)
                    .font(.system(size: 14))

                if let badge = badge {
                    badge
                } else {
                    Text(label)
                        .font(.system(.caption, design: .monospaced))
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
