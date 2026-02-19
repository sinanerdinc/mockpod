import Foundation

/// Mode for advanced traffic filters
enum FilterMode: String, CaseIterable, Identifiable {
    case include = "Include"
    case exclude = "Exclude"

    var id: String { rawValue }
}

/// Holds advanced filter state for traffic entries
struct TrafficFilter {
    var hostFilterMode: FilterMode = .exclude
    var hostFilters: Set<String> = []

    var methodFilterMode: FilterMode = .include
    var methodFilters: Set<String> = []

    var statusCodeFilterMode: FilterMode = .include
    var statusCodeFilters: Set<Int> = []

    /// Whether any filter is currently active
    var isActive: Bool {
        !hostFilters.isEmpty || !methodFilters.isEmpty || !statusCodeFilters.isEmpty
    }

    /// Check if a traffic entry passes all active filters
    func matches(_ entry: TrafficEntry) -> Bool {
        // Host filter
        if !hostFilters.isEmpty {
            let hostMatch = hostFilters.contains(entry.host)
            switch hostFilterMode {
            case .include:
                if !hostMatch { return false }
            case .exclude:
                if hostMatch { return false }
            }
        }

        // Method filter
        if !methodFilters.isEmpty {
            let methodMatch = methodFilters.contains(entry.method.uppercased())
            switch methodFilterMode {
            case .include:
                if !methodMatch { return false }
            case .exclude:
                if methodMatch { return false }
            }
        }

        // Status code filter
        if !statusCodeFilters.isEmpty {
            if let code = entry.responseStatusCode {
                let codeMatch = statusCodeFilters.contains(code)
                switch statusCodeFilterMode {
                case .include:
                    if !codeMatch { return false }
                case .exclude:
                    if codeMatch { return false }
                }
            }
            // If no status code yet (pending), allow through unless include mode
            else if statusCodeFilterMode == .include {
                return false
            }
        }

        return true
    }

    /// Reset all filters
    mutating func clearAll() {
        hostFilters.removeAll()
        methodFilters.removeAll()
        statusCodeFilters.removeAll()
        hostFilterMode = .exclude
        methodFilterMode = .include
        statusCodeFilterMode = .include
    }
}
