import Foundation

enum ModuleUsageStore {
    private static let scoresKey = "moduleUsageScoresByPath"

    static func recordUse(of module: MyBibleModule?) {
        guard let module else { return }
        var scores = usageScoresByPath()
        scores[module.filePath, default: 0] += 1
        if scores.count > 200 {
            scores = Dictionary(
                scores
                    .sorted { lhs, rhs in
                        if lhs.value != rhs.value { return lhs.value > rhs.value }
                        return lhs.key < rhs.key
                    }
                    .prefix(200),
                uniquingKeysWith: { first, _ in first }
            )
        }
        UserDefaults.standard.set(scores, forKey: scoresKey)
    }

    static func usageScoresByPath() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: scoresKey) as? [String: Int] ?? [:]
    }
}
