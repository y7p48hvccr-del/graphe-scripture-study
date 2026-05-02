import Foundation
import SQLite3
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

    @Test
    func passageNavigationResolverParsesBookChapterAndVerse() {
        let request = PassageNavigationResolver.resolveRequest(from: "John 3:16")

        #expect(request?.bookNumber == 500)
        #expect(request?.chapter == 3)
        #expect(request?.verse == 16)
    }

    @Test
    func passageNavigationResolverAcceptsUniqueBookPrefixes() {
        let request = PassageNavigationResolver.resolveRequest(from: "Gen 1:1")

        #expect(request?.bookNumber == 10)
        #expect(request?.chapter == 1)
        #expect(request?.verse == 1)
    }

    @Test
    func passageNavigationResolverRejectsUnknownBookNames() {
        #expect(PassageNavigationResolver.resolveRequest(from: "Unknown 3:16") == nil)
    }

    @Test
    func passageNavigationResolverBuildsPassageStateTitleAndUserInfo() {
        let state = PassageNavigationResolver.makePassageState(
            bookNumber: 500,
            chapter: 3,
            fallbackTitle: "Fallback"
        )

        #expect(state.title == "John 3")
        #expect(state.bookNumber == 500)
        #expect(state.chapter == 3)
        #expect(state.userInfo["bookNumber"] as? Int == 500)
        #expect(state.userInfo["chapter"] as? Int == 3)
    }

    @Test
    func biblePassageStateVerseReferenceMatchesTitle() {
        let state = BiblePassageState(title: "John 3", bookNumber: 500, chapter: 3)

        #expect(state.verseReference == "John 3")
        #expect(state.userInfo["bookNumber"] as? Int == 500)
        #expect(state.userInfo["chapter"] as? Int == 3)
    }

    @Test
    func moduleContentServiceFallsBackToSharedBookCatalogWhenBooksTableIsMissing() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BibleNoBooks-\(UUID().uuidString).sqlite3")
        defer { try? FileManager.default.removeItem(at: url) }

        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            Issue.record("Failed to open temporary bible database")
            return
        }
        defer { sqlite3_close(db) }

        guard sqlite3_exec(db, "CREATE TABLE verses (book_number INTEGER, chapter INTEGER, verse INTEGER, text TEXT);", nil, nil, nil) == SQLITE_OK else {
            Issue.record("Failed to create verses table")
            return
        }
        guard sqlite3_exec(db, "INSERT INTO verses (book_number, chapter, verse, text) VALUES (10, 1, 1, 'In the beginning');", nil, nil, nil) == SQLITE_OK else {
            Issue.record("Failed to seed verses table")
            return
        }

        let module = MyBibleModule(
            name: "KJV",
            description: "KJV",
            language: "en",
            type: .bible,
            filePath: url.path
        )

        #expect(ModuleContentService.bookNumber(forName: "Genesis", in: module) == 10)
        #expect(ModuleContentService.bookNumber(forName: "Gen", in: module) == 10)
    }
}

struct ModuleSelectionResolutionTests {
    @Test
    func moduleSelectionResolutionPrefersBundledStrongsAndSavedPaths() {
        let bible = makeModule(name: "Bible", type: .bible, path: "/tmp/bible.sqlite3")
        let savedCommentary = makeModule(name: "Saved Commentary", type: .commentary, path: "/tmp/commentary.sqlite3")
        let bundledStrongs = makeModule(name: "Bundled Strongs", type: .strongs, path: "/tmp/bundled-strongs.sqlite3")
        let dictionary = makeModule(name: "Dictionary", type: .dictionary, path: "/tmp/dictionary.sqlite3")
        let modules = [bible, savedCommentary, bundledStrongs, dictionary]

        let savedPaths = ModuleSelectionPaths(
            biblePath: bible.filePath,
            strongsPath: "/tmp/old-strongs.sqlite3",
            dictionaryPath: dictionary.filePath,
            commentaryPath: savedCommentary.filePath,
            encyclopediaPath: "",
            crossRefPath: "",
            devotionalPath: ""
        )
        let currentPaths = ModuleSelectionPaths(
            biblePath: "",
            strongsPath: "/tmp/current-strongs.sqlite3",
            dictionaryPath: "",
            commentaryPath: "",
            encyclopediaPath: "",
            crossRefPath: "",
            devotionalPath: ""
        )

        let resolved = ModuleCatalogService.resolveSelections(
            modules: modules,
            savedPaths: savedPaths,
            currentPaths: currentPaths,
            bundledCanonicalStrongsPath: bundledStrongs.filePath
        )

        #expect(resolved.bible?.filePath == bible.filePath)
        #expect(resolved.dictionary?.filePath == dictionary.filePath)
        #expect(resolved.commentary?.filePath == savedCommentary.filePath)
        #expect(resolved.strongs?.filePath == bundledStrongs.filePath)
    }

