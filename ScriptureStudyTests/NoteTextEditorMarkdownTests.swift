#if os(macOS)
import AppKit
import Testing
@testable import ScriptureStudy

@MainActor
struct NoteTextEditorMarkdownTests {
    @Test
    func scriptureReferenceDoesNotTriggerNumberedListMarkdown() {
        let controller = makeController(text: "1 Corinthians 13:4-7")

        let markdownChanged = controller.applyLiveMarkdownTransformsIfNeeded()

        #expect(markdownChanged == false)
        #expect(controller.textView?.string == "1 Corinthians 13:4-7")
        let blockToken = controller.textView?.textStorage?.attribute(
            .richNoteBlockKind,
            at: 0,
            effectiveRange: nil
        ) as? String
        #expect(blockToken == nil || blockToken == "paragraph")
    }

    @Test
    func numberedListItemRetainsScriptureDetection() throws {
        let controller = makeController(text: "1. Jn 3:16")

        let markdownChanged = controller.applyLiveMarkdownTransformsIfNeeded()
        let linkChanged = controller.applyAutoDetectedLinksIfNeeded()

        let textView = try #require(controller.textView)
        let storage = try #require(textView.textStorage)
        let blockToken = storage.attribute(.richNoteBlockKind, at: 0, effectiveRange: nil) as? String
        let target = try #require(firstDecodedTarget(in: storage))

        #expect(markdownChanged)
        #expect(linkChanged)
        #expect(blockToken == "numbered:0:1")
        #expect(textView.string.contains("Jn 3:16"))
        #expect(target == .scripture(ScriptureLinkTarget(bookNumber: 500, chapterNumber: 3, verseNumbers: [16])))
    }

    @Test
    func bulletListItemRetainsScriptureAndStrongsDetection() throws {
        let controller = makeController(text: "- Rev 21:4\n- G25")

        let markdownChanged = controller.applyLiveMarkdownTransformsIfNeeded()
        let linkChanged = controller.applyAutoDetectedLinksIfNeeded()

        let storage = try #require(controller.textView?.textStorage)
        var blockTokens: [String] = []
        var decodedTargets: [RichNoteLinkTarget] = []

        storage.enumerateAttribute(.richNoteBlockKind, in: NSRange(location: 0, length: storage.length), options: []) { value, _, _ in
            if let token = value as? String, blockTokens.last != token {
                blockTokens.append(token)
            }
        }
        storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length), options: []) { value, _, _ in
            guard let value else { return }
            guard let target = RichNoteLinkCodec.target(from: value) else { return }
            decodedTargets.append(target)
        }

        #expect(markdownChanged)
        #expect(linkChanged)
        #expect(blockTokens.contains("bullet:0"))
        #expect(
            decodedTargets.contains(
                .scripture(ScriptureLinkTarget(bookNumber: 730, chapterNumber: 21, verseNumbers: [4]))
            )
        )
        #expect(
            decodedTargets.contains(
                .strongs(StrongsLinkTarget(number: "G25", isOldTestament: false))
            )
        )
    }

    @Test
    func headingMarkdownStillAllowsScriptureLinkDetection() throws {
        let controller = makeController(text: "# Jn 3:16")

        let markdownChanged = controller.applyLiveMarkdownTransformsIfNeeded()
        let linkChanged = controller.applyAutoDetectedLinksIfNeeded()

        let textView = try #require(controller.textView)
        let storage = try #require(textView.textStorage)
        let blockToken = storage.attribute(.richNoteBlockKind, at: 0, effectiveRange: nil) as? String
        let target = try #require(firstDecodedTarget(in: storage))

        #expect(markdownChanged)
        #expect(linkChanged)
        #expect(blockToken == "heading:1")
        #expect(textView.string == "Jn 3:16")
        #expect(target == .scripture(ScriptureLinkTarget(bookNumber: 500, chapterNumber: 3, verseNumbers: [16])))
    }

    @Test
    func inlineMarkdownPreservesScriptureAndStrongsAutoLinks() throws {
        let controller = makeController(text: "- **Jn 3:16** and *G25*")

        let markdownChanged = controller.applyLiveMarkdownTransformsIfNeeded()
        let linkChanged = controller.applyAutoDetectedLinksIfNeeded()

        let textView = try #require(controller.textView)
        let storage = try #require(textView.textStorage)
        var decodedTargets: [RichNoteLinkTarget] = []
        var fontsBySubstring: [String: NSFont] = [:]

        storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length), options: []) { value, _, _ in
            guard let value, let target = RichNoteLinkCodec.target(from: value) else { return }
            decodedTargets.append(target)
        }
        storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length), options: []) { value, range, _ in
            guard let font = value as? NSFont else { return }
            fontsBySubstring[(storage.string as NSString).substring(with: range)] = font
        }

        #expect(markdownChanged)
        #expect(linkChanged)
        #expect(textView.string == "• Jn 3:16 and G25")
        #expect(
            decodedTargets.contains(
                .scripture(ScriptureLinkTarget(bookNumber: 500, chapterNumber: 3, verseNumbers: [16]))
            )
        )
        #expect(
            decodedTargets.contains(
                .strongs(StrongsLinkTarget(number: "G25", isOldTestament: false))
            )
        )
        #expect(fontsBySubstring["Jn 3:16"]?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect(fontsBySubstring["G25"]?.fontDescriptor.symbolicTraits.contains(.italic) == true)
    }

    private func makeController(text: String) -> NoteEditorController {
        let controller = NoteEditorController()
        let textView = NSTextView()
        textView.isRichText = true
        textView.string = text
        controller.textView = textView
        return controller
    }

    private func firstDecodedTarget(in storage: NSTextStorage) -> RichNoteLinkTarget? {
        var target: RichNoteLinkTarget?
        storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length), options: []) { value, _, stop in
            guard let value else { return }
            guard let decoded = RichNoteLinkCodec.target(from: value) else { return }
            target = decoded
            stop.pointee = true
        }
        return target
    }
}
#endif
