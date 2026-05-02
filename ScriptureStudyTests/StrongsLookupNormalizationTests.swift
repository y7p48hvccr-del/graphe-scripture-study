#if os(macOS)
import CommonCrypto
import Foundation
import SQLite3
import Testing
@testable import ScriptureStudy

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@MainActor
struct StrongsLookupNormalizationTests {
    @Test
    func exactExtendedGreekKeyRemainsDistinctFromNearbyStandardKey() async throws {
        let dbURL = try makeDictionaryDatabase(entries: [
            ("G311", "delay"),
            ("G00311", "tell")
        ])
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let service = MyBibleService()
        let module = MyBibleModule(
            name: "Strongs",
            description: "Test",
            language: "en",
            type: .strongs,
            filePath: dbURL.path
        )

        let entry = try #require(await service.lookupStrongs(module: module, number: "G00311"))

        #expect(entry.topic == "G00311")
        #expect(entry.shortDefinition == "tell")
    }

    @Test
    func exactExtendedHebrewKeyRemainsDistinctFromNearbyStandardKey() async throws {
        let dbURL = try makeDictionaryDatabase(entries: [
            ("H31", "common"),
            ("H00031", "extended")
        ])
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let service = MyBibleService()
        let module = MyBibleModule(
            name: "Strongs",
            description: "Test",
            language: "en",
            type: .strongs,
            filePath: dbURL.path
        )

        let entry = try #require(await service.lookupStrongs(module: module, number: "H00031", isOldTestament: true))

        #expect(entry.topic == "H00031")
        #expect(entry.shortDefinition == "extended")
    }

    @Test
    func lowercasePaddedStandardGreekKeyResolvesCanonicalEntry() async throws {
        let dbURL = try makeDictionaryDatabase(entries: [
            ("G3056", "word")
        ])
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let service = MyBibleService()
        let module = MyBibleModule(
            name: "Strongs",
            description: "Test",
            language: "en",
            type: .strongs,
            filePath: dbURL.path
        )

        let entry = try #require(await service.lookupStrongs(module: module, number: "g03056"))

        #expect(entry.topic == "G3056")
        #expect(entry.shortDefinition == "word")
    }

    @Test
    func expandedDefinitionBecomesPreferredDefinitionHTML() async throws {
        let dbURL = try makeDictionaryDatabase(
            entries: [("G3056", "word")],
            expandedDefinitions: ["G3056": "<b>Expanded</b>"],
            sourceFlags: ["G3056": "both"]
        )
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let service = MyBibleService()
        let module = MyBibleModule(
            name: "Strongs",
            description: "Test",
            language: "en",
            type: .strongs,
            filePath: dbURL.path
        )

        let entry = try #require(await service.lookupStrongs(module: module, number: "G3056"))

        #expect(entry.expandedDefinition == "<b>Expanded</b>")
        #expect(entry.sourceFlags == "both")
        #expect(entry.preferredDefinitionHTML == "<b>Expanded</b>")
    }

    private func makeDictionaryDatabase(
        entries: [(topic: String, shortDefinition: String)],
        expandedDefinitions: [String: String] = [:],
        sourceFlags: [String: String] = [:]
    ) throws -> URL {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrongsLookup-\(UUID().uuidString).sqlite3")
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK, let db else {
            throw DatabaseError.openFailed
        }
        defer { sqlite3_close(db) }

        let statements = [
            """
            CREATE TABLE dictionary (
                topic TEXT PRIMARY KEY,
                lexeme TEXT,
                transliteration TEXT,
                pronunciation TEXT,
                short_definition TEXT,
                definition TEXT,
                expanded_definition TEXT,
                source_flags TEXT NOT NULL DEFAULT 'strong'
            );
            """,
            """
            CREATE TABLE cognate_strong_numbers (
                strong_number TEXT,
                group_id INTEGER
            );
            """
        ]

        for statement in statements {
            guard sqlite3_exec(db, statement, nil, nil, nil) == SQLITE_OK else {
                throw DatabaseError.schemaFailed
            }
        }

        for entry in entries {
            let sql = "INSERT INTO dictionary (topic, lexeme, transliteration, pronunciation, short_definition, definition, expanded_definition, source_flags) VALUES (?, '', '', '', ?, 'Derivation: root\\nKJV: usage', ?, ?)"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
                throw DatabaseError.insertFailed
            }
            sqlite3_bind_text(stmt, 1, (entry.topic as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (entry.shortDefinition as NSString).utf8String, -1, nil)
            let expanded = expandedDefinitions[entry.topic] ?? ""
            let source = sourceFlags[entry.topic] ?? "strong"
            sqlite3_bind_text(stmt, 3, (expanded as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 4, (source as NSString).utf8String, -1, nil)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                sqlite3_finalize(stmt)
                throw DatabaseError.insertFailed
            }
            sqlite3_finalize(stmt)
        }

        return dbURL
    }

