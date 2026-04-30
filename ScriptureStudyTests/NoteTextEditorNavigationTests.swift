#if os(macOS)
import AppKit
import Foundation
import Testing
@testable import ScriptureStudy

@MainActor
struct NoteTextEditorNavigationTests {
    @Test
    func clickingScriptureLinkPostsPassageNavigationPayload() throws {
        let coordinator = NoteTextEditor.Coordinator(onTextChange: { _ in }, onAttributedTextChange: nil)
        let target = ScriptureLinkTarget(bookNumber: 500, chapterNumber: 3, verseNumbers: [16])
        let link = try #require(RichNoteLinkCodec.url(for: .scripture(target)))

        var request: PassageNavigationRequest?
        let observer = NotificationCenter.default.addObserver(
            forName: .navigateToPassage,
            object: nil,
            queue: nil
        ) { notification in
            request = PassageNavigationRequest(userInfo: notification.userInfo)
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let handled = coordinator.textView(NSTextView(), clickedOnLink: link, at: 0)

        #expect(handled)
        #expect(request == PassageNavigationRequest(scriptureTarget: target))
    }

    @Test
    func clickingNoteLinkPostsSwitchAndNavigateNotifications() throws {
        let coordinator = NoteTextEditor.Coordinator(onTextChange: { _ in }, onAttributedTextChange: nil)
        let noteID = UUID()
        let link = try #require(RichNoteLinkCodec.url(for: .note(noteID)))

        var didSwitchToNotesTab = false
        var navigatedNoteID: UUID?
        let switchObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("switchToNotesTab"),
            object: nil,
            queue: nil
        ) { _ in
            didSwitchToNotesTab = true
        }
        let navigateObserver = NotificationCenter.default.addObserver(
            forName: .navigateToNote,
            object: nil,
            queue: nil
        ) { notification in
            navigatedNoteID = notification.userInfo?["noteID"] as? UUID
        }
        defer {
            NotificationCenter.default.removeObserver(switchObserver)
            NotificationCenter.default.removeObserver(navigateObserver)
        }

        let handled = coordinator.textView(NSTextView(), clickedOnLink: link, at: 0)

        #expect(handled)
        #expect(didSwitchToNotesTab)
        #expect(navigatedNoteID == noteID)
    }

    @Test
    func clickingStrongsLinkPostsBibleSwitchThenLookup() async throws {
        let coordinator = NoteTextEditor.Coordinator(onTextChange: { _ in }, onAttributedTextChange: nil)
        let link = try #require(
            RichNoteLinkCodec.url(
                for: .strongs(
                    StrongsLinkTarget(number: "G25", isOldTestament: false)
                )
            )
        )

        var didSwitchToBibleTab = false
        var tappedNumber: String?
        let switchObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("switchToBibleTab"),
            object: nil,
            queue: nil
        ) { _ in
            didSwitchToBibleTab = true
        }
        let strongsObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("strongsTapped"),
            object: nil,
            queue: nil
        ) { notification in
            tappedNumber = notification.userInfo?["number"] as? String
        }
        defer {
            NotificationCenter.default.removeObserver(switchObserver)
            NotificationCenter.default.removeObserver(strongsObserver)
        }

        let handled = coordinator.textView(NSTextView(), clickedOnLink: link, at: 0)
        try await Task.sleep(nanoseconds: 300_000_000)

        #expect(handled)
        #expect(didSwitchToBibleTab)
        #expect(tappedNumber == "G25")
    }
}
#endif
