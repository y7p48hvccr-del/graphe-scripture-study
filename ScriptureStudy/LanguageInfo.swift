import SwiftUI

// MARK: - Language Info
// Maps ISO 639-1 language codes to a flag emoji and display name.
// Where a language spans many countries the primary / most common country is used.

struct LanguageInfo {
    let code:        String   // ISO 639-1 e.g. "en"
    let flag:        String   // emoji flag e.g. "🇬🇧"
    let displayName: String   // e.g. "English"

    // Convenience: flag + name e.g. "🇬🇧 English"
    var label: String { "\(flag) \(displayName)" }
}

// MARK: - Lookup

extension LanguageInfo {

    static func from(code: String) -> LanguageInfo {
        let lower = code.lowercased().trimmingCharacters(in: .whitespaces)
        return table[lower] ?? LanguageInfo(code: lower, flag: "🌐", displayName: lower.isEmpty ? "Unknown" : lower.uppercased())
    }

    // MARK: - Table

    private static let table: [String: LanguageInfo] = [

        // ── Major world languages ──────────────────────────────────────────
        "en":  LanguageInfo(code: "en",  flag: "🇬🇧", displayName: "English"),
        "fr":  LanguageInfo(code: "fr",  flag: "🇫🇷", displayName: "French"),
        "de":  LanguageInfo(code: "de",  flag: "🇩🇪", displayName: "German"),
        "es":  LanguageInfo(code: "es",  flag: "🇪🇸", displayName: "Spanish"),
        "pt":  LanguageInfo(code: "pt",  flag: "🇵🇹", displayName: "Portuguese"),
        "it":  LanguageInfo(code: "it",  flag: "🇮🇹", displayName: "Italian"),
        "ru":  LanguageInfo(code: "ru",  flag: "🇷🇺", displayName: "Russian"),
        "nl":  LanguageInfo(code: "nl",  flag: "🇳🇱", displayName: "Dutch"),
        "pl":  LanguageInfo(code: "pl",  flag: "🇵🇱", displayName: "Polish"),
        "ro":  LanguageInfo(code: "ro",  flag: "🇷🇴", displayName: "Romanian"),
        "cs":  LanguageInfo(code: "cs",  flag: "🇨🇿", displayName: "Czech"),
        "sk":  LanguageInfo(code: "sk",  flag: "🇸🇰", displayName: "Slovak"),
        "hu":  LanguageInfo(code: "hu",  flag: "🇭🇺", displayName: "Hungarian"),
        "sv":  LanguageInfo(code: "sv",  flag: "🇸🇪", displayName: "Swedish"),
        "da":  LanguageInfo(code: "da",  flag: "🇩🇰", displayName: "Danish"),
        "no":  LanguageInfo(code: "no",  flag: "🇳🇴", displayName: "Norwegian"),
        "nb":  LanguageInfo(code: "nb",  flag: "🇳🇴", displayName: "Norwegian Bokmål"),
        "nn":  LanguageInfo(code: "nn",  flag: "🇳🇴", displayName: "Norwegian Nynorsk"),
        "fi":  LanguageInfo(code: "fi",  flag: "🇫🇮", displayName: "Finnish"),
        "et":  LanguageInfo(code: "et",  flag: "🇪🇪", displayName: "Estonian"),
        "lv":  LanguageInfo(code: "lv",  flag: "🇱🇻", displayName: "Latvian"),
        "lt":  LanguageInfo(code: "lt",  flag: "🇱🇹", displayName: "Lithuanian"),
        "bg":  LanguageInfo(code: "bg",  flag: "🇧🇬", displayName: "Bulgarian"),
        "hr":  LanguageInfo(code: "hr",  flag: "🇭🇷", displayName: "Croatian"),
        "sr":  LanguageInfo(code: "sr",  flag: "🇷🇸", displayName: "Serbian"),
        "sl":  LanguageInfo(code: "sl",  flag: "🇸🇮", displayName: "Slovenian"),
        "mk":  LanguageInfo(code: "mk",  flag: "🇲🇰", displayName: "Macedonian"),
        "bs":  LanguageInfo(code: "bs",  flag: "🇧🇦", displayName: "Bosnian"),
        "sq":  LanguageInfo(code: "sq",  flag: "🇦🇱", displayName: "Albanian"),
        "el":  LanguageInfo(code: "el",  flag: "🇬🇷", displayName: "Greek"),
        "tr":  LanguageInfo(code: "tr",  flag: "🇹🇷", displayName: "Turkish"),
        "uk":  LanguageInfo(code: "uk",  flag: "🇺🇦", displayName: "Ukrainian"),
        "be":  LanguageInfo(code: "be",  flag: "🇧🇾", displayName: "Belarusian"),
        "ka":  LanguageInfo(code: "ka",  flag: "🇬🇪", displayName: "Georgian"),
        "hy":  LanguageInfo(code: "hy",  flag: "🇦🇲", displayName: "Armenian"),
        "az":  LanguageInfo(code: "az",  flag: "🇦🇿", displayName: "Azerbaijani"),
        "kk":  LanguageInfo(code: "kk",  flag: "🇰🇿", displayName: "Kazakh"),
        "uz":  LanguageInfo(code: "uz",  flag: "🇺🇿", displayName: "Uzbek"),
        "tg":  LanguageInfo(code: "tg",  flag: "🇹🇯", displayName: "Tajik"),
        "tk":  LanguageInfo(code: "tk",  flag: "🇹🇲", displayName: "Turkmen"),
        "ky":  LanguageInfo(code: "ky",  flag: "🇰🇬", displayName: "Kyrgyz"),
        "mn":  LanguageInfo(code: "mn",  flag: "🇲🇳", displayName: "Mongolian"),

        // ── Middle East & North Africa ─────────────────────────────────────
        "ar":  LanguageInfo(code: "ar",  flag: "🇸🇦", displayName: "Arabic"),
        "he":  LanguageInfo(code: "he",  flag: "🇮🇱", displayName: "Hebrew"),
        "fa":  LanguageInfo(code: "fa",  flag: "🇮🇷", displayName: "Persian"),
        "ur":  LanguageInfo(code: "ur",  flag: "🇵🇰", displayName: "Urdu"),
        "ps":  LanguageInfo(code: "ps",  flag: "🇦🇫", displayName: "Pashto"),
        "ku":  LanguageInfo(code: "ku",  flag: "🇮🇶", displayName: "Kurdish"),
        "am":  LanguageInfo(code: "am",  flag: "🇪🇹", displayName: "Amharic"),
        "ti":  LanguageInfo(code: "ti",  flag: "🇪🇷", displayName: "Tigrinya"),
        "so":  LanguageInfo(code: "so",  flag: "🇸🇴", displayName: "Somali"),

        // ── South & Southeast Asia ─────────────────────────────────────────
        "hi":  LanguageInfo(code: "hi",  flag: "🇮🇳", displayName: "Hindi"),
        "bn":  LanguageInfo(code: "bn",  flag: "🇧🇩", displayName: "Bengali"),
        "pa":  LanguageInfo(code: "pa",  flag: "🇮🇳", displayName: "Punjabi"),
        "gu":  LanguageInfo(code: "gu",  flag: "🇮🇳", displayName: "Gujarati"),
        "mr":  LanguageInfo(code: "mr",  flag: "🇮🇳", displayName: "Marathi"),
        "ta":  LanguageInfo(code: "ta",  flag: "🇮🇳", displayName: "Tamil"),
        "te":  LanguageInfo(code: "te",  flag: "🇮🇳", displayName: "Telugu"),
        "kn":  LanguageInfo(code: "kn",  flag: "🇮🇳", displayName: "Kannada"),
        "ml":  LanguageInfo(code: "ml",  flag: "🇮🇳", displayName: "Malayalam"),
        "or":  LanguageInfo(code: "or",  flag: "🇮🇳", displayName: "Odia"),
        "si":  LanguageInfo(code: "si",  flag: "🇱🇰", displayName: "Sinhala"),
        "ne":  LanguageInfo(code: "ne",  flag: "🇳🇵", displayName: "Nepali"),
        "my":  LanguageInfo(code: "my",  flag: "🇲🇲", displayName: "Burmese"),
        "th":  LanguageInfo(code: "th",  flag: "🇹🇭", displayName: "Thai"),
        "lo":  LanguageInfo(code: "lo",  flag: "🇱🇦", displayName: "Lao"),
        "km":  LanguageInfo(code: "km",  flag: "🇰🇭", displayName: "Khmer"),
        "vi":  LanguageInfo(code: "vi",  flag: "🇻🇳", displayName: "Vietnamese"),
        "id":  LanguageInfo(code: "id",  flag: "🇮🇩", displayName: "Indonesian"),
        "ms":  LanguageInfo(code: "ms",  flag: "🇲🇾", displayName: "Malay"),
        "tl":  LanguageInfo(code: "tl",  flag: "🇵🇭", displayName: "Filipino"),
        "ceb": LanguageInfo(code: "ceb", flag: "🇵🇭", displayName: "Cebuano"),
        "jv":  LanguageInfo(code: "jv",  flag: "🇮🇩", displayName: "Javanese"),

        // ── East Asia ──────────────────────────────────────────────────────
        "zh":  LanguageInfo(code: "zh",  flag: "🇨🇳", displayName: "Chinese"),
        "ja":  LanguageInfo(code: "ja",  flag: "🇯🇵", displayName: "Japanese"),
        "ko":  LanguageInfo(code: "ko",  flag: "🇰🇷", displayName: "Korean"),

        // ── Africa ─────────────────────────────────────────────────────────
        "sw":  LanguageInfo(code: "sw",  flag: "🇹🇿", displayName: "Swahili"),
        "zu":  LanguageInfo(code: "zu",  flag: "🇿🇦", displayName: "Zulu"),
        "xh":  LanguageInfo(code: "xh",  flag: "🇿🇦", displayName: "Xhosa"),
        "af":  LanguageInfo(code: "af",  flag: "🇿🇦", displayName: "Afrikaans"),
        "st":  LanguageInfo(code: "st",  flag: "🇱🇸", displayName: "Sotho"),
        "tn":  LanguageInfo(code: "tn",  flag: "🇧🇼", displayName: "Tswana"),
        "yo":  LanguageInfo(code: "yo",  flag: "🇳🇬", displayName: "Yoruba"),
        "ig":  LanguageInfo(code: "ig",  flag: "🇳🇬", displayName: "Igbo"),
        "ha":  LanguageInfo(code: "ha",  flag: "🇳🇬", displayName: "Hausa"),
        "mg":  LanguageInfo(code: "mg",  flag: "🇲🇬", displayName: "Malagasy"),

        // ── Americas ───────────────────────────────────────────────────────
        "qu":  LanguageInfo(code: "qu",  flag: "🇵🇪", displayName: "Quechua"),
        "gn":  LanguageInfo(code: "gn",  flag: "🇵🇾", displayName: "Guaraní"),
        "ht":  LanguageInfo(code: "ht",  flag: "🇭🇹", displayName: "Haitian Creole"),

        // ── Pacific ────────────────────────────────────────────────────────
        "mi":  LanguageInfo(code: "mi",  flag: "🇳🇿", displayName: "Māori"),
        "haw": LanguageInfo(code: "haw", flag: "🇺🇸", displayName: "Hawaiian"),
        "fj":  LanguageInfo(code: "fj",  flag: "🇫🇯", displayName: "Fijian"),
        "to":  LanguageInfo(code: "to",  flag: "🇹🇴", displayName: "Tongan"),
        "sm":  LanguageInfo(code: "sm",  flag: "🇼🇸", displayName: "Samoan"),

        // ── Classical / liturgical ─────────────────────────────────────────
        "la":  LanguageInfo(code: "la",  flag: "🇻🇦", displayName: "Latin"),
        "grc": LanguageInfo(code: "grc", flag: "🇬🇷", displayName: "Ancient Greek"),
        "hbo": LanguageInfo(code: "hbo", flag: "🇮🇱", displayName: "Biblical Hebrew"),
        "syc": LanguageInfo(code: "syc", flag: "🇸🇾", displayName: "Classical Syriac"),
        "cop": LanguageInfo(code: "cop", flag: "🇪🇬", displayName: "Coptic"),

        // ── Celtic & other European ────────────────────────────────────────
        "cy":  LanguageInfo(code: "cy",  flag: "🏴󠁧󠁢󠁷󠁬󠁳󠁿", displayName: "Welsh"),
        "ga":  LanguageInfo(code: "ga",  flag: "🇮🇪", displayName: "Irish"),
        "gd":  LanguageInfo(code: "gd",  flag: "🏴󠁧󠁢󠁳󠁣󠁴󠁿", displayName: "Scottish Gaelic"),
        "eu":  LanguageInfo(code: "eu",  flag: "🇪🇸", displayName: "Basque"),
        "ca":  LanguageInfo(code: "ca",  flag: "🇪🇸", displayName: "Catalan"),
        "gl":  LanguageInfo(code: "gl",  flag: "🇪🇸", displayName: "Galician"),
        "is":  LanguageInfo(code: "is",  flag: "🇮🇸", displayName: "Icelandic"),
        "fo":  LanguageInfo(code: "fo",  flag: "🇫🇴", displayName: "Faroese"),
        "mt":  LanguageInfo(code: "mt",  flag: "🇲🇹", displayName: "Maltese"),
        "lb":  LanguageInfo(code: "lb",  flag: "🇱🇺", displayName: "Luxembourgish"),
        "fy":  LanguageInfo(code: "fy",  flag: "🇳🇱", displayName: "Frisian"),

        // ── Central Asia / Caucasus extras ─────────────────────────────────
        "ab":  LanguageInfo(code: "ab",  flag: "🇬🇪", displayName: "Abkhaz"),
        "os":  LanguageInfo(code: "os",  flag: "🇷🇺", displayName: "Ossetian"),
        "ce":  LanguageInfo(code: "ce",  flag: "🇷🇺", displayName: "Chechen"),
        "av":  LanguageInfo(code: "av",  flag: "🇷🇺", displayName: "Avar"),
        "ba":  LanguageInfo(code: "ba",  flag: "🇷🇺", displayName: "Bashkir"),
        "tt":  LanguageInfo(code: "tt",  flag: "🇷🇺", displayName: "Tatar"),
        "cv":  LanguageInfo(code: "cv",  flag: "🇷🇺", displayName: "Chuvash"),
        "udm": LanguageInfo(code: "udm", flag: "🇷🇺", displayName: "Udmurt"),
        "mhr": LanguageInfo(code: "mhr", flag: "🇷🇺", displayName: "Mari"),
        "kv":  LanguageInfo(code: "kv",  flag: "🇷🇺", displayName: "Komi"),
    ]
}