    private enum DatabaseError: Error {
        case openFailed
        case schemaFailed
        case insertFailed
    }
}

struct SearchCoordinatorModeTests {
    @Test
    func searchCoordinatorModeOrderingReprioritizesAggregateResults() throws {
        let bibleURL = try makeBibleDatabase(verseText: "Mercy triumphs over judgment.")
        let commentaryURL = try makeCommentaryDatabase(text: "Mercy is central to this passage.")
        let dictionaryURL = try makeReferenceDatabase(topic: "Mercy", definition: "Mercy means compassion shown to the undeserving.")
        defer {
            try? FileManager.default.removeItem(at: bibleURL)
            try? FileManager.default.removeItem(at: commentaryURL)
            try? FileManager.default.removeItem(at: dictionaryURL)
        }

        let bibleModule = makeModule(name: "Sample Bible", type: .bible, path: bibleURL.path)
        let commentaryModule = makeModule(name: "Sample Commentary", type: .commentary, path: commentaryURL.path)
        let dictionaryModule = makeModule(name: "Sample Dictionary", type: .dictionary, path: dictionaryURL.path)

        let context = SearchExecutionContext(
            visibleModules: [bibleModule, commentaryModule, dictionaryModule],
            catalogRecordsByPath: [:],
            selectedBible: bibleModule,
            selectedDictionary: dictionaryModule,
            selectedEncyclopedia: nil,
            notes: []
        )

        let globalTypes = SearchCoordinator.performSearch(
            request: makeSearchRequest(mode: .global),
            context: context
        ).map(\.type)
        let bibleFirstTypes = SearchCoordinator.performSearch(
            request: makeSearchRequest(mode: .bibleFirst),
            context: context
        ).map(\.type)
        let referenceFirstTypes = SearchCoordinator.performSearch(
            request: makeSearchRequest(mode: .referenceFirst),
            context: context
        ).map(\.type)
        let commentaryFirstTypes = SearchCoordinator.performSearch(
            request: makeSearchRequest(mode: .commentaryFirst),
            context: context
        ).map(\.type)

        #expect(globalTypes.prefix(3).elementsEqual([.bible, .reference, .commentary]))
        #expect(bibleFirstTypes.prefix(3).elementsEqual([.bible, .commentary, .reference]))
        #expect(referenceFirstTypes.prefix(3).elementsEqual([.reference, .commentary, .bible]))
        #expect(commentaryFirstTypes.prefix(3).elementsEqual([.commentary, .bible, .reference]))
    }

    private func makeSearchRequest(mode: SearchMode) -> SearchRequest {
        SearchRequest(
            query: "Mercy",
            scope: .all,
            mode: mode,
            testament: .both,
            bookFilter: 0,
            exact: false,
            notesFrom: nil,
            notesTo: nil,
            selectedBiblePaths: [],
            selectedCommentaryPaths: []
        )
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

    private func makeBibleDatabase(verseText: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BibleSearch-\(UUID().uuidString).sqlite3")
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            throw SearchDatabaseError.openFailed
        }
        defer { sqlite3_close(db) }

        try execute("CREATE TABLE verses (book_number INTEGER, chapter INTEGER, verse INTEGER, text TEXT);", in: db)
        try execute("INSERT INTO verses (book_number, chapter, verse, text) VALUES (500, 3, 16, '\(escapedSQL(verseText))');", in: db)
        return url
    }

    private func makeCommentaryDatabase(text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CommentarySearch-\(UUID().uuidString).sqlite3")
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            throw SearchDatabaseError.openFailed
        }
        defer { sqlite3_close(db) }

