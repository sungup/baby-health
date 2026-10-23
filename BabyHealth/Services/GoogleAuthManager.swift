import Foundation
import AuthenticationServices
import UIKit

/// 로그인 시트를 띄울 창을 알려준다. (UI 전용이라 MainActor)
@MainActor
private final class WebAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        return windows.first { $0.isKeyWindow } ?? windows.first ?? ASPresentationAnchor()
    }
}

/// 진행 중인 로그인 세션이 해제되지 않도록 붙잡아 둔다.
private final class WebAuthSessionBox: @unchecked Sendable {
    private var session: ASWebAuthenticationSession?
    private var presenter: AnyObject?

    func keep(_ session: ASWebAuthenticationSession, presenter: AnyObject) {
        self.session = session
        self.presenter = presenter
    }

    func release() {
        session = nil
        presenter = nil
    }
}

/// Google 계정 연결 상태를 관리한다. (OAuth 2.0 + PKCE, ASWebAuthenticationSession)
final class GoogleAuthManager: ObservableObject {
    @Published private(set) var isSignedIn: Bool

    private let tokens = GoogleTokenService()
    private let sessionBox = WebAuthSessionBox()

    init() {
        isSignedIn = KeychainStore.read(account: SecretAccount.googleRefreshToken) != nil
    }

    func signIn(config: GoogleOAuthConfig) async throws {
        guard let redirectScheme = config.redirectScheme, let redirectURI = config.redirectURI else {
            throw GoogleAuthError.invalidClientID
        }

        let verifier = PKCE.randomString()
        let state = PKCE.randomString(length: 32)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        guard let authURL = components.url else { throw GoogleAuthError.invalidClientID }

        let callbackURL = try await authenticate(url: authURL, callbackScheme: redirectScheme)
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []

        if let error = items.first(where: { $0.name == "error" })?.value {
            throw error == "access_denied" ? GoogleAuthError.cancelled : GoogleAuthError.server(error)
        }
        guard items.first(where: { $0.name == "state" })?.value == state else {
            throw GoogleAuthError.stateMismatch
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw GoogleAuthError.missingCode
        }

        try await tokens.exchange(
            code: code,
            verifier: verifier,
            redirectURI: redirectURI,
            clientID: config.clientID
        )
        await setSignedIn(true)
    }

    func signOut() async {
        await tokens.clear()
        await setSignedIn(false)
    }

    /// 유효한 액세스 토큰을 돌려준다. 리프레시 토큰이 무효하면 로그인 상태를 해제한다.
    func accessToken(clientID: String) async throws -> String {
        do {
            return try await tokens.validAccessToken(clientID: clientID)
        } catch GoogleAuthError.notSignedIn {
            await setSignedIn(false)
            throw GoogleAuthError.notSignedIn
        }
    }

    // MARK: - 내부

    private func setSignedIn(_ value: Bool) async {
        await MainActor.run {
            self.isSignedIn = value
        }
    }

    private func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        let box = sessionBox
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            Task { @MainActor in
                let presenter = WebAuthPresenter()
                let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                    box.release()
                    if let error {
                        if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                            continuation.resume(throwing: GoogleAuthError.cancelled)
                        } else {
                            continuation.resume(throwing: error)
                        }
                        return
                    }
                    guard let callbackURL else {
                        continuation.resume(throwing: GoogleAuthError.missingCode)
                        return
                    }
                    continuation.resume(returning: callbackURL)
                }
                session.presentationContextProvider = presenter
                session.prefersEphemeralWebBrowserSession = false
                box.keep(session, presenter: presenter)
                if !session.start() {
                    box.release()
                    continuation.resume(throwing: GoogleAuthError.cancelled)
                }
            }
        }
    }
}
