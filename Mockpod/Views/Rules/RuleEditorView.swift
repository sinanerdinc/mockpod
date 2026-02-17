import SwiftUI

/// Editor for a single mock rule's matcher and response
struct RuleEditorView: View {
    @Binding var rule: MockRule
    @EnvironmentObject var ruleStore: RuleStore

    @State private var responseBodyText: String = ""
    @State private var editedBody: String = ""
    @State private var isSaveSuccess: Bool = false
    // ID to control when the editor should force update its content from the binding
    @State private var editorUpdateId: UUID = UUID()

    enum ResponseTab: String, CaseIterable {
        case body = "Body"
        case headers = "Headers"
    }

    @State private var selectedResponseTab: ResponseTab = .body

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                // Rule Name
                section("Rule Name") {
                    TextField("Name", text: $rule.name)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                // Request Matcher
                section("Request Matcher") {
                    HStack {
                        Picker("Match Type", selection: $rule.matcher.matchType) {
                            ForEach(RequestMatcher.MatchType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .frame(width: 200)

                        Picker("Method", selection: Binding(
                            get: { rule.matcher.method ?? "ALL" },
                            set: { rule.matcher.method = $0 == "ALL" ? nil : $0 }
                        )) {
                            Text("ALL").tag("ALL")
                            ForEach(["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"], id: \.self) { m in
                                Text(m).tag(m)
                            }
                        }
                        .frame(width: 160)
                    }

                    TextField("URL Pattern", text: $rule.matcher.urlPattern)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                Divider()

                // Response Configuration
                section("Response") {
                    HStack {
                        Text("Status Code")
                            .foregroundStyle(.secondary)
                        Picker("", selection: $rule.mockResponse.statusCode) {
                            ForEach([200, 201, 204, 301, 302, 400, 401, 403, 404, 409, 422, 429, 500, 502, 503], id: \.self) { code in
                                HStack {
                                    Text("\(code)")
                                    Text(NetworkUtils.statusCodeDescription(code))
                                        .foregroundStyle(.secondary)
                                }
                                .tag(code)
                            }
                        }
                        .frame(width: 140)

                        Spacer()

                        HStack {
                            Text("Delay (ms)")
                                .foregroundStyle(.secondary)
                            TextField("0", text: Binding(
                                get: {
                                    if let delay = rule.mockResponse.delay {
                                        return String(Int(delay * 1000))
                                    }
                                    return ""
                                },
                                set: { newValue in
                                    // Allow empty string to clear the value
                                    if newValue.isEmpty {
                                        rule.mockResponse.delay = nil
                                    } else if let value = Int(newValue) {
                                        rule.mockResponse.delay = Double(value) / 1000.0
                                    }
                                }
                            ))
                            .frame(width: 80)
                        }
                    }
                }

                // Response Content (Tabs)
                section("Response Content") {
                    Picker("", selection: $selectedResponseTab) {
                        ForEach(ResponseTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if selectedResponseTab == .headers {
                        // Headers Editor
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(rule.mockResponse.headers.enumerated()), id: \.element.id) { index, header in
                                HStack {
                                    TextField("Name", text: Binding(
                                        get: { rule.mockResponse.headers[index].name },
                                        set: { rule.mockResponse.headers[index].name = $0 }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 200)

                                    TextField("Value", text: Binding(
                                        get: { rule.mockResponse.headers[index].value },
                                        set: { rule.mockResponse.headers[index].value = $0 }
                                    ))
                                    .textFieldStyle(.roundedBorder)

                                    Button {
                                        rule.mockResponse.headers.remove(at: index)
                                    } label: {
                                        Image(systemName: "minus.circle")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            Button {
                                rule.mockResponse.headers.append(HTTPHeader(name: "", value: ""))
                            } label: {
                                Label("Add Header", systemImage: "plus")
                                    .font(.caption)
                            }
                        }
                        .padding(.top, 4)
                    } else {
                        // Body Editor
                        VStack(alignment: .leading, spacing: 8) {
                            CodeEditorView(text: $editedBody, updateId: editorUpdateId)
                                .frame(height: geometry.size.height * 0.9)
                                .border(Color.gray.opacity(0.3))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
        
                            HStack {
                                Button("Format JSON") {
                                    formatJSON()
                                }
                                
                                Button {
                                    rule.mockResponse.body = editedBody
                                    isSaveSuccess = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        isSaveSuccess = false
                                    }
                                } label: {
                                    if isSaveSuccess {
                                        Label("Saved!", systemImage: "checkmark")
                                            .foregroundStyle(.green)
                                    } else {
                                        Text("Save")
                                    }
                                }
                                
                                Spacer()
                                Text("\(editedBody.count) chars")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding()
        }
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        .onAppear {
            editedBody = rule.mockResponse.body
            editorUpdateId = UUID() // Force update on appear
        }
        .onChange(of: rule.id) {
            editedBody = rule.mockResponse.body
            editorUpdateId = UUID() // Force update on rule change
        }
    }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                content()
        }
    }

    private func formatJSON() {
        // Resign focus so CodeEditorView accepts the update
        NSApp.keyWindow?.makeFirstResponder(nil)
        
        guard let data = editedBody.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8)
        else { return }
        editedBody = str
        editorUpdateId = UUID() // Force update after formatting
    }
}
