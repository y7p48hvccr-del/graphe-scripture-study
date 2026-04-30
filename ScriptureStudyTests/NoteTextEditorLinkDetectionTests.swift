#if os(macOS)
import AppKit
import Testing
@testable import ScriptureStudy

@MainActor
struct NoteTextEditorLinkDetectionTests {
    @Test
    func autoDetectedLinksHandleAbbreviationsHiddenFormatCharactersAndStrongs() throws {
        let controller = NoteEditorController()
        let textView = NSTextView()
        textView.isRichText = true
        textView.string = "Jn 3:16\n1 \u{200B}Corinthians 13\u{200B}:4\u{200B}-7\nG\u{200B}25"
        controller.textView = textView

        let changed = controller.applyAutoDetectedLinksIfNeeded()
        let storage = try #require(textView.textStorage)
        var decodedTargets: [RichNoteLinkTarget] = []

        storage.enumerateAttribute(
            .link,
            in: NSRange(location: 0, length: storage.length),
            options: []
        ) { value, _, _ in
            guard let value, let target = RichNoteLinkCodec.target(from: value) else { return }
            decodedTargets.append(target)
        }

        #expect(changed)
        #expect(decodedTargets.count == 3)
        let scriptureTargets = decodedTargets.compactMap { target -> ScriptureLinkTarget? in
            guard case .scripture(let scripture) = target else { return nil }
            return scripture
        }
        #expect(
            scriptureTargets.contains {
                $0.chapterNumber == 3 && $0.verseNumbers == [16]
            }
        )
        #expect(
            scriptureTargets.contains {
                $0.chapterNumber == 13 && $0.verseNumbers == [4, 5, 6, 7]
            }
        )
        #expect(
            decodedTargets.contains(
                .strongs(StrongsLinkTarget(number: "G25", isOldTestament: false))
            )
        )
    }

    @Test
    func autoDetectedLinksAvoidAmbiguousAbbreviations() {
        let controller = NoteEditorController()
        let textView = NSTextView()
        textView.isRichText = true
        textView.string = "Co 1:1\nTi 2:1"
        controller.textView = textView

        let changed = controller.applyAutoDetectedLinksIfNeeded()
        let storage = textView.textStorage!
        var linkCount = 0
        storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length), options: []) { value, _, _ in
            if value != nil {
                linkCount += 1
            }
        }

        #expect(changed == false)
        #expect(linkCount == 0)
    }
}
#endif
