import Foundation

/// Keychain 항목 이름 모음.
enum SecretAccount {
    static let anthropicAPIKey = "anthropic-api-key"
    static let geminiAPIKey = "gemini-api-key"
    static let googleRefreshToken = "google-oauth-refresh-token"
}

/// 비밀이 아닌 연동 설정(UserDefaults/AppStorage) 키.
enum SettingsKey {
    static let googleOAuthClientID = "googleOAuthClientID"
    static let googleCloudProjectID = "googleCloudProjectID"
    static let geminiModel = "geminiModel"
    static let anthropicModel = "anthropicModel"
}
