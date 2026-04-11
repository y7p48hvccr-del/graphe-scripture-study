import Foundation

// MARK: - Bible Book

struct BibleBook: Identifiable, Hashable {
    let id        = UUID()
    let name:      String
    let chapters:  Int
    let apiName:   String   // URL-safe name for bible-api.com

    static func == (lhs: BibleBook, rhs: BibleBook) -> Bool { lhs.name == rhs.name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

// MARK: - All 66 Books

let bibleBooks: [BibleBook] = [
    // Old Testament
    BibleBook(name: "Genesis",          chapters: 50,  apiName: "genesis"),
    BibleBook(name: "Exodus",           chapters: 40,  apiName: "exodus"),
    BibleBook(name: "Leviticus",        chapters: 27,  apiName: "leviticus"),
    BibleBook(name: "Numbers",          chapters: 36,  apiName: "numbers"),
    BibleBook(name: "Deuteronomy",      chapters: 34,  apiName: "deuteronomy"),
    BibleBook(name: "Joshua",           chapters: 24,  apiName: "joshua"),
    BibleBook(name: "Judges",           chapters: 21,  apiName: "judges"),
    BibleBook(name: "Ruth",             chapters:  4,  apiName: "ruth"),
    BibleBook(name: "1 Samuel",         chapters: 31,  apiName: "1%20samuel"),
    BibleBook(name: "2 Samuel",         chapters: 24,  apiName: "2%20samuel"),
    BibleBook(name: "1 Kings",          chapters: 22,  apiName: "1%20kings"),
    BibleBook(name: "2 Kings",          chapters: 25,  apiName: "2%20kings"),
    BibleBook(name: "1 Chronicles",     chapters: 29,  apiName: "1%20chronicles"),
    BibleBook(name: "2 Chronicles",     chapters: 36,  apiName: "2%20chronicles"),
    BibleBook(name: "Ezra",             chapters: 10,  apiName: "ezra"),
    BibleBook(name: "Nehemiah",         chapters: 13,  apiName: "nehemiah"),
    BibleBook(name: "Esther",           chapters: 10,  apiName: "esther"),
    BibleBook(name: "Job",              chapters: 42,  apiName: "job"),
    BibleBook(name: "Psalms",           chapters: 150, apiName: "psalms"),
    BibleBook(name: "Proverbs",         chapters: 31,  apiName: "proverbs"),
    BibleBook(name: "Ecclesiastes",     chapters: 12,  apiName: "ecclesiastes"),
    BibleBook(name: "Song of Solomon",  chapters:  8,  apiName: "song%20of%20solomon"),
    BibleBook(name: "Isaiah",           chapters: 66,  apiName: "isaiah"),
    BibleBook(name: "Jeremiah",         chapters: 52,  apiName: "jeremiah"),
    BibleBook(name: "Lamentations",     chapters:  5,  apiName: "lamentations"),
    BibleBook(name: "Ezekiel",          chapters: 48,  apiName: "ezekiel"),
    BibleBook(name: "Daniel",           chapters: 12,  apiName: "daniel"),
    BibleBook(name: "Hosea",            chapters: 14,  apiName: "hosea"),
    BibleBook(name: "Joel",             chapters:  3,  apiName: "joel"),
    BibleBook(name: "Amos",             chapters:  9,  apiName: "amos"),
    BibleBook(name: "Obadiah",          chapters:  1,  apiName: "obadiah"),
    BibleBook(name: "Jonah",            chapters:  4,  apiName: "jonah"),
    BibleBook(name: "Micah",            chapters:  7,  apiName: "micah"),
    BibleBook(name: "Nahum",            chapters:  3,  apiName: "nahum"),
    BibleBook(name: "Habakkuk",         chapters:  3,  apiName: "habakkuk"),
    BibleBook(name: "Zephaniah",        chapters:  3,  apiName: "zephaniah"),
    BibleBook(name: "Haggai",           chapters:  2,  apiName: "haggai"),
    BibleBook(name: "Zechariah",        chapters: 14,  apiName: "zechariah"),
    BibleBook(name: "Malachi",          chapters:  4,  apiName: "malachi"),
    // New Testament
    BibleBook(name: "Matthew",          chapters: 28,  apiName: "matthew"),
    BibleBook(name: "Mark",             chapters: 16,  apiName: "mark"),
    BibleBook(name: "Luke",             chapters: 24,  apiName: "luke"),
    BibleBook(name: "John",             chapters: 21,  apiName: "john"),
    BibleBook(name: "Acts",             chapters: 28,  apiName: "acts"),
    BibleBook(name: "Romans",           chapters: 16,  apiName: "romans"),
    BibleBook(name: "1 Corinthians",    chapters: 16,  apiName: "1%20corinthians"),
    BibleBook(name: "2 Corinthians",    chapters: 13,  apiName: "2%20corinthians"),
    BibleBook(name: "Galatians",        chapters:  6,  apiName: "galatians"),
    BibleBook(name: "Ephesians",        chapters:  6,  apiName: "ephesians"),
    BibleBook(name: "Philippians",      chapters:  4,  apiName: "philippians"),
    BibleBook(name: "Colossians",       chapters:  4,  apiName: "colossians"),
    BibleBook(name: "1 Thessalonians",  chapters:  5,  apiName: "1%20thessalonians"),
    BibleBook(name: "2 Thessalonians",  chapters:  3,  apiName: "2%20thessalonians"),
    BibleBook(name: "1 Timothy",        chapters:  6,  apiName: "1%20timothy"),
    BibleBook(name: "2 Timothy",        chapters:  4,  apiName: "2%20timothy"),
    BibleBook(name: "Titus",            chapters:  3,  apiName: "titus"),
    BibleBook(name: "Philemon",         chapters:  1,  apiName: "philemon"),
    BibleBook(name: "Hebrews",          chapters: 13,  apiName: "hebrews"),
    BibleBook(name: "James",            chapters:  5,  apiName: "james"),
    BibleBook(name: "1 Peter",          chapters:  5,  apiName: "1%20peter"),
    BibleBook(name: "2 Peter",          chapters:  3,  apiName: "2%20peter"),
    BibleBook(name: "1 John",           chapters:  5,  apiName: "1%20john"),
    BibleBook(name: "2 John",           chapters:  1,  apiName: "2%20john"),
    BibleBook(name: "3 John",           chapters:  1,  apiName: "3%20john"),
    BibleBook(name: "Jude",             chapters:  1,  apiName: "jude"),
    BibleBook(name: "Revelation",       chapters: 22,  apiName: "revelation"),
]

// MARK: - Daily Verses

struct DailyVerse {
    let text:      String
    let reference: String
}

let dailyVerses: [DailyVerse] = [
    DailyVerse(text: "For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life.",
               reference: "John 3:16"),
    DailyVerse(text: "I can do all this through him who gives me strength.",
               reference: "Philippians 4:13"),
    DailyVerse(text: "The Lord is my shepherd; I shall not want.",
               reference: "Psalm 23:1"),
    DailyVerse(text: "Trust in the Lord with all your heart and lean not on your own understanding; in all your ways submit to him, and he will make your paths straight.",
               reference: "Proverbs 3:5–6"),
    DailyVerse(text: "And we know that in all things God works for the good of those who love him, who have been called according to his purpose.",
               reference: "Romans 8:28"),
    DailyVerse(text: "Be strong and courageous. Do not be afraid; do not be discouraged, for the Lord your God will be with you wherever you go.",
               reference: "Joshua 1:9"),
    DailyVerse(text: "But those who hope in the Lord will renew their strength. They will soar on wings like eagles; they will run and not grow weary, they will walk and not be faint.",
               reference: "Isaiah 40:31"),
    DailyVerse(text: "The Lord bless you and keep you; the Lord make his face shine on you and be gracious to you.",
               reference: "Numbers 6:24–25"),
    DailyVerse(text: "Do not be anxious about anything, but in every situation, by prayer and petition, with thanksgiving, present your requests to God.",
               reference: "Philippians 4:6"),
    DailyVerse(text: "For I know the plans I have for you, declares the Lord, plans to prosper you and not to harm you, plans to give you hope and a future.",
               reference: "Jeremiah 29:11"),
]

var todayVerse: DailyVerse {
    let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
    return dailyVerses[day % dailyVerses.count]
}
