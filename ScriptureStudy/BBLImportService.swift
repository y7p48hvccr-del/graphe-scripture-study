import Foundation
import SQLite3
import CommonCrypto
import Security

enum BBLImportError: LocalizedError {
    case securityScopeDenied(String)
    case unreadableSource
    case openDestinationFailed
    case unsupportedSchema
    case statementFailed(String)
    case encryptionFailed(Int)
    case randomIVFailed

    var errorDescription: String? {
        switch self {
        case .securityScopeDenied(let path):
            "Could not access \(URL(fileURLWithPath: path).lastPathComponent)."
        case .unreadableSource:
            "The .bbl file could not be read."
        case .openDestinationFailed:
            "The destination .graphe file could not be created."
        case .unsupportedSchema:
            "This .bbl schema is not recognized yet."
        case .statementFailed(let detail):
            detail
        case .encryptionFailed:
            "Graphē encryption failed."
        case .randomIVFailed:
            "Could not generate encryption IV."
        }
    }
}

enum BBLImportService {
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private static let grapheKey: [UInt8] = [
        0x9d, 0xd4, 0x49, 0x2d, 0x38, 0xe1, 0x65, 0xb6,
        0xf6, 0x69, 0x9c, 0x3e, 0x31, 0x5f, 0x2f, 0x65,
        0xf3, 0xff, 0x6c, 0xb4, 0x74, 0xea, 0x6f, 0xcb,
        0x9b, 0x6e, 0x22, 0x22, 0xfc, 0xa4, 0x6b, 0xfe,
    ]

    static func importBible(from sourceURL: URL, into modulesFolderURL: URL) throws -> URL {
        guard sourceURL.startAccessingSecurityScopedResource() else {
            throw BBLImportError.securityScopeDenied(sourceURL.path)
        }
        defer { sourceURL.stopAccessingSecurityScopedResource() }

        guard modulesFolderURL.startAccessingSecurityScopedResource() else {
            throw BBLImportError.securityScopeDenied(modulesFolderURL.path)
        }
        defer { modulesFolderURL.stopAccessingSecurityScopedResource() }

        let destinationURL = modulesFolderURL.appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent + ".graphe")
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        var sourceDB: OpaquePointer?
        guard sqlite3_open_v2(sourceURL.path, &sourceDB, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let sourceDB
        else {
            sqlite3_close(sourceDB)
            throw BBLImportError.unreadableSource
        }
        defer { sqlite3_close(sourceDB) }

        var destinationDB: OpaquePointer?
        guard sqlite3_open(destinationURL.path, &destinationDB) == SQLITE_OK,
              let destinationDB
        else {
            sqlite3_close(destinationDB)
            throw BBLImportError.openDestinationFailed
        }
        defer { sqlite3_close(destinationDB) }

        let bibleTable = try findTable(named: "bible", in: sourceDB)
        let detailsTable = findOptionalTable(named: "details", in: sourceDB)
        let bibleColumns = try tableColumns(for: bibleTable, in: sourceDB)

        guard let bookColumn = firstPresentColumn(in: bibleColumns, candidates: ["book", "booknumber", "book_number"]),
              let chapterColumn = firstPresentColumn(in: bibleColumns, candidates: ["chapter", "chapter_number"]),
              let verseColumn = firstPresentColumn(in: bibleColumns, candidates: ["verse", "verse_number"]),
              let textColumn = firstPresentColumn(in: bibleColumns, candidates: ["scripture", "text", "versetext", "content"])
        else {
            throw BBLImportError.unsupportedSchema
        }

        try execute(
            """
            CREATE TABLE verses (
                book_number INTEGER NOT NULL,
                chapter INTEGER NOT NULL,
                verse INTEGER NOT NULL,
                text BLOB,
                PRIMARY KEY (book_number, chapter, verse)
            );
            """,
            in: destinationDB
        )
        try execute(
            """
            CREATE TABLE info (
                name TEXT PRIMARY KEY,
                value BLOB
            );
            """,
            in: destinationDB
        )

        let metadata = try readDetails(from: detailsTable, in: sourceDB)
        try copyBibleRows(
            from: sourceDB,
            bibleTable: bibleTable,
            bookColumn: bookColumn,
            chapterColumn: chapterColumn,
            verseColumn: verseColumn,
            textColumn: textColumn,
            into: destinationDB
        )
        try writeInfo(metadata: metadata, fallbackName: sourceURL.deletingPathExtension().lastPathComponent, into: destinationDB)

        return destinationURL
    }

