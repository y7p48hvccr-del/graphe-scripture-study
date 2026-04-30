import Testing
@testable import ScriptureStudy

struct PassageNavigationRequestTests {
    @Test
    func passageNavigationRequestRoundTripsUserInfo() {
        let request = PassageNavigationRequest(
            scriptureTarget: ScriptureLinkTarget(
                bookNumber: 46,
                chapterNumber: 8,
                verseNumbers: [1, 28, 31, 32]
            ),
            moduleName: "KJV"
        )

        let decoded = PassageNavigationRequest(userInfo: request.userInfo)

        #expect(decoded == request)
    }

    @Test
    func passageNavigationRequestRejectsIncompletePayloads() {
        #expect(PassageNavigationRequest(userInfo: ["chapter": 3]) == nil)
        #expect(PassageNavigationRequest(userInfo: ["bookNumber": 43]) == nil)
    }

    @Test
    func passageNavigationRequestPromotesFirstVerseFromScriptureTarget() {
        let request = PassageNavigationRequest(
            scriptureTarget: ScriptureLinkTarget(
                bookNumber: 500,
                chapterNumber: 3,
                verseNumbers: [16, 17, 18]
            )
        )

        #expect(request.verse == 16)
        #expect(request.verses == [16, 17, 18])
        #expect(request.userInfo["verse"] as? Int == 16)
    }

    @Test
    func passageNavigationRequestIgnoresEmptyOptionalPayloadFields() {
        let request = PassageNavigationRequest(bookNumber: 500, chapter: 3, verses: [], moduleName: "")

        #expect(request.userInfo["verses"] == nil)
        #expect(request.userInfo["moduleName"] == nil)
    }
}
