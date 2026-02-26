import Foundation
import SwiftUI
import AppKit

/// Manages update check state and UI visibility
@MainActor
final class UpdateChecker: ObservableObject {
    @Published var updateAvailable = false
    @Published var latestVersion: String = ""
    @Published var releaseURL: URL?
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
            if let info = await VersionCheckService.checkForUpdate() {
                updateAvailable = true
                latestVersion = info.latestVersion
                releaseURL = info.releaseURL
                isDismissed = false
                NSSound(named: "Glass")?.play()
            } else {
                updateAvailable = false
            }
        }
    }

    func dismissBanner() {
        isDismissed = true
    }
}
