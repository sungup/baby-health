import XCTest
@testable import BabyHealth

final class GoogleOAuthConfigTests: XCTestCase {
    func testRedirectSchemeIsReversedClientID() {
        let config = GoogleOAuthConfig(clientID: "123456-abcdef.apps.googleusercontent.com")

        XCTAssertEqual(config.redirectScheme, "com.googleusercontent.apps.123456-abcdef")
        XCTAssertEqual(config.redirectURI, "com.googleusercontent.apps.123456-abcdef:/oauth2redirect")
    }

    func testInvalidClientIDHasNoRedirect() {
        XCTAssertNil(GoogleOAuthConfig(clientID: "not-a-client-id").redirectScheme)
        XCTAssertNil(GoogleOAuthConfig(clientID: ".apps.googleusercontent.com").redirectScheme)
        XCTAssertNil(GoogleOAuthConfig(clientID: "").redirectURI)
    }

    func testDefaultScopeIsGenerativeLanguage() {
        let config = GoogleOAuthConfig(clientID: "1-a.apps.googleusercontent.com")

        XCTAssertEqual(config.scopes, ["https://www.googleapis.com/auth/generative-language.retriever"])
    }
}

final class PKCETests: XCTestCase {
    /// RFC 7636 부록 B 의 예시 값.
    func testChallengeMatchesRFCExample() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"

        XCTAssertEqual(PKCE.challenge(for: verifier), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testRandomStringHasRequestedLengthAndAllowedCharacters() {
        let value = PKCE.randomString(length: 64)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

        XCTAssertEqual(value.count, 64)
        XCTAssertTrue(value.unicodeScalars.allSatisfy { allowed.contains($0) })
        XCTAssertNotEqual(value, PKCE.randomString(length: 64))
    }

    func testFormEncodeEscapesReservedCharacters() {
        XCTAssertEqual(GoogleTokenService.formEncode("a b&c=d/e"), "a%20b%26c%3Dd%2Fe")
        XCTAssertEqual(GoogleTokenService.formEncode("abc-._~"), "abc-._~")
    }
}
