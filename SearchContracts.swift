import Foundation

enum SearchScope: String, CaseIterable {
    case bible = "Bibles"
    case interlinear = "Interlinear"
    case strongs = "Strongs"
    case commentary = "Commentaries"
    case crossReferences = "Cross-references"
    case encyclopedias = "Encyclopedias"
    case lexicons = "Lexicons"
    case dictionaries = "Dictionaries"
    case notes = "Notes"
}

enum SearchMode: String, CaseIterable {
    case global
    case bibleFirst
    case referenceFirst
    case commentaryFirst
}

enum SearchQueryKind: String, CaseIterable {
    case word = "Word"
    case phrase = "Phrase"
    case strongs = "Strong's"
}

enum Testament {
    case ot
    case nt
    case both
}

struct SearchModuleInfo: Hashable {
    let path: String
    let name: String
    let type: ModuleType
}

struct SearchRequest {
    let query: String
    let queryKind: SearchQueryKind
    let scope: SearchScope
    let mode: SearchMode
    let testament: Testament
    let bookFilter: Int
    let exact: Bool
    let includeInflections: Bool
    let notesFrom: Date?
    let notesTo: Date?
    let selectedBiblePaths: Set<String>
    let selectedInterlinearPaths: Set<String>
    let selectedStrongsPaths: Set<String>
    let selectedCommentaryPaths: Set<String>
    let selectedCrossReferencePaths: Set<String>
    let selectedEncyclopediaPaths: Set<String>
    let selectedLexiconPaths: Set<String>
    let selectedDictionaryPaths: Set<String>
}

struct SearchExecutionContext {
    let visibleModules: [MyBibleModule]
    let catalogRecordsByPath: [String: ModuleCatalogRecord]
    let selectedBible: MyBibleModule?
    let selectedStrongs: MyBibleModule?
    let selectedCommentary: MyBibleModule?
    let selectedDictionary: MyBibleModule?
    let selectedEncyclopedia: MyBibleModule?
    let selectedCrossReference: MyBibleModule?
    let moduleUsageScoresByPath: [String: Int]
    let notes: [Note]
}

enum ModuleUsageStore {
    private static let scoresKey = "moduleUsageScoresByPath"

    static func recordUse(of module: MyBibleModule?) {
        guard let module else { return }
        var scores = usageScoresByPath()
        scores[module.filePath, default: 0] += 1
        if scores.count > 200 {
            let trimmed = scores
                .sorted { lhs, rhs in
                    if lhs.value != rhs.value { return lhs.value > rhs.value }
                    return lhs.key < rhs.key
                }
                .prefix(200)
                .map { ($0.key, $0.value) }
            scores = Dictionary(
                trimmed,
                uniquingKeysWith: { first, _ in first }
            )
        }
        UserDefaults.standard.set(scores, forKey: scoresKey)
    }

    static func usageScoresByPath() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: scoresKey) as? [String: Int] ?? [:]
    }
}