        try execute("CREATE TABLE commentaries (book_number INTEGER, chapter_number_from INTEGER, verse_number_from INTEGER, text TEXT);", in: db)
        try execute("INSERT INTO commentaries (book_number, chapter_number_from, verse_number_from, text) VALUES (500, 3, 16, '\(escapedSQL(text))');", in: db)
        return url
    }

    private func makeReferenceDatabase(topic: String, definition: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReferenceSearch-\(UUID().uuidString).sqlite3")
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            throw SearchDatabaseError.openFailed
        }
        defer { sqlite3_close(db) }

        try execute("CREATE TABLE dictionary (topic TEXT, definition TEXT);", in: db)
        try execute(
            "INSERT INTO dictionary (topic, definition) VALUES ('\(escapedSQL(topic))', '\(escapedSQL(definition))');",
            in: db
        )
        return url
    }

    private func execute(_ sql: String, in db: OpaquePointer) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw SearchDatabaseError.statementFailed
        }
    }

    private func escapedSQL(_ text: String) -> String {
        text.replacingOccurrences(of: "'", with: "''")
    }

    private enum SearchDatabaseError: Error {
        case openFailed
        case statementFailed
    }
}

struct SearchCapabilityFilteringTests {
    @Test
    func searchCoordinatorSkipsReadableOnlyReferenceModules() throws {
        let dictionaryURL = try makeReferenceDatabase(topic: "Mercy", definition: "Mercy means compassion.")
        defer { try? FileManager.default.removeItem(at: dictionaryURL) }

        let dictionaryModule = makeModule(name: "Readable Only Dictionary", type: .dictionary, path: dictionaryURL.path)
        let context = SearchExecutionContext(
            visibleModules: [dictionaryModule],
            catalogRecordsByPath: [
                dictionaryModule.filePath: ModuleCatalogRecord(
                    module: dictionaryModule,
                    metadata: GrapheModuleMetadata(
                        identifier: "readable-only-dictionary",
                        displayName: dictionaryModule.name,
                        kind: .dictionary,
                        contentFormat: "sqlite-legacy",
                        version: "1",
                        source: nil,
                        capabilities: ["articleLookup"],
                        language: "en"
                    ),
                    metadataBlob: "mercy readable only",
                    validation: GrapheRuntimeValidationReport(
                        state: .readableOnly,
                        matchedProfileName: nil,
                        rejectionReasons: ["No registered profile matched."],
                        moduleType: .dictionary,
                        hasStrongsCapability: false
                    )
                )
            ],
            selectedBible: nil,
            selectedDictionary: dictionaryModule,
            selectedEncyclopedia: nil,
            notes: []
        )

        let results = SearchCoordinator.performSearch(
            request: SearchRequest(
                query: "Mercy",
                scope: .reference,
                mode: .global,
                testament: .both,
                bookFilter: 0,
                exact: false,
                notesFrom: nil,
                notesTo: nil,
                selectedBiblePaths: [],
                selectedCommentaryPaths: []
            ),
            context: context
        )

        #expect(results.isEmpty)
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

    private func makeReferenceDatabase(topic: String, definition: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapabilityReference-\(UUID().uuidString).sqlite3")
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            throw SearchCapabilityDatabaseError.openFailed
        }
        defer { sqlite3_close(db) }

        guard sqlite3_exec(db, "CREATE TABLE dictionary (topic TEXT, definition TEXT);", nil, nil, nil) == SQLITE_OK else {
            throw SearchCapabilityDatabaseError.statementFailed
        }
        let sql = "INSERT INTO dictionary (topic, definition) VALUES ('\(escapedSQL(topic))', '\(escapedSQL(definition))');"
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw SearchCapabilityDatabaseError.statementFailed
        }
        return url
    }

    private func escapedSQL(_ text: String) -> String {
        text.replacingOccurrences(of: "'", with: "''")
    }

    private enum SearchCapabilityDatabaseError: Error {
        case openFailed
        case statementFailed
    }
}

struct RuntimeProfileValidationTests {
    @Test
    func runtimeProfileValidatorMatchesBibleProfile() {
        let report = GrapheRuntimeProfileValidator.validate(
            info: ["description": "Sample Bible"],
            tables: ["info", "verses"],
            path: "/tmp/sample-bible.graphe"
        )

        #expect(report.state == .ready)
        #expect(report.matchedProfileName == "bible-verses")
        #expect(report.moduleType == .bible)
    }

