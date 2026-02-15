import SwiftUI

/// Setup guide showing how to configure iOS device to use the proxy
struct SetupGuideView: View {
    @EnvironmentObject var proxyManager: ProxyManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Setup Guide")
                        .font(.largeTitle.bold())
                    Text("Follow these steps to start capturing traffic from your iOS device")
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Step 1: Start Proxy
                stepView(
                    number: 1,
                    title: "Start the Proxy Server",
                    icon: "play.circle.fill",
                    color: .green
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Click the ▶ button in the toolbar to start the proxy server.")
                        HStack(spacing: 12) {
                            Label("Status", systemImage: "circle.fill")
                                .foregroundStyle(proxyManager.isRunning ? .green : .red)
                            Text(proxyManager.isRunning ? "Running" : "Stopped")
                                .bold()
                            if proxyManager.isRunning {
                                Text("on \(proxyManager.localIP):\(proxyManager.port)")
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                        .padding(10)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                // Step 2: Install Certificate
                stepView(
                    number: 2,
                    title: "Install Root CA Certificate on iOS",
                    icon: "lock.shield.fill",
                    color: .blue
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("To inspect HTTPS traffic, your iOS device needs to trust our certificate.")

                        if proxyManager.isCertificateReady {
                            HStack(spacing: 12) {
                                Button {
                                    proxyManager.exportCertificateFile()
                                } label: {
                                    Label("Save Certificate...", systemImage: "square.and.arrow.down")
                                }
                                .buttonStyle(.borderedProminent)

                                Button {
                                    proxyManager.revealCertificateInFinder()
                                } label: {
                                    Label("Reveal in Finder", systemImage: "folder")
                                }
                            }

                            Text("Save the certificate, then AirDrop it to your iOS device or email it to yourself.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Label("Certificate not yet generated. Restart the app.", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }

                        stepsText([
                            "Save and transfer the certificate to your iOS device",
                            "Open the certificate file on iOS to download the profile",
                            "Go to Settings → General → VPN & Device Management",
                            "Tap the downloaded profile and Install",
                            "Go to Settings → General → About → Certificate Trust Settings",
                            "Enable \"Mockpod Proxy CA\" under ENABLE FULL TRUST FOR ROOT CERTIFICATES"
                        ])
                    }
                }

                // Step 3: Configure WiFi Proxy
                stepView(
                    number: 3,
                    title: "Configure WiFi Proxy on iOS",
                    icon: "wifi",
                    color: .orange
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your iOS device and Mac must be on the same WiFi network.")

                        stepsText([
                            "Go to Settings → Wi-Fi",
                            "Tap the ℹ️ icon next to your connected WiFi network",
                            "Scroll down and tap Configure Proxy",
                            "Select Manual",
                            "Server: \(proxyManager.isRunning ? proxyManager.localIP : "<start proxy first>")",
                            "Port: \(proxyManager.port)",
                            "Tap Save"
                        ])
                    }
                }

                // Step 4: Capture
                stepView(
                    number: 4,
                    title: "Start Capturing Traffic",
                    icon: "antenna.radiowaves.left.and.right",
                    color: .purple
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Open any app on your iOS device. HTTP/HTTPS traffic will appear in the Traffic tab.")
                        Text("Tip: Use Record mode (● button) to automatically save all traffic as a rule set for later mocking.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(24)
        }
    }

    private func stepView(
        number: Int,
        title: String,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> some View
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Step \(number): \(title)")
                    .font(.title3.bold())
                content()
            }
        }
    }

    private func stepsText(_ steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 6) {
                    Text("\(index + 1).")
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .trailing)
                    Text(step)
                }
                .font(.callout)
            }
        }
        .padding(10)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
