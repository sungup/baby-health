import SwiftUI

enum SecretAccount {
    static let anthropicAPIKey = "anthropic-api-key"
}

struct APIKeySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var hasSavedKey = KeychainStore.read(account: SecretAccount.anthropicAPIKey) != nil
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Anthropic API 키", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("키는 이 기기의 Keychain에만 저장되며, 점검 시 Anthropic API로 직접 전송됩니다. 이름 등 식별 정보는 전송하지 않습니다.")
                }

                if hasSavedKey {
                    Section {
                        Label("저장된 키가 있습니다", systemImage: "checkmark.seal")
                        Button("저장된 키 삭제", role: .destructive) {
                            KeychainStore.delete(account: SecretAccount.anthropicAPIKey)
                            hasSavedKey = false
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("LLM 설정")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        do {
            let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            try KeychainStore.save(trimmed, account: SecretAccount.anthropicAPIKey)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