    @Test
    func moduleSelectionResolutionFallsBackToCurrentAndPreferredTypes() {
        let currentBible = makeModule(name: "Current Bible", type: .bible, path: "/tmp/current-bible.sqlite3")
        let nativeCrossRef = makeModule(name: "Native CrossRef", type: .crossRefNative, path: "/tmp/native-cross.sqlite3")
        let legacyCrossRef = makeModule(name: "Legacy CrossRef", type: .crossRef, path: "/tmp/legacy-cross.sqlite3")
        let devotional = makeModule(name: "Devotional", type: .devotional, path: "/tmp/devotional.sqlite3")
        let modules = [currentBible, nativeCrossRef, legacyCrossRef, devotional]

        let savedPaths = ModuleSelectionPaths(
            biblePath: "/tmp/missing-bible.sqlite3",
            strongsPath: "",
            dictionaryPath: "",
            commentaryPath: "",
            encyclopediaPath: "",
            crossRefPath: "",
            devotionalPath: ""
        )
        let currentPaths = ModuleSelectionPaths(
            biblePath: currentBible.filePath,
            strongsPath: "",
            dictionaryPath: "",
            commentaryPath: "",
            encyclopediaPath: "",
            crossRefPath: "",
            devotionalPath: ""
        )

        let resolved = ModuleCatalogService.resolveSelections(
            modules: modules,
            savedPaths: savedPaths,
            currentPaths: currentPaths,
            bundledCanonicalStrongsPath: nil
        )

        #expect(resolved.bible?.filePath == currentBible.filePath)
        #expect(resolved.crossRef?.filePath == nativeCrossRef.filePath)
        #expect(resolved.devotional?.filePath == devotional.filePath)
        #expect(resolved.strongs == nil)
    }

    private func makeModule(name: String, type: ModuleType, path: String) -> MyBibleModule {
        MyBibleModule(
            name: name,
            description: name,
            language: "en",
            type: type,
            filePath: path
        )
    }
}

struct SearchRouteFactoryTests {
    @Test
    func searchResultFactoriesCarryExpectedRoutes() throws {
        let bible = SearchResult.bible(
            reference: "John 3:16",
            snippet: "For God so loved the world",
            moduleName: "KJV",
            bookNumber: 500,
            chapter: 3,
            verse: 16,
            modulePath: "/tmp/kjv.sqlite3",
            score: 500
        )
        let commentary = SearchResult.commentary(
            reference: "John 3:16",
            snippet: "Commentary on mercy",
            moduleName: "Matthew Henry",
            bookNumber: 500,
            chapter: 3,
            verse: 16,
            modulePath: "/tmp/commentary.sqlite3",
            score: 400
        )
        let reference = SearchResult.reference(
            reference: "Mercy",
            snippet: "Definition of mercy",
            moduleName: "Dictionary",
            modulePath: "/tmp/dictionary.sqlite3",
            lookupQuery: "Mercy",
            kind: .dictionary,
            score: 300
        )

        let bibleRoute = try #require(bible.route)
        if case let .passage(request) = bibleRoute {
            #expect(request.bookNumber == 500)
            #expect(request.chapter == 3)
            #expect(request.verse == 16)
            #expect(request.moduleName == "KJV")
        } else {
            Issue.record("Expected bible route to be a passage request")
        }

        let commentaryRoute = try #require(commentary.route)
        if case let .commentary(bookNumber, chapter, moduleName) = commentaryRoute {
            #expect(bookNumber == 500)
            #expect(chapter == 3)
            #expect(moduleName == "Matthew Henry")
        } else {
            Issue.record("Expected commentary route to be a commentary request")
        }

        let referenceRoute = try #require(reference.route)
        if case let .reference(modulePath, lookupQuery, kind) = referenceRoute {
            #expect(modulePath == "/tmp/dictionary.sqlite3")
            #expect(lookupQuery == "Mercy")
            #expect(kind == .dictionary)
        } else {
            Issue.record("Expected reference route to be a reference lookup")
        }
    }
}

struct ModuleLookupResolverTests {
    @Test
    func moduleLookupResolverPrefersExplicitModule() {
        let dictionary = makeModule(name: "Dictionary", type: .dictionary, path: "/tmp/dictionary.sqlite3")
        let encyclopedia = makeModule(name: "Encyclopedia", type: .encyclopedia, path: "/tmp/encyclopedia.sqlite3")

        let resolved = ModuleLookupResolver.resolveLookupModules(
            preferredModule: encyclopedia,
            fallbackType: .dictionary,
            visibleModules: [dictionary, encyclopedia]
        )

        #expect(resolved.map(\.filePath) == [encyclopedia.filePath])
    }

    @Test
    func moduleLookupResolverFallsBackByTypeAcrossVisibleModules() {
        let dictionaryA = makeModule(name: "Dictionary A", type: .dictionary, path: "/tmp/dictionary-a.sqlite3")
        let dictionaryB = makeModule(name: "Dictionary B", type: .dictionary, path: "/tmp/dictionary-b.sqlite3")
        let commentary = makeModule(name: "Commentary", type: .commentary, path: "/tmp/commentary.sqlite3")

        let resolved = ModuleLookupResolver.resolveLookupModules(
            preferredModule: nil,
            fallbackType: .dictionary,
            visibleModules: [commentary, dictionaryA, dictionaryB]
        )

        #expect(resolved.map(\.filePath) == [dictionaryA.filePath, dictionaryB.filePath])
    }

    @Test
    func moduleLookupResolverReturnsEmptyWithoutPreferredModuleOrFallbackType() {
        let dictionary = makeModule(name: "Dictionary", type: .dictionary, path: "/tmp/dictionary.sqlite3")

        let resolved = ModuleLookupResolver.resolveLookupModules(
            preferredModule: nil,
            fallbackType: nil,
            visibleModules: [dictionary]
        )

        #expect(resolved.isEmpty)
    }

    private func makeModule(name: String, type: ModuleType, path: String) -> MyBibleModule {
        MyBibleModule(
            name: name,
            description: name,
            language: "en",
            type: type,
            filePath: path
        )
    }
}
