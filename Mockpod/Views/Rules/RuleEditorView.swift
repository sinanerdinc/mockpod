import SwiftUI

/// Editor for a single mock rule's matcher and response
struct RuleEditorView: View {
    @Binding var rule: MockRule
    @EnvironmentObject var ruleStore: RuleStore

    @State private var responseBodyText: String = ""

    var body: some View {
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
                        .frame(width: 150)

                        Picker("Method", selection: Binding(
                            get: { rule.matcher.method ?? "ALL" },
                            set: { rule.matcher.method = $0 == "ALL" ? nil : $0 }
                        )) {
                            Text("ALL").tag("ALL")
                            ForEach(["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"], id: \.self) { m in
                                Text(m).tag(m)
                            }
                        }
                        .frame(width: 120)
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
                            TextField("0", value: Binding(
                                get: { Int((rule.mockResponse.delay ?? 0) * 1000) },
                                set: { rule.mockResponse.delay = Double($0) / 1000.0 }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        }
                    }
                }

                // Response Headers
                section("Response Headers") {
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

                Divider()

                // Response Body
                section("Response Body") {
                    MacCodeEditor(text: $rule.mockResponse.body)
                        .frame(minHeight: 200)
                        .border(Color.gray.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    HStack {
                        Button("Format JSON") {
                            formatJSON()
                        }
                        Spacer()
                        Text("\(rule.mockResponse.body.count) chars")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding()
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
        guard let data = rule.mockResponse.body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8)
        else { return }
        rule.mockResponse.body = str
    }
}

struct MacCodeEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        textView.allowsUndo = true
        
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        
        textView.delegate = context.coordinator
        
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as? NSTextView
        if textView?.string != text {
            textView?.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacCodeEditor
        
        init(_ parent: MacCodeEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            self.parent.text = textView.string
        }
    }
}
