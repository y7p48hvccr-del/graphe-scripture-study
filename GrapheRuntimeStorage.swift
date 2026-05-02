import Foundation
import SQLite3
import CommonCrypto

enum GrapheRuntimeValidationState: String, Codable, Hashable {
    case ready
    case readableOnly
    case rejected
}

struct GrapheRuntimeValidationReport: Hashable {
    let state: GrapheRuntimeValidationState
    let matchedProfileName: String?
    let rejectionReasons: [String]
    let moduleType: ModuleType
    let hasStrongsCapability: Bool
}

struct GrapheRuntimeSchemaProfile {
    let name: String
    let moduleType: ModuleType
    let matches: (GrapheRuntimeModuleInspection, String) -> Bool
}

struct GrapheRuntimeModuleInspection {
    let info: [String: String]
    let metadataBlob: String
    let tables: Set<String>
    let validationReport: GrapheRuntimeValidationReport
}

protocol GrapheRuntimeProviding {
    func openDatabase(at path: String) -> OpaquePointer?
    func closeDatabase(_ db: OpaquePointer?)
    func decrypt(_ blob: UnsafePointer<UInt8>?, _ blobLen: Int32, filePath: String) -> String?
    func query(db: OpaquePointer?, sql: String) -> OpaquePointer?
    func tableNames(db: OpaquePointer?) -> [String]
    func columnString(_ stmt: OpaquePointer?, _ col: Int32, path: String) -> String?
    func inspectModule(at path: String) -> GrapheRuntimeModuleInspection?
}

protocol GrapheRuntimeModuleInspecting {
    func inspectModule(at path: String) -> GrapheRuntimeModuleInspection?
}

enum GrapheRuntimeStorage {
    private static var provider: GrapheRuntimeProviding = GrapheSQLiteBlobRuntimeProvider()

    static func useRuntimeProvider(_ provider: GrapheRuntimeProviding) {
        self.provider = provider
    }

    static func openDatabase(at path: String) -> OpaquePointer? {
        provider.openDatabase(at: path)
    }

    static func closeDatabase(_ db: OpaquePointer?) {
        provider.closeDatabase(db)
    }

    static func decrypt(_ blob: UnsafePointer<UInt8>?, _ blobLen: Int32, filePath: String) -> String? {
        provider.decrypt(blob, blobLen, filePath: filePath)
    }

    static func query(db: OpaquePointer?, sql: String) -> OpaquePointer? {
        provider.query(db: db, sql: sql)
    }

    static func tableNames(db: OpaquePointer?) -> [String] {
        provider.tableNames(db: db)
    }

    static func columnString(_ stmt: OpaquePointer?, _ col: Int32, path: String) -> String? {
        provider.columnString(stmt, col, path: path)
    }

    static func inspectModule(at path: String) -> GrapheRuntimeModuleInspection? {
        provider.inspectModule(at: path)
    }

    static func withOpenDatabase<T>(at path: String, _ body: (OpaquePointer) -> T) -> T? {
        guard let db = openDatabase(at: path) else { return nil }
        defer { closeDatabase(db) }
        return body(db)
    }
}

struct GrapheSQLiteBlobRuntimeProvider: GrapheRuntimeProviding {
    private let grapheKey: [UInt8] = [
        0x9d, 0xd4, 0x49, 0x2d, 0x38, 0xe1, 0x65, 0xb6,
        0xf6, 0x69, 0x9c, 0x3e, 0x31, 0x5f, 0x2f, 0x65,
        0xf3, 0xff, 0x6c, 0xb4, 0x74, 0xea, 0x6f, 0xcb,
        0x9b, 0x6e, 0x22, 0x22, 0xfc, 0xa4, 0x6b, 0xfe,
    ]

