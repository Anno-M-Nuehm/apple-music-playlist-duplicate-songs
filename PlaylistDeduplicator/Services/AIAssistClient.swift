import Foundation

/// Optional AI assist for tracks with an empty or invalid file location.
///
/// Privacy: only anonymized metadata (title/artist/album) is sent,
/// over HTTPS, to the configured endpoint. If the feature is disabled
/// in config.json, no key exists in the Keychain, the network is
/// unreachable, or any error occurs, the call fails soft and the app
/// remains fully usable.
struct AIAssistRequest: Sendable, Equatable {
    var title: String
    var artist: String
    var album: String
}

struct AIAssistResult: Sendable, Equatable {
    var matchedTitle: String
    var matchedArtist: String
    var matchedAlbum: String
    var confidence: Double
}

protocol AIAssistProviding: Sendable {
    func identify(_ request: AIAssistRequest) async throws -> AIAssistResult
}

struct AIAssistDisabledError: Error {}

final class AIAssistClient: AIAssistProviding, @unchecked Sendable {
    private let config: AppConfig.AIAssist
    private let keychain: KeychainStore
    private let urlSession: URLSession

    init(config: AppConfig.AIAssist,
         keychain: KeychainStore = KeychainStore(),
         urlSession: URLSession = .shared) {
        self.config = config
        self.keychain = keychain
        self.urlSession = urlSession
    }

    func identify(_ request: AIAssistRequest) async throws -> AIAssistResult {
        guard config.enabled else { throw AIAssistDisabledError() }
        guard let apiKey = keychain.readAPIKey() else { throw AIAssistDisabledError() }
        guard let url = URL(string: config.endpoint), url.scheme == "https" else {
            throw AIAssistDisabledError()
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = config.timeoutSeconds
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(chatBody(for: request))

        let (data, _) = try await urlSession.data(for: urlRequest)
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let content = decoded.choices.first?.message.content ?? ""
        return try Self.parse(resultJSON: content)
    }

    private func chatBody(for request: AIAssistRequest) -> ChatBody {
        ChatBody(
            model: config.model,
            messages: [
                .init(role: "system", content: "You match music track metadata. Reply with ONLY a JSON object with keys title, artist, album, confidence (0-1). No prose."),
                .init(role: "user", content: "Title: \(request.title)\nArtist: \(request.artist)\nAlbum: \(request.album)")
            ]
        )
    }

    private static func parse(resultJSON: String) throws -> AIAssistResult {
        struct Payload: Decodable {
            var title: String
            var artist: String
            var album: String
            var confidence: Double?
        }
        let cleaned = resultJSON
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw AIAssistDisabledError()
        }
        return AIAssistResult(
            matchedTitle: payload.title,
            matchedArtist: payload.artist,
            matchedAlbum: payload.album,
            confidence: payload.confidence ?? 0
        )
    }

    private struct ChatBody: Encodable {
        struct Message: Encodable {
            var role: String
            var content: String
        }
        var model: String
        var messages: [Message]
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { var content: String }
            var message: Message
        }
        var choices: [Choice]
    }
}
