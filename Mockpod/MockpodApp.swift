import SwiftUI

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
}
