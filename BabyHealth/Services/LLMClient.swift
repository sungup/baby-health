import Foundation

protocol LLMClient {
    func complete(system: String, user: String) async throws -> String
}

enum LLMError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case badStatus(Int)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API 키가 설정되지 않았습니다."
        case .invalidResponse:
            return "서버 응답을 해석할 수 없습니다."
        case .badStatus(let code):
            return "요청이 실패했습니다 (HTTP \(code))."
        case .emptyResponse:
            return "응답 내용이 비어 있습니다."
        }
    }
}

/// Anthropic Messages API 클라이언트.
/// 개인용 앱 전제로 기기에서 직접 호출한다. 배포용으로 확장할 때는 별도 백엔드 프록시를 두고 키를 앱에 두지 않는다.
struct AnthropicClient: LLMClient {
    static let defaultModel = "claude-sonnet-5-5"

    let apiKey: String
    var model: String = AnthropicClient.defaultModel
    var maxTokens: Int = 1024
    var session: URLSession = .shared

    private struct RequestBody: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        let model: String
        let maxTokens: Int
        let system: String
        let messages: [Message]
    }

    private struct ResponseBody: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }

        let content: [Block]
    }

    func complete(system: String, user: String) async throws -> String {
        guard !apiKey.isEmpty else { throw LLMError.missingAPIKey }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body = RequestBody(
            model: model,
            maxTokens: maxTokens,
            system: system,
            messages: [.init(role: "user", content: user)]
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LLMError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw LLMError.badStatus(http.statusCode) }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        let text = decoded.content
            .compactMap { $0.type == "text" ? $0.text : nil }
            .joined(separator: "\n")
        guard !text.isEmpty else { throw LLMError.emptyResponse }
        return text
    }
}
