import Foundation

// MARK: - Chat Message

struct ChatMessage: Identifiable, Codable {
    var id      = UUID()
    let role:    String
    let content: String

    enum CodingKeys: String, CodingKey {
        case role, content
    }
}

// MARK: - Ollama Service

@MainActor
class OllamaService: ObservableObject {

    @Published var isLoading        = false
    @Published var summaryProvider:  String = "ollama"  // "ollama" or "claude"
    @Published var ollamaReady      = false
    @Published var chapterSummary:   String = ""
    @Published var bookSummary:       String = ""
    @Published var summaryPassage:   String = ""
    @Published var bookName:          String = ""
    @Published var summaryReady:     Bool   = false
    @Published var summaryIsLoading: Bool   = false
    @Published var bookSummaryReady: Bool   = false

    // Model to use — user can change in Settings
    @Published var selectedModel: String {
        didSet { UserDefaults.standard.set(selectedModel, forKey: "ollamaModel") }
    }

    // Available models discovered from Ollama
    @Published var availableModels: [String] = []

    private let baseURL = "http://localhost:11434"

    init() {
        self.selectedModel = UserDefaults.standard.string(forKey: "ollamaModel") ?? "llama3.2"
        Task { await checkOllama() }
    }

    // MARK: - Check Ollama is running and fetch models

    func checkOllama() async {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                ollamaReady = false; return
            }

            struct TagsResponse: Decodable {
                struct Model: Decodable { let name: String }
                let models: [Model]
            }

            let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
            availableModels = decoded.models.map { $0.name }
            ollamaReady = !availableModels.isEmpty

            // Auto-select first available model if saved one isn't installed
            if !availableModels.contains(selectedModel), let first = availableModels.first {
                selectedModel = first
            }
        } catch {
            ollamaReady = false
        }
    }

    // MARK: - Send chat message

    func send(history: [ChatMessage], userMessage: String) async throws -> String {
        isLoading = true
        defer { isLoading = false }

        // Build messages with system prompt prepended
        var messages: [[String: String]] = [
            [
                "role": "system",
                "content": """
                    You are a knowledgeable, spiritually sensitive Bible study companion.
                    Provide thoughtful, scholarly yet accessible responses about scripture,
                    theology, biblical history, and spiritual application. Draw from various
                    Christian traditions respectfully. Reference specific passages when relevant.
                    Keep responses warm, clear, and concise — typically 2–3 paragraphs.
                    """
            ]
        ]

        // Add conversation history
        for msg in history {
            messages.append(["role": msg.role, "content": msg.content])
        }
        messages.append(["role": "user", "content": userMessage])

        // Build request. keep_alive: -1 tells Ollama to keep the model
        // resident in memory instead of unloading it after 5 minutes of
        // inactivity — eliminates the warm-up delay on subsequent
        // questions within the same session.
        let body: [String: Any] = [
            "model":      selectedModel,
            "messages":   messages,
            "stream":     false,
            "keep_alive": -1
        ]

        guard let url = URL(string: "\(baseURL)/api/chat") else {
            throw ServiceError.notRunning
        }

        var request = URLRequest(url: url)
        request.httpMethod  = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody    = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120  // local models can be slow on first response

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.badResponse(body)
        }

        // Parse response
        struct OllamaResponse: Decodable {
            struct Message: Decodable { let role: String; let content: String }
            let message: Message
        }

        let decoded = try JSONDecoder().decode(OllamaResponse.self, from: data)
        return decoded.message.content
    }

    // MARK: - Chapter summary

    func generateBookAndChapterSummary(bookName: String, passage: String, verseTexts: String) async {
        let useClaude = AnthropicService.shared.isConfigured
        guard useClaude || ollamaReady else { return }
        summaryProvider = useClaude ? "claude" : "ollama" 
        summaryIsLoading = true
        summaryReady     = false
        bookSummaryReady = false
        summaryPassage   = passage
        self.bookName    = bookName

        // Generate book overview first
        let bookPrompt = """
            Please provide a scholarly overview of the book of \(bookName) suitable for Bible study.

            Include:
            - Author, date written and historical context
            - Main themes and theological purpose
            - Key characters and events
            - The book's place in the overall Biblical narrative
            - Practical application for today

            Keep to 3-4 focused paragraphs.
            """
        do {
            let bookResponse = try await completeSummary(bookPrompt)
            bookSummary      = bookResponse
            bookSummaryReady = true
        } catch {}

        // Then generate chapter summary
        let chapterPrompt = """
            Please provide a detailed study summary of \(passage).

            Include:
            - The main themes of this chapter
            - Historical and cultural context
            - Key verses and their significance
            - Theological insights and spiritual application

            Keep to 3-4 focused paragraphs. Here is the chapter text:
            \(verseTexts.prefix(4000))
            """
        do {
            let chapterResponse = try await completeSummary(chapterPrompt)
            chapterSummary   = chapterResponse
            summaryReady     = true
            summaryIsLoading = false
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            summaryReady     = false
            bookSummaryReady = false
        } catch {
            summaryIsLoading = false
        }
    }

    func generateSummary(passage: String, verseTexts: String) async {
        let useClaude = AnthropicService.shared.isConfigured
        guard useClaude || ollamaReady else { return }
        summaryProvider = useClaude ? "claude" : "ollama" 
        summaryIsLoading = true
        summaryReady     = false
        summaryPassage   = passage

        let prompt = """
            Please provide a detailed study summary of \(passage).

            Include:
            - The main themes of this chapter
            - Historical and cultural context
            - Key verses and their significance
            - Theological insights and spiritual application

            Keep the summary to 3-4 focused paragraphs. Be scholarly yet accessible.

            Here is the chapter text:
            \(verseTexts.prefix(4000))
            """

        do {
            let response = try await completeSummary(prompt)
            chapterSummary   = response
            summaryReady     = true
            summaryIsLoading = false
            // Auto-clear the "ready" indicator after 4 seconds
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            summaryReady = false
        } catch {
            summaryIsLoading = false
        }
    }

    // MARK: - Summary routing helper

    private func completeSummary(_ prompt: String) async throws -> String {
        if AnthropicService.shared.isConfigured {
            return try await AnthropicService.shared.complete(prompt: prompt)
        }
        return try await send(history: [], userMessage: prompt)
    }

    // MARK: - Errors

    enum ServiceError: LocalizedError {
        case notRunning
        case noModels
        case badResponse(String)

        var errorDescription: String? {
            switch self {
            case .notRunning:
                return "Ollama is not running. Open Terminal and run: ollama serve"
            case .noModels:
                return "No models installed. Run: ollama pull llama3.2"
            case .badResponse(let msg):
                return "Ollama error: \(msg.prefix(200))"
            }
        }
    }
}
