#if os(macOS)
import Foundation
import SQLite3
import Testing
@testable import ScriptureStudy

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
#endif