    @Test
    func runtimeProfileValidatorMarksUnknownShapesReadableOnly() {
        let report = GrapheRuntimeProfileValidator.validate(
            info: ["description": "Odd Module"],
            tables: ["info", "mystery_table"],
            path: "/tmp/odd-module.graphe"
        )

        #expect(report.state == .readableOnly)
        #expect(report.matchedProfileName == nil)
        #expect(report.moduleType == .unknown)
        #expect(report.rejectionReasons.isEmpty == false)
    }

    @Test
    func runtimeModuleAccessorRejectsModulesWithoutReadableTables() throws {
        let url = try makeEmptyDatabase()
        defer { try? FileManager.default.removeItem(at: url) }

        let inspection = GrapheRuntimeModuleAccessor().inspectModule(at: url.path)

        #expect(inspection?.validationReport.state == .rejected)
        #expect(inspection?.validationReport.matchedProfileName == nil)
        #expect(inspection?.validationReport.rejectionReasons.isEmpty == false)
    }

    private func makeEmptyDatabase() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ValidationEmpty-\(UUID().uuidString).sqlite3")
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            throw ValidationDatabaseError.openFailed
        }
        sqlite3_close(db)
        return url
    }

    private enum ValidationDatabaseError: Error {
        case openFailed
    }
}

struct GrapheSearchFallbackTests {
    @Test
    func searchCoordinatorFindsBibleTextInEncryptedGrapheVerses() throws {
        let url = try makeEncryptedGrapheBibleDatabase(verseText: "The Lord is my shepherd.")
        defer { try? FileManager.default.removeItem(at: url) }

        let module = MyBibleModule(
            name: "Encrypted Bible",
            description: "Encrypted Bible",
            language: "en",
            type: .bible,
            filePath: url.path
        )

        let context = SearchExecutionContext(
            visibleModules: [module],
            catalogRecordsByPath: [:],
            selectedBible: module,
            selectedDictionary: nil,
            selectedEncyclopedia: nil,
            notes: []
        )

        let results = SearchCoordinator.performSearch(
            request: SearchRequest(
                query: "Lord",
                scope: .bible,
                mode: .global,
                testament: .both,
                bookFilter: 0,
                exact: false,
                notesFrom: nil,
                notesTo: nil,
                selectedBiblePaths: [],
                selectedCommentaryPaths: []
            ),
            context: context
        )

        #expect(results.contains(where: { $0.type == .bible && $0.reference.contains("Genesis 1:1") }))
    }

    private func makeEncryptedGrapheBibleDatabase(verseText: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("EncryptedBible-\(UUID().uuidString).graphe")
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            throw GrapheSearchFallbackError.openFailed
        }
        defer { sqlite3_close(db) }

        guard sqlite3_exec(db, "CREATE TABLE verses (book_number INTEGER, chapter INTEGER, verse INTEGER, text BLOB);", nil, nil, nil) == SQLITE_OK else {
            throw GrapheSearchFallbackError.statementFailed
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO verses (book_number, chapter, verse, text) VALUES (?, ?, ?, ?);", -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw GrapheSearchFallbackError.statementFailed
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, 10)
        sqlite3_bind_int(statement, 2, 1)
        sqlite3_bind_int(statement, 3, 1)
        let encryptedValue = try encryptedGrapheBlob(for: verseText)
        let bindStatus = encryptedValue.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, 4, bytes.baseAddress, Int32(bytes.count), SQLITE_TRANSIENT)
        }
        guard bindStatus == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else {
            throw GrapheSearchFallbackError.statementFailed
        }

        return url
    }

    private enum GrapheSearchFallbackError: Error {
        case openFailed
        case statementFailed
    }
}

struct ModuleCatalogMetadataReaderTests {
    @Test
    func runtimeInspectionMetadataTakesPrecedenceOverSidecarCompatibilityMetadata() async throws {
        let harness = try makeCatalogModuleHarness(
            filename: "Aligned.bibles.sqlite3",
            infoEntries: [
                ("description", "Runtime Bible"),
                ("language", "gr"),
                ("identifier", "runtime-id")
            ],
            sidecarContents: """
            Name: Sidecar Bible
            Language: en
            Identifier: sidecar-id
            Type: Dictionary
            """
        )
        defer { try? harness.cleanup() }

        let result = try await ModuleCatalogService.scanModules(
            folderURL: harness.rootURL,
            bundledCanonicalStrongsPath: nil
        )

        let record = try #require(result.recordsByPath[harness.moduleURL.path])
        #expect(record.metadata.displayName == "Runtime Bible")
        #expect(record.metadata.language == "gr")
        #expect(record.metadata.identifier == "runtime-id")
        #expect(record.metadata.kind == .bible)
    }

