import Foundation

/// 모델 선택 UI 에 쓰는 기본 목록과 합치기 로직.
enum ModelCatalog {
    /// 서버에서 목록을 불러오기 전에 보여줄 기본 후보. 실제 사용 가능 여부는 "불러오기"로 확인한다.
    static let geminiPresets = [
        "gemini-3.8-flash",
        "gemini-3.6-flash",
        "gemini-3.5-flash-lite",
        "gemini-3.1-flash-lite"
    ]

    static let anthropicPresets = [
        "claude-sonnet-5-5",
        "claude-opus-5-5",
        "claude-haiku-5-5",
        "claude-fable-5-1"
    ]

    /// 기본 후보 → 불러온 목록(정렬) → 현재 선택값 순으로 중복 없이 합친다.
    static func options(selection: String, presets: [String], fetched: [String]) -> [String] {
        var result: [String] = []
        for id in presets + fetched.sorted() + [selection] where !id.isEmpty && !result.contains(id) {
            result.append(id)
        }
        return result
    }

    /// 저장된 값이 비어 있으면 기본값을 쓴다.
    static func effective(_ stored: String, default defaultValue: String) -> String {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultValue : trimmed
    }
}

/// 모델 목록 API 응답 파서.
enum ModelListParser {
    private struct GeminiList: Decodable {
        struct Model: Decodable {
            let name: String
            let supportedGenerationMethods: [String]?
        }

        let models: [Model]?
        let nextPageToken: String?
    }

    private struct AnthropicList: Decodable {
        struct Model: Decodable {
            let id: String
        }

        let data: [Model]?
    }

    /// generateContent 를 지원하는 gemini 모델만 골라 "models/" 접두어를 뗀 ID 로 돌려준다.
    static func geminiModelIDs(from data: Data) -> [String] {
        guard let list = try? JSONDecoder().decode(GeminiList.self, from: data) else { return [] }
        return (list.models ?? [])
            .filter { $0.supportedGenerationMethods?.contains("generateContent") ?? true }
            .map { $0.name.hasPrefix("models/") ? String($0.name.dropFirst("models/".count)) : $0.name }
            .filter { $0.hasPrefix("gemini") }
    }

    static func geminiNextPageToken(from data: Data) -> String? {
        guard let token = (try? JSONDecoder().decode(GeminiList.self, from: data))?.nextPageToken,
              !token.isEmpty else { return nil }
        return token
    }

    static func anthropicModelIDs(from data: Data) -> [String] {
        guard let list = try? JSONDecoder().decode(AnthropicList.self, from: data) else { return [] }
        return (list.data ?? []).map(\.id)
    }
}

extension GeminiCredential {
    /// 인증 방식에 맞는 헤더를 요청에 붙인다.
    func apply(to request: inout URLRequest) {
        switch self {
        case .oauth(let accessToken, let projectID):
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            if let projectID, !projectID.isEmpty {
                request.setValue(projectID, forHTTPHeaderField: "x-goog-user-project")
            }
        case .apiKey(let key):
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        }
    }
}

/// Gemini 에서 현재 계정/키로 쓸 수 있는 모델 목록을 가져온다.
struct GeminiModelLister {
    var session: URLSession = .shared

    func fetch(credentials: [GeminiCredential]) async throws -> [String] {
        guard !credentials.isEmpty else { throw GeminiError.notConnected }

        var lastError: Error = GeminiError.notConnected
        for credential in credentials {
            do {
                return try await fetchAll(credential: credential)
            } catch GeminiError.badStatus(let code, let message) where code == 401 || code == 403 {
                lastError = GeminiError.badStatus(code, message)
            }
        }
        throw lastError
    }

    private func fetchAll(credential: GeminiCredential) async throws -> [String] {
        var ids: [String] = []
        var pageToken: String?

        for _ in 0..<5 {
            var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models")!
            var items = [URLQueryItem(name: "pageSize", value: "200")]
            if let pageToken {
                items.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components.queryItems = items
            guard let url = components.url else { throw GeminiError.invalidResponse }

            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            credential.apply(to: &request)

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw GeminiError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw GeminiError.badStatus(http.statusCode, "")
            }

            ids.append(contentsOf: ModelListParser.geminiModelIDs(from: data))
            guard let next = ModelListParser.geminiNextPageToken(from: data) else { break }
            pageToken = next
        }
        return ids
    }
}

/// Anthropic 에서 현재 키로 쓸 수 있는 모델 목록을 가져온다.
struct AnthropicModelLister {
    var session: URLSession = .shared

    func fetch(apiKey: String) async throws -> [String] {
        guard !apiKey.isEmpty else { throw LLMError.missingAPIKey }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=1000")!)
        request.timeoutInterval = 30
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LLMError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw LLMError.badStatus(http.statusCode) }
        return ModelListParser.anthropicModelIDs(from: data)
    }
}
