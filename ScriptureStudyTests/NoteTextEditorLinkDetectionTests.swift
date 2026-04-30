#if os(macOS)
import AppKit
import Testing
@testable import ScriptureStudy

struct NoteTextEditorLinkDetectionTests {
    @Test
    func autoDetectedLinksHandleAbbreviationsHiddenFormatCharactersAndStrongs() {
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
        #expect(
            decodedTargets.contains(
                .scripture(
                    ScriptureLinkTarget(bookNumber: 43, chapterNumber: 3, verseNumbers: [16])
                )
            )
        )
        #expect(
            decodedTargets.contains(
                .scripture(
                    ScriptureLinkTarget(bookNumber: 46, chapterNumber: 13, verseNumbers: [4, 5, 6, 7])
                )
            )
        )
        #expect(
            decodedTargets.contains(
                .strongs(StrongsLinkTarget(number: "G25", isOldTestament: false))
            )
        )
    }
}
#endif