    @Test
    func sidecarCompatibilityMetadataFillsCatalogWhenInfoTableIsUnavailable() async throws {
        let harness = try makeCatalogModuleHarness(
            filename: "Legacy.bibles.sqlite3",
            infoEntries: [],
            sidecarContents: """
            Name: Sidecar Bible
            Language: es
            Identifier: sidecar-id
            Version: 3
            Source: Legacy Library
            Type: Bible
            """
        )
        defer { try? harness.cleanup() }

        let result = try await ModuleCatalogService.scanModules(
            folderURL: harness.rootURL,
            bundledCanonicalStrongsPath: nil
        )

        let record = try #require(result.recordsByPath[harness.moduleURL.path])
        #expect(record.metadata.displayName == "Sidecar Bible")
        #expect(record.metadata.language == "es")
        #expect(record.metadata.identifier == "sidecar-id")
        #expect(record.metadata.version == "3")
        #expect(record.metadata.source == "Legacy Library")
        #expect(record.metadata.kind == .bible)
    }

    @Test
    func filenameFallbackProvidesCatalogMetadataWhenRuntimeAndSidecarMetadataAreAbsent() async throws {
        let harness = try makeCatalogModuleHarness(
            filename: "Fallback.bibles.sqlite3",
            infoEntries: [],
            sidecarContents: nil
        )
        defer { try? harness.cleanup() }

        let result = try await ModuleCatalogService.scanModules(
            folderURL: harness.rootURL,
            bundledCanonicalStrongsPath: nil
        )

        let record = try #require(result.recordsByPath[harness.moduleURL.path])
        #expect(record.metadata.displayName == "Fallback")
        #expect(record.metadata.kind == .bible)
        #expect(record.metadata.contentFormat == "sqlite-legacy")
    }

    @Test
    func grapheRuntimeInspectionDecryptsEncryptedInfoValues() async throws {
        let harness = try makeCatalogModuleHarness(
            filename: "Encrypted.bibles.graphe",
            infoEntries: [
                ("description", "Encrypted Runtime Bible"),
                ("language", "he"),
                ("identifier", "encrypted-runtime-id")
            ],
            sidecarContents: nil,
            encryptInfoValues: true
        )
        defer { try? harness.cleanup() }

        let result = try await ModuleCatalogService.scanModules(
            folderURL: harness.rootURL,
            bundledCanonicalStrongsPath: nil
        )

        let record = try #require(result.recordsByPath[harness.moduleURL.path])
        #expect(record.metadata.displayName == "Encrypted Runtime Bible")
        #expect(record.metadata.language == "he")
        #expect(record.metadata.identifier == "encrypted-runtime-id")
        #expect(record.metadata.kind == .bible)
        #expect(record.metadata.contentFormat == "graphe")
    }

