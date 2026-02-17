import SwiftUI
import AppKit

struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool = true
    var updateId: UUID? = nil // Only update the view content if this ID changes
    var onEditingChanged: () -> Void = {}

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        // ... (rest of makeNSView remains same)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        
        // TEMPORARY: Disable syntax highlighting to rule out cursor jumping bug
        // let textStorage = JSONSyntaxStorage()
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        
        let textContainer = NSTextContainer(size: NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.addTextContainer(textContainer)
        
        let textView = SearchableTextView(frame: .zero, textContainer: textContainer)
        textView.autoresizingMask = [.width, .height]
        textView.delegate = context.coordinator
        
        // Configuration
        textView.isEditable = isEditable
        textView.isSelectable = true
        
        // Scrolling support
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        
        // Editor styling
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isRichText = false
        
        // Search support
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        
        // Initial text set
        // textView.string = text 
        // DO NOT set string here. Let updateNSView handle it. 
        // Setting it here causes cursor reset if makeNSView is called repeatedly 
        // (which can happen in some SwiftUI container updates).
        
        scrollView.documentView = textView
        
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        
        guard let textView = scrollView.documentView as? SearchableTextView else { return }
        
        // Update editable state if changed
        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
        }
        
        // STRICT UPDATE LOGIC:
        // Only update the text view content if the `updateId` has changed.
        // This completely decouples the typing loop (textView -> binding) from the update loop (binding -> textView).
        // If updateId is nil (default behavior), we fall back to standard check, but we recommend using updateId.
        
        if let updateId = updateId {
            if updateId != context.coordinator.lastUpdateId {
                textView.string = text
                context.coordinator.lastUpdateId = updateId
            }
        } else {
            // Fallback for views not using updateId (like TrafficDetailView)
            // 1. Identity Check
            if textView.string == text {
                return
            }
            // 2. Loop Breaker
            if text == context.coordinator.lastTextFromView {
                return
            }
            // 3. Focus Check
            if let window = textView.window, 
               let firstResponder = window.firstResponder as? NSView, 
               firstResponder === textView {
                 return
            }
             // Apply external update
            textView.string = text
        }
    }


    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        // Tracks the last text we emitted to avoid redundant updates from binding
        var lastTextFromView: String?
        // Tracks the last update ID we processed
        var lastUpdateId: UUID?

        init(_ parent: CodeEditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            
            // Record what we just sent
            let currentText = textView.string
            self.lastTextFromView = currentText
            
            // Immediate update to binding (No debounce)
            // This ensures binding is always fresh and reduces the chance of race conditions.
            // Updates to `@State editedBody` are cheap, re-renders are handled by SwiftUI efficiency.
            self.parent.text = currentText
            self.parent.onEditingChanged()
        }
    }
}

/// Custom NSTextView to ensure Cmd+F is handled reliably
class SearchableTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Handle Cmd+F manually if it's not being caught
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "f" {
            // Trigger the find bar action (1 = Show Find Panel)
            let menuItem = NSMenuItem(title: "Find...", action: #selector(performFindPanelAction(_:)), keyEquivalent: "")
            menuItem.tag = 1
            self.performFindPanelAction(menuItem)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Custom TextStorage for basic JSON syntax highlighting
class JSONSyntaxStorage: NSTextStorage {
    private let backingStore = NSMutableAttributedString()
    
    // Cache regexes to avoid recompilation
    private static let stringRegex = try? NSRegularExpression(pattern: "\"[^\"\\\\]*(\\\\.[^\"\\\\]*)*\"", options: [])
    private static let numberRegex = try? NSRegularExpression(pattern: "\\b-?(?:0|[1-9]\\d*)(?:\\.\\d+)?(?:[eE][+-]?\\d+)?\\b", options: [])
    private static let boolRegex = try? NSRegularExpression(pattern: "\\b(true|false|null)\\b", options: [])
    
    override var string: String {
        return backingStore.string
    }
    
    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key : Any] {
        return backingStore.attributes(at: location, effectiveRange: range)
    }
    
    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backingStore.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: (str as NSString).length - range.length)
        endEditing()
    }
    
    override func setAttributes(_ attrs: [NSAttributedString.Key : Any]?, range: NSRange) {
        beginEditing()
        backingStore.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }
    
    override func processEditing() {
        // Only trigger syntax highlighting if characters changed.
        // If we only changed attributes (e.g. from highlighting itself), we should stop to avoid infinite loops.
        // Also skip highlighting for very large files to avoid freezing (e.g. > 50KB)
        if editedMask.contains(.editedCharacters) {
            if string.count < 50_000 {
                performSyntaxHighlighting()
            }
        }
        super.processEditing()
    }
    
    private func performSyntaxHighlighting() {
        let text = string as NSString
        let range = NSRange(location: 0, length: text.length)
        
        // We must avoid triggering another round of 'processEditing' loop if possible.
        // However, setting attributes calls 'edited', which might be fine if we guard 'processEditing' with '.editedCharacters'.
        // To be safe, we can manually modify backingStore and then call edited() once at the end? 
        // No, standard way is to just set attributes. Since we guarded processEditing, it should be fine.
        
        // Reset to default color first
        // Note: This removes all attributes. If we had other attributes (like fonts), we should be careful.
        // But for code editor, we usually control all attributes.
        // Let's just remove foreground color.
        removeAttribute(.foregroundColor, range: range)
        addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
        
        // Define colors
        let keyColor = NSColor.systemBlue
        let stringColor = NSColor.systemOrange
        let numberColor = NSColor.systemGreen
        let booleanColor = NSColor.systemPurple
        
        guard let stringRegex = Self.stringRegex,
              let numberRegex = Self.numberRegex,
              let boolRegex = Self.boolRegex else { return }
        
        // 1. Numbers (lowest priority)
        numberRegex.enumerateMatches(in: string, options: [], range: range) { match, _, _ in
            guard let matchRange = match?.range else { return }
            addAttribute(.foregroundColor, value: numberColor, range: matchRange)
        }
        
        // 2. Booleans
        boolRegex.enumerateMatches(in: string, options: [], range: range) { match, _, _ in
            guard let matchRange = match?.range else { return }
            addAttribute(.foregroundColor, value: booleanColor, range: matchRange)
        }
        
        // 3. Strings & Keys (highest priority, overwrites numbers/bools inside strings)
        stringRegex.enumerateMatches(in: string, options: [], range: range) { match, _, _ in
            guard let matchRange = match?.range else { return }
            
            // Check if it's a key (followed by :)
            // Look ahead for colon ignoring whitespace
            var isKey = false
            var i = matchRange.upperBound
            
            // Limit lookahead to avoid performance issues on huge files
            let maxLookahead = 100
            let limit = min(text.length, i + maxLookahead)
            
            while i < limit {
                let char = text.character(at: i)
                if let scalar = UnicodeScalar(char), Character(scalar).isWhitespace {
                    i += 1
                    continue
                }
                if char == 58 { // ':'
                    isKey = true
                }
                break
            }
            
            if isKey {
                addAttribute(.foregroundColor, value: keyColor, range: matchRange)
            } else {
                addAttribute(.foregroundColor, value: stringColor, range: matchRange)
            }
        }
    }
}
