import Foundation
import CryptoKit

enum GoogleAuthError: LocalizedError {
    case invalidClientID
    case cancelled
    case stateMismatch
    case missingCode
    case notSignedIn
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidClientID:
            return "OAuth 클라이언트 ID 형식이 올바르지 않습니다. (예: 123456-abc.apps.googleusercontent.com)"
        case .cancelled:
            return "Google 로그인이 취소되었습니다."
        case .stateMismatch:
            return "로그인 응답을 확인할 수 없습니다. 다시 시도해 주세요."
        case .missingCode:
            return "로그인 응답에 인증 코드가 없습니다."
        case .notSignedIn:
            return "Google 계정이 연결되어 있지 않습니다."
        case .invalidResponse:
            return "Google 서버 응답을 해석할 수 없습니다."
        case .server(let message):
            return "Google 인증 오류: \(message)"
        }
    }
}

/// iOS용 OAuth 클라이언트 설정.
struct GoogleOAuthConfig: Equatable {
    /// Gemini API 문서가 안내하는 scope. generateContent 에 충분한지는 계정/프로젝트 설정에 따라 달라질 수 있어
    /// 한 곳에서만 정의한다. 403 이 나면 Gemini API 키 대체 경로를 사용한다.
    static let defaultScopes = ["https://www.googleapis.com/auth/generative-language.retriever"]

    let clientID: String
    var scopes: [String] = GoogleOAuthConfig.defaultScopes

    private static let clientIDSuffix = ".apps.googleusercontent.com"

    /// "<번호>-<해시>.apps.googleusercontent.com" → "com.googleusercontent.apps.<번호>-<해시>"
    var redirectScheme: String? {
        guard clientID.hasSuffix(Self.clientIDSuffix) else { return nil }
        let prefix = String(clientID.dropLast(Self.clientIDSuffix.count))
        guard !prefix.isEmpty else { return nil }
        return "com.googleusercontent.apps." + prefix
    }

    var redirectURI: String? {
        redirectScheme.map { $0 + ":/oauth2redirect" }
    }
}

/// OAuth 2.0 PKCE (RFC 7636) 도우미.
enum PKCE {
    private static let unreserved = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func randomString(length: Int = 64) -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in unreserved.randomElement(using: &generator)! })
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// 토큰 교환/갱신과 액세스 토큰 캐시. 리프레시 토큰은 Keychain 에만 저장한다.
actor GoogleTokenService {
    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Int
        let refreshToken: String?
    }

    private struct ErrorBody: Decodable {
        let error: String?
        let errorDescription: String?
    }

    private static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!

    private var accessToken: String?
    private var expiry = Date.distantPast
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func exchange(code: String, verifier: String, redirectURI: String, clientID: String) async throws {
        let response = try await post([
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code"
        ])
        guard let refreshToken = response.refreshToken else {
            throw GoogleAuthError.server("리프레시 토큰을 받지 못했습니다. 연결을 해제한 뒤 다시 시도해 주세요.")
        }
        try KeychainStore.save(refreshToken, account: SecretAccount.googleRefreshToken)
        cache(response)
    }

    func validAccessToken(clientID: String) async throws -> String {
        if let accessToken, expiry > Date.now.addingTimeInterval(60) {
            return accessToken
        }
        guard let refreshToken = KeychainStore.read(account: SecretAccount.googleRefreshToken) else {
            throw GoogleAuthError.notSignedIn
        }
        do {
            let response = try await post([
                "client_id": clientID,
                "refresh_token": refreshToken,
                "grant_type": "refresh_token"
            ])
            cache(response)
            return response.accessToken
        } catch GoogleAuthError.server(let message) where message.contains("invalid_grant") {
            // 취소/만료된 리프레시 토큰: 로컬 로그인 상태를 정리한다.
            clear()
            throw GoogleAuthError.notSignedIn
        }
    }

    func clear() {
        accessToken = nil
        expiry = .distantPast
        KeychainStore.delete(account: SecretAccount.googleRefreshToken)
    }

    private func cache(_ response: TokenResponse) {
        accessToken = response.accessToken
        expiry = Date.now.addingTimeInterval(TimeInterval(response.expiresIn))
    }

    private func post(_ fields: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = fields
            .map { "\($0.key)=\(Self.formEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GoogleAuthError.invalidResponse }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        guard (200..<300).contains(http.statusCode) else {
            let body = try? decoder.decode(ErrorBody.self, from: data)
            let message = [body?.error, body?.errorDescription].compactMap { $0 }.joined(separator: ": ")
            throw GoogleAuthError.server(message.isEmpty ? "HTTP \(http.statusCode)" : message)
        }
        guard let token = try? decoder.decode(TokenResponse.self, from: data) else {
            throw GoogleAuthError.invalidResponse
        }
        return token
    }

    static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