    private static func copyBibleRows(
        from sourceDB: OpaquePointer,
        bibleTable: String,
        bookColumn: String,
        chapterColumn: String,
        verseColumn: String,
        textColumn: String,
        into destinationDB: OpaquePointer
    ) throws {
        let selectSQL =
        """
        SELECT "\(bookColumn)", "\(chapterColumn)", "\(verseColumn)", "\(textColumn)"
        FROM "\(bibleTable)"
        ORDER BY "\(bookColumn)", "\(chapterColumn)", "\(verseColumn)"
        """

        var sourceStatement: OpaquePointer?
        guard sqlite3_prepare_v2(sourceDB, selectSQL, -1, &sourceStatement, nil) == SQLITE_OK,
              let sourceStatement
        else {
            throw BBLImportError.statementFailed("Could not read Bible rows.")
        }
        defer { sqlite3_finalize(sourceStatement) }

        var insertStatement: OpaquePointer?
        guard sqlite3_prepare_v2(
            destinationDB,
            "INSERT INTO verses (book_number, chapter, verse, text) VALUES (?, ?, ?, ?)",
            -1,
            &insertStatement,
            nil
        ) == SQLITE_OK, let insertStatement else {
            throw BBLImportError.statementFailed("Could not prepare verse insert.")
        }
        defer { sqlite3_finalize(insertStatement) }

        while sqlite3_step(sourceStatement) == SQLITE_ROW {
            sqlite3_reset(insertStatement)
            sqlite3_clear_bindings(insertStatement)

            sqlite3_bind_int(insertStatement, 1, sqlite3_column_int(sourceStatement, 0))
            sqlite3_bind_int(insertStatement, 2, sqlite3_column_int(sourceStatement, 1))
            sqlite3_bind_int(insertStatement, 3, sqlite3_column_int(sourceStatement, 2))

            let verseText = sqlite3_column_text(sourceStatement, 3).map { String(cString: $0) } ?? ""
            let encryptedValue = try encryptedGrapheBlob(for: verseText)
            let bindStatus = encryptedValue.withUnsafeBytes { bytes in
                sqlite3_bind_blob(insertStatement, 4, bytes.baseAddress, Int32(bytes.count), sqliteTransient)
            }
            guard bindStatus == SQLITE_OK, sqlite3_step(insertStatement) == SQLITE_DONE else {
                throw BBLImportError.statementFailed("Could not write verse rows.")
            }
        }
    }

    private static func writeInfo(
        metadata: [String: String],
        fallbackName: String,
        into destinationDB: OpaquePointer
    ) throws {
        var insertStatement: OpaquePointer?
        guard sqlite3_prepare_v2(
            destinationDB,
            "INSERT OR REPLACE INTO info (name, value) VALUES (?, ?)",
            -1,
            &insertStatement,
            nil
        ) == SQLITE_OK, let insertStatement else {
            throw BBLImportError.statementFailed("Could not prepare info insert.")
        }
        defer { sqlite3_finalize(insertStatement) }

        var entries = metadata
        let description = entries["description"] ?? entries["name"] ?? fallbackName
        entries["description"] = description
        entries["identifier"] = entries["identifier"] ?? fallbackName
        entries["language"] = normalizedLanguage(from: entries["language"]) ?? "en"
        entries["version"] = entries["version"] ?? "1"
        entries["source"] = entries["source"] ?? "e-Sword .bbl"

        for (name, value) in entries.sorted(by: { $0.key < $1.key }) {
            sqlite3_reset(insertStatement)
            sqlite3_clear_bindings(insertStatement)

            guard sqlite3_bind_text(insertStatement, 1, (name as NSString).utf8String, -1, sqliteTransient) == SQLITE_OK else {
                throw BBLImportError.statementFailed("Could not bind info key.")
            }
            let encryptedValue = try encryptedGrapheBlob(for: value)
            let bindStatus = encryptedValue.withUnsafeBytes { bytes in
                sqlite3_bind_blob(insertStatement, 2, bytes.baseAddress, Int32(bytes.count), sqliteTransient)
            }
            guard bindStatus == SQLITE_OK, sqlite3_step(insertStatement) == SQLITE_DONE else {
                throw BBLImportError.statementFailed("Could not write info rows.")
            }
        }
    }

