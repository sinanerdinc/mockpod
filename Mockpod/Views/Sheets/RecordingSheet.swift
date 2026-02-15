import SwiftUI

/// Recording mode name input sheet
struct RecordingSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject var proxyManager: ProxyManager
    @ObservedObject var ruleStore: RuleStore
    @State private var name = ""

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "record.circle")
                .font(.system(size: 40))
                .foregroundStyle(.red)

            Text("Start Recording")
                .font(.title2.bold())

            Text("All traffic will be captured and saved as a rule set.\nYou can edit individual responses after recording stops.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("Rule set name (e.g., exampleApp)", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Start Recording") {
                    guard !name.isEmpty else { return }
                    proxyManager.startRecording(name: name)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(30)
        .frame(width: 400)
    }
}
