import SwiftUI
import AppKit

@main
struct MockpodApp: App {
    @StateObject private var proxyManager = ProxyManager()
    @StateObject private var ruleStore = RuleStore()
    @StateObject private var updateChecker = UpdateChecker()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(proxyManager)
                .environmentObject(ruleStore)
                .environmentObject(updateChecker)
                .frame(minWidth: 1000, minHeight: 600)
                .onAppear {
                    syncRules()
                    updateChecker.checkForUpdate()
                }
                .onChange(of: ruleStore.rules) { _, _ in syncRules() }
                .onChange(of: ruleStore.ruleSets) { _, _ in syncRules() }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button("About Mockpod") {
                    showAboutPanel()
                }
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    updateChecker.checkForUpdate()
                }
            }
            CommandMenu("Proxy") {
                Button(proxyManager.isRunning ? "Stop Proxy" : "Start Proxy") {
                    proxyManager.toggleProxy()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Divider()

                Button("Clear Traffic") {
                    proxyManager.clearTraffic()
                }
                .keyboardShortcut("k", modifiers: .command)
            }
        }
    }

    private func syncRules() {
        proxyManager.updateActiveRules(ruleStore.allActiveRules)
    }

    private func showAboutPanel() {
        let installed = "\(VersionCheckService.currentVersion) (\(VersionCheckService.currentBuild))"
        let latest = updateChecker.latestGitHubVersion.isEmpty
            ? "Checking..."
            : updateChecker.latestGitHubVersion

        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .version: "Installed: \(installed)",
            .applicationVersion: "Latest on GitHub: \(latest)"
        ]

        let credits = NSMutableAttributedString()
        let copyrightLine = NSAttributedString(string: "Copyright © 2026 Sinan Erdinç\n")
        credits.append(copyrightLine)

        if let twitterURL = URL(string: "https://x.com/helloiamsinan") {
            let twitterLabel = NSAttributedString(string: "X: ")
            let twitterLink = NSAttributedString(
                string: "@helloiamsinan",
                attributes: [.link: twitterURL]
            )
            credits.append(NSAttributedString(string: "\n"))
            credits.append(twitterLabel)
            credits.append(twitterLink)
        }
        if credits.length > 0 {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            credits.addAttribute(
                .paragraphStyle,
                value: style,
                range: NSRange(location: 0, length: credits.length)
            )
            options[NSApplication.AboutPanelOptionKey(rawValue: "Copyright")] = ""
            options[.credits] = credits
        }

        NSApp.orderFrontStandardAboutPanel(options: options)
        NSApp.activate(ignoringOtherApps: true)
    }
}