    private static func readDetails(from tableName: String?, in sourceDB: OpaquePointer) throws -> [String: String] {
        guard let tableName else { return [:] }
        let columns = try tableColumns(for: tableName, in: sourceDB)
        guard let keyColumn = firstPresentColumn(in: columns, candidates: ["field", "name", "key"]),
              let valueColumn = firstPresentColumn(in: columns, candidates: ["value", "content", "data"])
        else {
            return [:]
        }

        let sql = "SELECT \"\(keyColumn)\", \"\(valueColumn)\" FROM \"\(tableName)\""
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(sourceDB, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw BBLImportError.statementFailed("Could not read details table.")
        }
        defer { sqlite3_finalize(statement) }

        var metadata: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawKey = sqlite3_column_text(statement, 0),
                  let rawValue = sqlite3_column_text(statement, 1)
            else {
                continue
            }
            let key = normalizedMetadataKey(String(cString: rawKey))
            let value = String(cString: rawValue).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            metadata[key] = value
        }
        return metadata
    }

    private static func normalizedMetadataKey(_ key: String) -> String {
        switch key.lowercased().replacingOccurrences(of: " ", with: "") {
        case "description", "title":
            "description"
        case "abbreviation", "shortname":
            "name"
        case "identifier", "moduleidentifier":
            "identifier"
        case "language", "lang":
            "language"
        case "version":
            "version"
        case "source", "publisher":
            "source"
        default:
            key.lowercased()
        }
    }

    private static func normalizedLanguage(from value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed == "english" { return "en" }
        if trimmed.count == 2 || trimmed.count == 3 { return trimmed }
        return nil
    }

    private static func findTable(named desiredName: String, in db: OpaquePointer) throws -> String {
        if let table = findOptionalTable(named: desiredName, in: db) {
            return table
        }
        throw BBLImportError.unsupportedSchema
    }

    private static func findOptionalTable(named desiredName: String, in db: OpaquePointer) -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='table'", -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawName = sqlite3_column_text(statement, 0) else { continue }
            let tableName = String(cString: rawName)
            if tableName.lowercased() == desiredName.lowercased() {
                return tableName
            }
        }
        return nil
    }

    private static func tableColumns(for tableName: String, in db: OpaquePointer) throws -> [String: String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\"\(tableName)\")", -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw BBLImportError.statementFailed("Could not inspect \(tableName) columns.")
        }
        defer { sqlite3_finalize(statement) }

        var result: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawName = sqlite3_column_text(statement, 1) else { continue }
            let columnName = String(cString: rawName)
            result[columnName.lowercased()] = columnName
        }
        return result
    }

    private static func firstPresentColumn(in columns: [String: String], candidates: [String]) -> String? {
        for candidate in candidates {
            if let match = columns[candidate] {
                return match
            }
        }
        return nil
    }

    private static func execute(_ sql: String, in db: OpaquePointer) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            let message = sqlite3_errmsg(db).map { String(cString: $0) } ?? "SQLite error"
            throw BBLImportError.statementFailed(message)
        }
    }

    private static func encryptedGrapheBlob(for text: String) throws -> Data {
        let plaintext = Data(text.utf8)
        var ivBytes = [UInt8](repeating: 0, count: kCCBlockSizeAES128)
        guard SecRandomCopyBytes(kSecRandomDefault, ivBytes.count, &ivBytes) == errSecSuccess else {
            throw BBLImportError.randomIVFailed
        }

        let iv = Data(ivBytes)
        let key = Data(grapheKey)
        let bufferSize = plaintext.count + kCCBlockSizeAES128
        var encrypted = Data(count: bufferSize)
        var numBytesEncrypted = 0

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
                            &numBytesEncrypted
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw BBLImportError.encryptionFailed(Int(status))
        }

        return iv + encrypted.prefix(numBytesEncrypted)
    }
}
