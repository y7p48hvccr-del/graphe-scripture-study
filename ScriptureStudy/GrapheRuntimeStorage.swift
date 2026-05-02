import Foundation
import SQLite3
import CommonCrypto

enum GrapheRuntimeStorage {
    private static let grapheKey: [UInt8] = [
        0x9d, 0xd4, 0x49, 0x2d, 0x38, 0xe1, 0x65, 0xb6,
        0xf6, 0x69, 0x9c, 0x3e, 0x31, 0x5f, 0x2f, 0x65,
        0xf3, 0xff, 0x6c, 0xb4, 0x74, 0xea, 0x6f, 0xcb,
        0x9b, 0x6e, 0x22, 0x22, 0xfc, 0xa4, 0x6b, 0xfe,
    ]

    static func decrypt(_ blob: UnsafePointer<UInt8>?, _ blobLen: Int32, filePath: String) -> String? {
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

    static func query(db: OpaquePointer?, sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        return stmt
    }

    static func tableNames(db: OpaquePointer?) -> [String] {
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

    static func columnString(_ stmt: OpaquePointer?, _ col: Int32, path: String) -> String? {
        guard let stmt = stmt else { return nil }
        if path.hasSuffix(".graphe") {
            let ptr = sqlite3_column_blob(stmt, col)?.assumingMemoryBound(to: UInt8.self)
            let len = sqlite3_column_bytes(stmt, col)
            return decrypt(ptr, len, filePath: path)
        }
        return sqlite3_column_text(stmt, col).map { String(cString: $0) }
    }
}

func grapheDecrypt(_ blob: UnsafePointer<UInt8>?, _ blobLen: Int32, filePath: String) -> String? {
    GrapheRuntimeStorage.decrypt(blob, blobLen, filePath: filePath)
}
