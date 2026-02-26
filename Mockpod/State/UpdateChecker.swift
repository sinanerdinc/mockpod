import Foundation
import SwiftUI
import AppKit

/// Manages update check state and UI visibility
@MainActor
final class UpdateChecker: ObservableObject {
    @Published var updateAvailable = false
    @Published var latestVersion: String = ""
    @Published var releaseURL: URL?
    @Published var latestGitHubVersion: String = ""
    @Published var latestGitHubReleaseURL: URL?
    @Published var isDismissed = false
    @Published var isChecking = false

    var shouldShowBanner: Bool {
        updateAvailable && !isDismissed
    }

    func checkForUpdate() {
        guard !isChecking else { return }
        isChecking = true

        Task {
            defer { isChecking = false }
            if let release = await VersionCheckService.fetchLatestRelease() {
                latestGitHubVersion = release.version
                latestGitHubReleaseURL = release.releaseURL
                if VersionCheckService.isNewer(release.version, than: VersionCheckService.currentVersion) {
                    updateAvailable = true
                    latestVersion = release.version
                    releaseURL = release.releaseURL
                    isDismissed = false
                    NSSound(named: "Glass")?.play()
                } else {
                    updateAvailable = false
                }
            } else {
                updateAvailable = false
            }
        }
    }

    func dismissBanner() {
        isDismissed = true
    }
}
