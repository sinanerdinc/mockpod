import Foundation
import SwiftUI

/// Central state manager for the proxy server, traffic, and recording
@MainActor
final class ProxyManager: ObservableObject {
    @Published var isRunning = false
    @Published var localIP: String = "—"
    @Published var port: Int = 8080
    @Published var trafficEntries: [TrafficEntry] = []
    @Published var selectedEntryID: UUID?
    @Published var searchText = ""
    @Published var advancedFilter = TrafficFilter()
    @Published var isRecording = false
    @Published var recordingName = ""
    @Published var recordedEntries: [TrafficEntry] = []

    private var proxyServer: ProxyServer?
    private(set) var certificateManager: CertificateManager?
    let ruleEngine = RuleEngine()

    var filteredEntries: [TrafficEntry] {
        var entries = trafficEntries

        // Text search filter
        if !searchText.isEmpty {
            entries = entries.filter { entry in
                entry.url.localizedCaseInsensitiveContains(searchText) ||
                entry.method.localizedCaseInsensitiveContains(searchText) ||
                entry.host.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Advanced filter
        if advancedFilter.isActive {
            entries = entries.filter { advancedFilter.matches($0) }
        }

        return entries
    }

    /// Unique hosts from current traffic entries
    var uniqueHosts: [String] {
        Array(Set(trafficEntries.map { $0.host })).sorted()
    }

    /// Unique status codes from current traffic entries
    var uniqueStatusCodes: [Int] {
        Array(Set(trafficEntries.compactMap { $0.responseStatusCode })).sorted()
    }

    var selectedEntry: TrafficEntry? {
        guard let id = selectedEntryID else { return nil }
        return trafficEntries.first { $0.id == id }
    }

    init() {
        localIP = NetworkUtils.getLocalIPAddress() ?? "127.0.0.1"

        // Generate certificate immediately on launch
        do {
            self.certificateManager = try CertificateManager()
        } catch {
            print("Failed to initialize CertificateManager: \(error)")
        }
    }

    // MARK: - Proxy Lifecycle

    func startProxy() {
        guard !isRunning else { return }

        do {
            let certManager: CertificateManager
            if let existing = certificateManager {
                certManager = existing
            } else {
                certManager = try CertificateManager()
            }
            self.certificateManager = certManager

            let server = ProxyServer(
                port: port,
                certificateManager: certManager,
                ruleEngine: ruleEngine
            )

            server.onTrafficCaptured = { [weak self] entry in
                DispatchQueue.main.async {
                    self?.addTrafficEntry(entry)
                }
            }

            server.onRecordingEntry = { [weak self] entry in
                DispatchQueue.main.async {
                    self?.addRecordingEntry(entry)
                }
            }

            try server.start()
            proxyServer = server
            isRunning = true
            localIP = NetworkUtils.getLocalIPAddress() ?? "127.0.0.1"
        } catch {
            print("Failed to start proxy: \(error)")
        }
    }

    func stopProxy() {
        let server = proxyServer
        proxyServer = nil
        isRunning = false
        DispatchQueue.global(qos: .utility).async {
            server?.stop()
            // server released here → deinit runs on background thread
            // syncShutdownGracefully no longer blocks main thread
        }
    }

    func toggleProxy() {
        if isRunning {
            stopProxy()
        } else {
            startProxy()
        }
    }

    // MARK: - Traffic Management

    private func addTrafficEntry(_ entry: TrafficEntry) {
        trafficEntries.insert(entry, at: 0)
        if trafficEntries.count > 1000 {
            trafficEntries.removeLast()
        }
    }

    func clearTraffic() {
        trafficEntries.removeAll()
        selectedEntryID = nil
    }

    // MARK: - Recording

    func startRecording(name: String) {
        recordingName = name
        recordedEntries.removeAll()
        isRecording = true
    }

    func stopRecording() -> [TrafficEntry] {
        isRecording = false
        let entries = recordedEntries
        recordedEntries.removeAll()
        return entries
    }

    private func addRecordingEntry(_ entry: TrafficEntry) {
        guard isRecording else { return }
        recordedEntries.append(entry)
    }

    // MARK: - Certificate

    func exportCertificatePEM() -> String? {
        try? certificateManager?.exportRootCAPEM()
    }

    var certificateFilePath: URL? {
        certificateManager?.rootCAPEMPath
    }

    /// Save the Root CA certificate to a user-chosen location via save panel
    func exportCertificateFile() {
        guard let certManager = certificateManager,
              let certData = try? certManager.exportRootCADER() else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.x509Certificate]
        panel.nameFieldStringValue = "MockpodCA.der"
        panel.title = "Export Mockpod Root CA Certificate"
        panel.message = "Save this certificate, then transfer it to your iOS device via AirDrop or email."
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? certData.write(to: url)
            }
        }
    }

    /// Reveal the certificate file in Finder
    func revealCertificateInFinder() {
        guard let path = certificateFilePath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([path])
    }

    /// Whether the certificate has been generated
    var isCertificateReady: Bool {
        certificateManager != nil
    }

    // MARK: - Rules

    func updateActiveRules(_ rules: [MockRule]) {
        ruleEngine.updateRules(rules)
    }
}
