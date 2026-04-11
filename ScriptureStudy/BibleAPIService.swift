import Foundation

// MARK: - Models

struct BibleChapter: Identifiable {
    let id      = UUID()
    let book:    String
    let chapter: Int
    let verses:  [BibleVerse]
}

struct BibleVerse: Identifiable {
    let id     = UUID()
    let number: Int
    let text:   String
}

// MARK: - API Response Models

private struct APIResponse: Decodable {
    let verses: [APIVerse]
}

private struct APIVerse: Decodable {
    let verse: Int
    let text:  String
}

// MARK: - Service

@MainActor
class BibleAPIService: ObservableObject {

    @Published var isLoading    = false
    @Published var chapter:     BibleChapter?
    @Published var errorMessage: String?

    /// Loads a full chapter from bible-api.com (KJV, free, no key required)
    func loadChapter(book: BibleBook, chapter: Int) async {
        isLoading    = true
        errorMessage = nil
        self.chapter = nil

        let urlString = "https://bible-api.com/\(book.apiName)+\(chapter)?translation=kjv"

        guard let url = URL(string: urlString) else {
            errorMessage = "Could not build a valid URL for \(book.name) \(chapter)."
            isLoading = false
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }

            let decoded = try JSONDecoder().decode(APIResponse.self, from: data)

            self.chapter = BibleChapter(
                book:    book.name,
                chapter: chapter,
                verses:  decoded.verses.map {
                    BibleVerse(number: $0.verse,
                               text:   $0.text.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            )
        } catch {
            errorMessage = "Could not load \(book.name) \(chapter). Check your internet connection and try again."
        }

        isLoading = false
    }
}