    func openDatabase(at path: String) -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        return db
    }

    func closeDatabase(_ db: OpaquePointer?) {
        sqlite3_close(db)
    }

    func decrypt(_ blob: UnsafePointer<UInt8>?, _ blobLen: Int32, filePath: String) -> String? {
        guard filePath.hasSuffix(".graphe") else {
            guard let ptr = blob else { return nil }
            return String(bytes: UnsafeBufferPointer(start: ptr, count: Int(blobLen)), encoding: .utf8)
        }

        guard let ptr = blob, blobLen > 16 else { return nil }
        let ivData = Data(bytes: ptr, count: 16)
        let ctData = Data(bytes: ptr + 16, count: Int(blobLen) - 16)
        let keyData = Data(grapheKey)

        let bufferSize = ctData.count + kCCBlockSizeAES128
        var decrypted = Data(count: bufferSize)
        var numBytes = 0

        let status = decrypted.withUnsafeMutableBytes { decPtr in
            ctData.withUnsafeBytes { ctPtr in
                ivData.withUnsafeBytes { ivPtr in
                    keyData.withUnsafeBytes { keyPtr in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, kCCKeySizeAES256,
                            ivPtr.baseAddress,
                            ctPtr.baseAddress, ctData.count,
                            decPtr.baseAddress, bufferSize,
                            &numBytes
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else { return nil }
        return String(data: decrypted.prefix(numBytes), encoding: .utf8)
    }

    func query(db: OpaquePointer?, sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        return stmt
    }

    func tableNames(db: OpaquePointer?) -> [String] {
        var tables: [String] = []
        if let stmt = query(db: db, sql: "SELECT name FROM sqlite_master WHERE type='table'") {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let ptr = sqlite3_column_text(stmt, 0) else { continue }
                tables.append(String(cString: ptr))
            }
            sqlite3_finalize(stmt)
        }
        return tables
    }

    func columnString(_ stmt: OpaquePointer?, _ col: Int32, path: String) -> String? {
        guard let stmt = stmt else { return nil }
        if path.hasSuffix(".graphe"), sqlite3_column_type(stmt, col) == SQLITE_BLOB {
            let ptr = sqlite3_column_blob(stmt, col)?.assumingMemoryBound(to: UInt8.self)
            let len = sqlite3_column_bytes(stmt, col)
            if let decrypted = decrypt(ptr, len, filePath: path) {
                return decrypted
            }
        }
        return sqlite3_column_text(stmt, col).map { String(cString: $0) }
    }

    func inspectModule(at path: String) -> GrapheRuntimeModuleInspection? {
        guard let db = openDatabase(at: path) else { return nil }
        defer { closeDatabase(db) }

        var info: [String: String] = [:]
        var blobParts: [String] = []
        if let statement = query(db: db, sql: "SELECT name, value FROM info") {
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let key = columnString(statement, 0, path: path),
                      let value = columnString(statement, 1, path: path)
                else {
                    continue
                }
                info[key] = value
                blobParts.append(value)
            }
            sqlite3_finalize(statement)
        }

        let tables = Set(tableNames(db: db))
        return GrapheRuntimeModuleInspection(
            info: info,
            metadataBlob: blobParts.joined(separator: " "),
            tables: tables,
            validationReport: GrapheRuntimeProfileValidator.validate(
                info: info,
                tables: tables,
                path: path
            )
        )
    }
}

enum GrapheRuntimeProfileValidator {
    private static let profiles: [GrapheRuntimeSchemaProfile] = [
        GrapheRuntimeSchemaProfile(name: "bible-verses", moduleType: .bible) { inspection, _ in
            inspection.tables.contains("verses")
        },
        GrapheRuntimeSchemaProfile(name: "devotional-devotions", moduleType: .devotional) { inspection, _ in
            inspection.tables.contains("devotions")
        },
        GrapheRuntimeSchemaProfile(name: "reading-plan-reading_plan", moduleType: .readingPlan) { inspection, _ in
            inspection.tables.contains("reading_plan")
        },
        GrapheRuntimeSchemaProfile(name: "crossref-cross_references", moduleType: .crossRefNative) { inspection, _ in
            inspection.tables.contains("cross_references")
        },
        GrapheRuntimeSchemaProfile(name: "crossref-commentaries", moduleType: .crossRef) { inspection, path in
            let description = (inspection.info["description"] ?? "").lowercased()
            let isFootnotes = inspection.info["is_footnotes"]?.lowercased() == "true"
            let filename = URL(fileURLWithPath: path).lastPathComponent.lowercased()
            return inspection.tables.contains("commentaries") && (
                isFootnotes ||
                description.contains("treasury") ||
                description.contains("cross ref") ||
                description.contains("cross-ref") ||
                description.contains("tsk") ||
                description.contains("footnote") ||
                description.contains("cross-reference") ||
                filename.contains(".crossreferences.") ||
                filename.contains("-x.")
            )
        },
        GrapheRuntimeSchemaProfile(name: "subheadings-subheadings", moduleType: .subheadings) { inspection, _ in
            inspection.tables.contains("subheadings")
        },
        GrapheRuntimeSchemaProfile(name: "word-index-words", moduleType: .wordIndex) { inspection, _ in
            (inspection.tables.contains("words") || inspection.tables.contains("words_processing")) &&
                !inspection.tables.contains("dictionary") &&
                !inspection.tables.contains("verses")
        },
        GrapheRuntimeSchemaProfile(name: "atlas-info", moduleType: .atlas) { inspection, _ in
            inspection.info["type"]?.lowercased() == "atlas"
        },
        GrapheRuntimeSchemaProfile(name: "commentary-commentaries", moduleType: .commentary) { inspection, _ in
            inspection.tables.contains("commentaries")
        },
        GrapheRuntimeSchemaProfile(name: "commentary-commentary", moduleType: .commentary) { inspection, _ in
            inspection.tables.contains("commentary")
        },
        GrapheRuntimeSchemaProfile(name: "strongs-dictionary", moduleType: .strongs) { inspection, _ in
            inspection.tables.contains("dictionary") &&
                inspection.info["is_strong"]?.lowercased() == "true"
        },
        GrapheRuntimeSchemaProfile(name: "encyclopedia-dictionary", moduleType: .encyclopedia) { inspection, path in
            guard inspection.tables.contains("dictionary") else { return false }
            let description = (inspection.info["description"] ?? "").lowercased()
            let filename = URL(fileURLWithPath: path).lastPathComponent.lowercased()
            let encyclopediaKeywords = [
                "encyclop", "handbook", "companion to the bible", "isbe",
                "easton", "hastings", "smith's bible", "unger", "zondervan",
                "naves", "nave's",
            ]
            return encyclopediaKeywords.contains {
                description.contains($0) || filename.contains($0)
            }
        },
        GrapheRuntimeSchemaProfile(name: "reference-dictionary", moduleType: .dictionary) { inspection, _ in
            inspection.tables.contains("dictionary")
        },
    ]

    static func validate(
        info: [String: String],
        tables: Set<String>,
        path: String
    ) -> GrapheRuntimeValidationReport {
        let inspection = GrapheRuntimeModuleInspection(
            info: info,
            metadataBlob: "",
            tables: tables,
            validationReport: GrapheRuntimeValidationReport(
                state: .rejected,
                matchedProfileName: nil,
                rejectionReasons: [],
                moduleType: .unknown,
                hasStrongsCapability: false
            )
        )
        if let profile = profiles.first(where: { $0.matches(inspection, path) }) {
            let hasStrongs = info["strong_numbers"]?.lowercased() == "true" || profile.moduleType == .strongs
            return GrapheRuntimeValidationReport(
                state: .ready,
                matchedProfileName: profile.name,
                rejectionReasons: [],
                moduleType: profile.moduleType,
                hasStrongsCapability: hasStrongs
            )
        }
        if tables.isEmpty {
            return GrapheRuntimeValidationReport(
                state: .rejected,
                matchedProfileName: nil,
                rejectionReasons: ["No readable runtime tables were found."],
                moduleType: .unknown,
                hasStrongsCapability: false
            )
        }
        return GrapheRuntimeValidationReport(
            state: .readableOnly,
            matchedProfileName: nil,
            rejectionReasons: ["Module tables do not match a registered runtime profile."],
            moduleType: .unknown,
            hasStrongsCapability: info["strong_numbers"]?.lowercased() == "true"
        )
    }
}

struct GrapheRuntimeModuleAccessor: GrapheRuntimeModuleInspecting {
    private let provider: GrapheRuntimeProviding

    init(provider: GrapheRuntimeProviding = GrapheSQLiteBlobRuntimeProvider()) {
        self.provider = provider
    }

    func inspectModule(at path: String) -> GrapheRuntimeModuleInspection? {
        provider.inspectModule(at: path)
    }
}

func grapheDecrypt(_ blob: UnsafePointer<UInt8>?, _ blobLen: Int32, filePath: String) -> String? {
    GrapheRuntimeStorage.decrypt(blob, blobLen, filePath: filePath)
}
