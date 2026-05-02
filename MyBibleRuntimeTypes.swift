import Foundation

enum ScriptureBookCatalog {
    static let namesByNumber: [Int: String] = [
        10:"Genesis", 20:"Exodus", 30:"Leviticus", 40:"Numbers", 50:"Deuteronomy",
        60:"Joshua", 70:"Judges", 80:"Ruth", 90:"1 Samuel", 100:"2 Samuel",
        110:"1 Kings", 120:"2 Kings", 130:"1 Chronicles", 140:"2 Chronicles",
        150:"Ezra", 160:"Nehemiah", 190:"Esther", 220:"Job", 230:"Psalms",
        240:"Proverbs", 250:"Ecclesiastes", 260:"Song of Solomon", 290:"Isaiah",
        300:"Jeremiah", 310:"Lamentations", 330:"Ezekiel", 340:"Daniel",
        350:"Hosea", 360:"Joel", 370:"Amos", 380:"Obadiah", 390:"Jonah",
        400:"Micah", 410:"Nahum", 420:"Habakkuk", 430:"Zephaniah", 440:"Haggai",
        450:"Zechariah", 460:"Malachi",
        470:"Matthew", 480:"Mark", 490:"Luke", 500:"John", 510:"Acts",
        520:"Romans", 530:"1 Corinthians", 540:"2 Corinthians", 550:"Galatians",
        560:"Ephesians", 570:"Philippians", 580:"Colossians",
        590:"1 Thessalonians", 600:"2 Thessalonians",
        610:"1 Timothy", 620:"2 Timothy", 630:"Titus", 640:"Philemon",
        650:"Hebrews", 660:"James", 670:"1 Peter", 680:"2 Peter",
        690:"1 John", 700:"2 John", 710:"3 John", 720:"Jude", 730:"Revelation",
    ]

    static let order: [Int] = namesByNumber.keys.sorted()

    private static let osisCodesByNumber: [Int: String] = [
        10:"GEN", 20:"EXO", 30:"LEV", 40:"NUM", 50:"DEU",
        60:"JOS", 70:"JDG", 80:"RUT", 90:"1SA", 100:"2SA",
        110:"1KI", 120:"2KI", 130:"1CH", 140:"2CH", 150:"EZR",
        160:"NEH", 170:"EST", 180:"JOB", 190:"PSA", 220:"PRO",
        230:"ECC", 240:"SNG", 250:"ISA", 260:"JER", 270:"LAM",
        280:"EZK", 290:"DAN", 300:"HOS", 310:"JOL", 320:"AMO",
        330:"OBA", 340:"JON", 350:"MIC", 360:"NAH", 370:"HAB",
        380:"ZEP", 390:"HAG", 400:"ZEC", 410:"MAL",
        470:"MAT", 480:"MRK", 490:"LUK", 500:"JHN", 510:"ACT",
        520:"ROM", 530:"1CO", 540:"2CO", 550:"GAL", 560:"EPH",
        570:"PHP", 580:"COL", 590:"1TH", 600:"2TH", 610:"1TI",
        620:"2TI", 630:"TIT", 640:"PHM", 650:"HEB", 660:"JAS",
        670:"1PE", 680:"2PE", 690:"1JN", 700:"2JN", 710:"3JN",
        720:"JUD", 730:"REV",
    ]

    static func osisCode(for bookNumber: Int) -> String {
        osisCodesByNumber[bookNumber] ?? ""
    }

    static func bookNumber(forName name: String) -> Int? {
        let normalized = normalizeBookName(name)
        if let exact = namesByNumber.first(where: { normalizeBookName($0.value) == normalized })?.key {
            return exact
        }

        let tokenWords = normalized.split(separator: " ")
        guard !tokenWords.isEmpty else { return nil }

        let matches = namesByNumber.compactMap { entry -> Int? in
            let candidateWords = normalizeBookName(entry.value).split(separator: " ")
            guard candidateWords.count >= tokenWords.count else { return nil }
            for (index, tokenWord) in tokenWords.enumerated() {
                if !candidateWords[index].hasPrefix(tokenWord) {
                    return nil
                }
            }
            return entry.key
        }

        return matches.count == 1 ? matches[0] : nil
    }

    private static func normalizeBookName(_ name: String) -> String {
        name
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

let myBibleBookNumbers: [Int: String] = ScriptureBookCatalog.namesByNumber
let myBibleBookOrder: [Int] = ScriptureBookCatalog.order

struct BiblePassageState {
    let title: String
    let bookNumber: Int
    let chapter: Int

    var userInfo: [String: Any] {
        [
            "bookNumber": bookNumber,
            "chapter": chapter
        ]
    }

    var verseReference: String {
        title
    }
}

enum PassageNavigationResolver {
    static func makePassageState(
        bookNumber: Int,
        chapter: Int,
        fallbackTitle: String
    ) -> BiblePassageState {
        let bookName = myBibleBookNumbers[bookNumber] ?? fallbackTitle
        return BiblePassageState(
            title: "\(bookName) \(chapter)",
            bookNumber: bookNumber,
            chapter: chapter
        )
    }

    static func resolveRequest(from reference: String) -> PassageNavigationRequest? {
        let trimmedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        let split = trimmedReference.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        let chapterPart = String(split.first ?? "")
        let verse = split.count > 1 ? Int(split[1].split(separator: ",").first ?? "") : nil

        let parts = chapterPart.components(separatedBy: " ")
        guard let chapterString = parts.last,
              let chapter = Int(chapterString) else {
            return nil
        }

        let bookName = parts.dropLast().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bookNumber = ScriptureBookCatalog.bookNumber(forName: bookName) else {
            return nil
        }

        return PassageNavigationRequest(
            bookNumber: bookNumber,
            chapter: chapter,
            verse: verse
        )
    }
}

enum ModuleLookupResolver {
    static func resolveLookupModules(
        preferredModule: MyBibleModule?,
        fallbackType: ModuleType?,
        visibleModules: [MyBibleModule]
    ) -> [MyBibleModule] {
        if let preferredModule {
            return [preferredModule]
        }
        guard let fallbackType else {
            return []
        }
        return visibleModules.filter { $0.type == fallbackType }
    }
}

struct CrossRefGroup {
    let keyword: String?
    let references: [CrossRefEntry]
}

extension Notification.Name {
    static let biblePassageChanged = Notification.Name("biblePassageChanged")
}

struct CrossRefEntry {
    let display: String
    let bookNumber: Int
    let chapter: Int
    let verseStart: Int
    let verseEnd: Int
}

struct DevotionalEntry {
    let day: Int
    let title: String
    let html: String
}

struct PlanEntry {
    let bookNumber: Int
    let startChapter: Int
    let startVerse: Int?
    let endChapter: Int?
    let endVerse: Int?
    let displayText: String
}
