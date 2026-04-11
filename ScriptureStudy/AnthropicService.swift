import Foundation

// MARK: - Anthropic Claude Service

class AnthropicService {

    static let shared = AnthropicService()
    private let endpoint = "https://api.anthropic.com/v1/messages"
    private let model    = "claude-haiku-4-5-20251001"  // fast and affordable

    private var apiKey: String {
        UserDefaults.standard.string(forKey: "anthropicAPIKey") ?? ""
    }

    var isConfigured: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    func complete(prompt: String) async throws -> String {
        guard isConfigured else { throw APIError.noKey }

        let body: [String: Any] = [
            "model":      model,
            "max_tokens": 1024,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        guard let url = URL(string: endpoint) else { throw APIError.badURL }
        var request        = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json",    forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey,                forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01",          forHTTPHeaderField: "anthropic-version")
        request.httpBody   = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else { throw APIError.badResponse("No response") }

        if http.statusCode == 401 { throw APIError.invalidKey }
        if http.statusCode == 402 { throw APIError.insufficientCredits }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw APIError.badResponse(msg)
        }

        struct Response: Decodable {
            struct Content: Decodable { let text: String }
            let content: [Content]
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.content.first?.text ?? ""
    }

    enum APIError: LocalizedError {
        case noKey
        case badURL
        case invalidKey
        case insufficientCredits
        case badResponse(String)

        var errorDescription: String? {
            switch self {
            case .noKey:               return "No API key set. Add your Anthropic API key in Settings."
            case .badURL:              return "Invalid API endpoint."
            case .invalidKey:          return "Invalid API key. Check your key in Settings."
            case .insufficientCredits: return "Insufficient Anthropic credits. Top up at console.anthropic.com."
            case .badResponse(let m):  return "API error: \(m.prefix(200))"
            }
        }
    }
}
