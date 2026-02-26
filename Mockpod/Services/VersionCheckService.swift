import Foundation

/// Fetches latest release from GitHub and compares with current app version
enum VersionCheckService {
    private static let repo = "sinanerdinc/mockpod"
    private static let apiURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!

    struct UpdateInfo {
        let latestVersion: String
        let releaseURL: URL
    }

    /// Current app version. In DEBUG, can override via UserDefaults "MockpodTestCurrentVersion" for testing.
    static var currentVersion: String {
        #if DEBUG
        if let testVersion = UserDefaults.standard.string(forKey: "MockpodTestCurrentVersion"), !testVersion.isEmpty {
            return testVersion
        }
        #endif
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Parse tag (e.g. "v1.0.4") to version string ("1.0.4")
    private static func parseTag(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// Compare semantic versions. Returns true if latest > current.
    static func isNewer(_ latest: String, than current: String) -> Bool {
        let latestParts = latest.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let maxCount = max(latestParts.count, currentParts.count)

        for i in 0..<maxCount {
            let l = i < latestParts.count ? latestParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if l > c { return true }
            if l < c { return false }
        }
        return false
    }

    /// Fetch latest release from GitHub. Returns UpdateInfo if a newer version exists.
    static func checkForUpdate() async -> UpdateInfo? {
        do {
            var request = URLRequest(url: apiURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

            struct GitHubRelease: Decodable {
                let tag_name: String
                let html_url: String
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latestVersion = parseTag(release.tag_name)
            guard let releaseURL = URL(string: release.html_url) else { return nil }

            if isNewer(latestVersion, than: currentVersion) {
                return UpdateInfo(latestVersion: latestVersion, releaseURL: releaseURL)
            }
            return nil
        } catch {
            return nil
        }
    }
}
