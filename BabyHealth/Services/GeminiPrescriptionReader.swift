import Foundation

enum GeminiCredential: Equatable {
    /// Google 계정(OAuth) 액세스 토큰. 프로젝트 ID 가 있으면 할당량 프로젝트로 보낸다.
    case oauth(accessToken: String, projectID: String?)
    /// Gemini API 키 (대체 경로)
    case apiKey(String)
}

enum GeminiError: LocalizedError {
    case notConnected
    case badStatus(Int, String)
    case emptyResponse
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Gemini 연결이 필요합니다. 설정(열쇠 버튼)에서 Google 계정을 연결하거나 Gemini API 키를 입력해 주세요."
        case .badStatus(let code, let message):
            if code == 401 || code == 403 {
                return "Gemini 접근이 거부되었습니다 (HTTP \(code)). 계정 권한/scope 또는 API 키를 확인해 주세요. \(message)"
            }
            return "Gemini 요청이 실패했습니다 (HTTP \(code)). \(message)"
        case .emptyResponse:
            return "Gemini 응답이 비어 있습니다. 이미지가 선명한지 확인해 주세요."
        case .invalidResponse:
            return "Gemini 응답을 해석할 수 없습니다."
        }
    }
}

enum PrescriptionPrompt {
    static let text = """
    첨부된 이미지는 한국의 병원/약국 처방전, 약 봉투, 또는 복약 안내문입니다.
    영유아용 처방일 수 있으며, 약마다 복용 시점이 서로 다를 수 있습니다.

    규칙:
    - 환자 이름, 주민등록번호, 보험/차트 번호, 연락처 등 개인 식별 정보는 절대 출력하지 마세요.
    - 이미지에 없는 내용은 추측하지 말고 null 로 두세요. 읽기 불확실한 부분은 warnings 에 적으세요.
    - dosage 는 "1회" 복용량이며 단위를 포함하세요 (예: "2.5ml", "1포", "0.5정").
    - timing 은 복용 시점을 아침/점심/저녁/취침 전, 식전/식후/식간, 분 단위 표현으로 적고, 한 약에 시점이 여럿이면 쉼표로 구분하세요 (예: "아침 식후 30분, 저녁 식후 30분", "취침 전", "필요 시").
    - 식사나 취침과 무관한 시각/간격 지시(예: "8시간마다")만 있으면 timing 은 null 로 두고 intervalHours 에 간격(시간, 정수)을 적으세요.
    - timesPerDay 는 timing 과 일치하는 하루 복용 횟수(정수)입니다. "필요 시"처럼 정해지지 않았으면 null.
    - days 는 총 투약 일수(정수), prescribedDate 는 처방일(yyyy-MM-dd)입니다.
    - 처방된 약마다 medications 항목을 하나씩 만드세요.

    아래 JSON 형식으로만 답하세요. 설명 문장이나 코드 블록 표시는 쓰지 마세요.
    {
      "prescribedDate": "yyyy-MM-dd 또는 null",
      "prescriber": "병원/의원 이름 또는 null",
      "medications": [
        {
          "name": "약 이름",
          "dosage": "1회 용량 또는 null",
          "timesPerDay": 3,
          "timing": "복용 시점 또는 null",
          "intervalHours": null,
          "days": 5,
          "reason": "효능/복용 사유 또는 null",
          "notes": "주의사항 또는 null"
        }
      ],
      "warnings": ["불확실하거나 읽기 어려웠던 부분"]
    }
    """
}

/// 처방전 이미지를 Gemini 로 읽어 구조화된 결과로 돌려준다.
/// 인증 방식(Google 계정/API 키)은 `credentials` 가 우선순위 순으로 돌려주며,
/// 401/403 이면 다음 후보로 넘어간다.
struct GeminiPrescriptionReader {
    /// 모델 이름은 여기 한 곳에서만 바꾼다.
    static let defaultModel = "gemini-3.8-flash"

    var model: String = GeminiPrescriptionReader.defaultModel
    var credentials: () async throws -> [GeminiCredential]
    var session: URLSession = .shared

    func read(images: [Data]) async throws -> ParsedPrescription {
        let candidates = try await credentials()
        guard !candidates.isEmpty else { throw GeminiError.notConnected }

        var lastError: Error = GeminiError.notConnected
        for credential in candidates {
            do {
                let text = try await generate(images: images, credential: credential)
                return try PrescriptionParser.parse(text)
            } catch GeminiError.badStatus(let code, let message) where code == 401 || code == 403 {
                lastError = GeminiError.badStatus(code, message)
            }
        }
        throw lastError
    }

    // MARK: - 요청

    private struct RequestBody: Encodable {
        struct InlineData: Encodable {
            let mimeType: String
            let data: String

            enum CodingKeys: String, CodingKey {
                case mimeType = "mime_type"
                case data
            }
        }

        struct Part: Encodable {
            var text: String?
            var inlineData: InlineData?

            enum CodingKeys: String, CodingKey {
                case text
                case inlineData = "inline_data"
            }
        }

        struct Content: Encodable {
            let parts: [Part]
        }

        struct GenerationConfig: Encodable {
            let responseMimeType: String
            let temperature: Double
        }

        let contents: [Content]
        let generationConfig: GenerationConfig
    }

    private struct ResponseBody: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable {
                    let text: String?
                }

                let parts: [Part]?
            }

            let content: Content?
        }

        let candidates: [Candidate]?
    }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable {
            let message: String?
        }

        let error: Detail?
    }

    private func generate(images: [Data], credential: GeminiCredential) async throws -> String {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw GeminiError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        credential.apply(to: &request)

        var parts = images.map {
            RequestBody.Part(inlineData: .init(mimeType: "image/jpeg", data: $0.base64EncodedString()))
        }
        parts.append(RequestBody.Part(text: PrescriptionPrompt.text))

        let body = RequestBody(
            contents: [.init(parts: parts)],
            generationConfig: .init(responseMimeType: "application/json", temperature: 0)
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GeminiError.invalidResponse }

        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error?.message ?? ""
            throw GeminiError.badStatus(http.statusCode, message)
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        let text = (decoded.candidates ?? [])
            .flatMap { $0.content?.parts ?? [] }
            .compactMap { $0.text }
            .joined(separator: "\n")
        guard !text.isEmpty else { throw GeminiError.emptyResponse }
        return text
    }
}

/// 현재 연결 상태에서 사용할 수 있는 인증 후보를 우선순위대로 만든다.
/// Google 계정이 연결돼 있으면 먼저, 그다음 Gemini API 키.
enum GeminiCredentialResolver {
    static func credentials(
        auth: GoogleAuthManager,
        isGoogleSignedIn: Bool,
        clientID: String,
        projectID: String
    ) async -> [GeminiCredential] {
        var result: [GeminiCredential] = []

        if isGoogleSignedIn, !clientID.isEmpty,
           let token = try? await auth.accessToken(clientID: clientID) {
            let project = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(.oauth(accessToken: token, projectID: project.isEmpty ? nil : project))
        }

        if let key = KeychainStore.read(account: SecretAccount.geminiAPIKey), !key.isEmpty {
            result.append(.apiKey(key))
        }
        return result
    }
}