    private func makeCatalogModuleHarness(
        filename: String,
        infoEntries: [(String, String)],
        sidecarContents: String?,
        encryptInfoValues: Bool = false
    ) throws -> CatalogModuleHarness {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CatalogHarness-\(UUID().uuidString)", isDirectory: true)
        let modulesURL = rootURL.appendingPathComponent("Bibles", isDirectory: true)
        let moduleInfoURL = rootURL.appendingPathComponent("_ModuleInfo", isDirectory: true)
        try FileManager.default.createDirectory(at: modulesURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: moduleInfoURL, withIntermediateDirectories: true)

        let moduleURL = modulesURL.appendingPathComponent(filename)
        var db: OpaquePointer?
        guard sqlite3_open(moduleURL.path, &db) == SQLITE_OK, let db else {
            throw CatalogHarnessError.openFailed
        }
        defer { sqlite3_close(db) }

        guard sqlite3_exec(db, "CREATE TABLE verses (book_number INTEGER, chapter INTEGER, verse INTEGER, text TEXT);", nil, nil, nil) == SQLITE_OK else {
            throw CatalogHarnessError.statementFailed
        }
        if !infoEntries.isEmpty {
            let valueType = encryptInfoValues ? "BLOB" : "TEXT"
            guard sqlite3_exec(db, "CREATE TABLE info (name TEXT, value \(valueType));", nil, nil, nil) == SQLITE_OK else {
                throw CatalogHarnessError.statementFailed
            }
            if encryptInfoValues {
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, "INSERT INTO info (name, value) VALUES (?, ?);", -1, &statement, nil) == SQLITE_OK,
                      let statement
                else {
                    throw CatalogHarnessError.statementFailed
                }
                defer { sqlite3_finalize(statement) }

                for (name, value) in infoEntries {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    guard sqlite3_bind_text(statement, 1, name, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
                        throw CatalogHarnessError.statementFailed
                    }
                    let encryptedValue = try encryptedGrapheBlob(for: value)
                    let bindStatus = encryptedValue.withUnsafeBytes { bytes in
                        sqlite3_bind_blob(statement, 2, bytes.baseAddress, Int32(bytes.count), SQLITE_TRANSIENT)
                    }
                    guard bindStatus == SQLITE_OK else {
                        throw CatalogHarnessError.statementFailed
                    }
                    guard sqlite3_step(statement) == SQLITE_DONE else {
                        throw CatalogHarnessError.statementFailed
                    }
                }
            } else {
                for (name, value) in infoEntries {
                    let sql = "INSERT INTO info (name, value) VALUES ('\(escapedSQL(name))', '\(escapedSQL(value))');"
                    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
                        throw CatalogHarnessError.statementFailed
                    }
                }
            }
        }

        if let sidecarContents {
            let sidecarURL = moduleInfoURL.appendingPathComponent("\(filenameBaseName(filename)).txt")
            try sidecarContents.write(to: sidecarURL, atomically: true, encoding: .utf8)
        }

        return CatalogModuleHarness(rootURL: rootURL, moduleURL: moduleURL)
    }

    private func filenameBaseName(_ filename: String) -> String {
        var base = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        let typeExtensions = [
            "bibles", "commentaries", "dictionaries", "crossreferences",
            "cross_references", "devotions", "subheadings", "words",
            "reading_plan", "readingplan",
        ]
        for typeExtension in typeExtensions {
            let suffix = "." + typeExtension
            if base.lowercased().hasSuffix(suffix.lowercased()) {
                base = String(base.dropLast(suffix.count))
                break
            }
        }
        return base
    }

    private func escapedSQL(_ text: String) -> String {
        text.replacingOccurrences(of: "'", with: "''")
    }

    private struct CatalogModuleHarness {
        let rootURL: URL
        let moduleURL: URL

        func cleanup() throws {
            try FileManager.default.removeItem(at: rootURL)
        }
    }

    private enum CatalogHarnessError: Error {
        case openFailed
        case statementFailed
    }
}

private func encryptedGrapheBlob(for text: String) throws -> Data {
    let grapheKey: [UInt8] = [
        0x9d, 0xd4, 0x49, 0x2d, 0x38, 0xe1, 0x65, 0xb6,
        0xf6, 0x69, 0x9c, 0x3e, 0x31, 0x5f, 0x2f, 0x65,
        0xf3, 0xff, 0x6c, 0xb4, 0x74, 0xea, 0x6f, 0xcb,
        0x9b, 0x6e, 0x22, 0x22, 0xfc, 0xa4, 0x6b, 0xfe,
    ]
    let plaintext = Data(text.utf8)
    let iv = Data((0..<16).map(UInt8.init))
    let key = Data(grapheKey)
    let bufferSize = plaintext.count + kCCBlockSizeAES128
    var encrypted = Data(count: bufferSize)
    var encryptedLength = 0

    let status = encrypted.withUnsafeMutableBytes { encryptedBytes in
        plaintext.withUnsafeBytes { plaintextBytes in
            key.withUnsafeBytes { keyBytes in
                iv.withUnsafeBytes { ivBytes in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyBytes.baseAddress,
                        kCCKeySizeAES256,
                        ivBytes.baseAddress,
                        plaintextBytes.baseAddress,
                        plaintext.count,
                        encryptedBytes.baseAddress,
                        bufferSize,
                        &encryptedLength
                    )
                }
            }
        }
    }

    guard status == kCCSuccess else {
        struct GrapheEncryptionError: Error {}
        throw GrapheEncryptionError()
    }

    return iv + encrypted.prefix(encryptedLength)
}
#endif
