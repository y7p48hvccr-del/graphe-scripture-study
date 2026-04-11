#if os(macOS)
import SwiftUI
import AppKit

// MARK: - Editor Controller

class NoteEditorController: ObservableObject {
    weak var textView: NSTextView? {
        didSet {
            // Register with router when text view is assigned
            if textView != nil {
                NoteCommandRouter.shared.activeController = self
            }
        }
    }

    func bold()    { wrapSelection("**", "**") }
    func italic()  { wrapSelection("*",  "*")  }
    func heading() { insertAtLineStart("# ")   }
    func bullet()  { insertAtLineStart("- ")   }

    func changeFontSize(by delta: CGFloat) {
        guard let tv = textView,
              let current = tv.font else { return }
        let newSize = max(8, current.pointSize + delta)
        tv.font = NSFont(name: current.fontName, size: newSize)
               ?? NSFont.systemFont(ofSize: newSize)
        // Persist via AppStorage key — post notification for SettingsView to pick up
        UserDefaults.standard.set(Double(newSize), forKey: "fontSize")
    }

    private func wrapSelection(_ prefix: String, _ suffix: String) {
        guard let tv = textView else { return }
        let range    = tv.selectedRange()
        let selected = (tv.string as NSString).substring(with: range)
        tv.insertText(prefix + selected + suffix, replacementRange: range)
    }

    private func insertAtLineStart(_ prefix: String) {
        guard let tv  = textView else { return }
        let nsStr     = tv.string as NSString
        let charRange = tv.selectedRange()
        let lineRange = nsStr.lineRange(for: NSRange(location: charRange.location, length: 0))
        tv.insertText(prefix, replacementRange: NSRange(location: lineRange.location, length: 0))
    }
}

// MARK: - NSTextView Representable

struct NoteTextEditor: NSViewRepresentable {

    let noteID:        UUID           // used only to confirm identity
    let initialText:   String         // loaded once on creation
    var onTextChange:  (String) -> Void  // caller handles saving
    var fontSize:      Double
    var fontName:      String
    var controller:    NoteEditorController
    var highlight:     String = ""
    var isEditable:    Bool   = true

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let tv         = scrollView.documentView as! NSTextView

        tv.isRichText                          = false
        tv.allowsUndo                          = true
        tv.isEditable                          = isEditable
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled  = false
        tv.delegate                            = context.coordinator
        tv.textContainerInset                  = NSSize(width: 12, height: 12)
        tv.drawsBackground                     = false
        tv.font                                = resolvedFont()
        tv.string                              = initialText

        controller.textView = tv

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers  = true
        scrollView.drawsBackground     = false

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
        // Since we use .id(note.id), this view is brand new per note.
        // Only handle editability and highlights here — never touch the text.
        tv.isEditable       = isEditable
        controller.textView = tv

        if !highlight.isEmpty && highlight != context.coordinator.lastHighlight {
            context.coordinator.lastHighlight = highlight
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.applyHighlight(highlight, in: tv)
            }
        }
    }

    private func resolvedFont() -> NSFont {
        if !fontName.isEmpty, let f = NSFont(name: fontName, size: fontSize) { return f }
        return NSFont.systemFont(ofSize: fontSize)
    }

    private func applyHighlight(_ term: String, in tv: NSTextView) {
        let nsStr = tv.string as NSString
        let range = nsStr.range(of: term, options: [.caseInsensitive, .diacriticInsensitive])
        guard range.location != NSNotFound else { return }
        tv.layoutManager?.removeTemporaryAttribute(.backgroundColor,
            forCharacterRange: NSRange(location: 0, length: nsStr.length))
        tv.scrollRangeToVisible(range)
        tv.setSelectedRange(range)
        tv.layoutManager?.addTemporaryAttribute(.backgroundColor,
            value: NSColor.systemYellow.withAlphaComponent(0.55),
            forCharacterRange: range)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            tv.layoutManager?.removeTemporaryAttribute(.backgroundColor,
                forCharacterRange: NSRange(location: 0, length: (tv.string as NSString).length))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTextChange: onTextChange) }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        let onTextChange:  (String) -> Void
        var lastHighlight: String = ""

        init(onTextChange: @escaping (String) -> Void) {
            self.onTextChange = onTextChange
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            onTextChange(tv.string)
        }
    }
}
#else
import SwiftUI
import UIKit

// MARK: - iOS stub (UITextView-based, to be implemented)

class NoteEditorController: ObservableObject {
    func bold()             {}
    func italic()           {}
    func heading()          {}
    func bullet()           {}
    func changeFontSize(by delta: CGFloat) {}
}

struct NoteTextEditor: UIViewRepresentable {
    let noteID:       UUID
    let initialText:  String
    var onTextChange: (String) -> Void
    var fontSize:     Double
    var fontName:     String
    var controller:   NoteEditorController
    var highlight:    String = ""
    var isEditable:   Bool   = true

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.text       = initialText
        tv.isEditable = isEditable
        tv.font       = UIFont.systemFont(ofSize: CGFloat(fontSize))
        tv.delegate   = context.coordinator
        tv.backgroundColor = .clear
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        tv.isEditable = isEditable
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTextChange: onTextChange) }

    class Coordinator: NSObject, UITextViewDelegate {
        let onTextChange: (String) -> Void
        init(onTextChange: @escaping (String) -> Void) { self.onTextChange = onTextChange }
        func textViewDidChange(_ textView: UITextView) { onTextChange(textView.text) }
    }
}

#endif
