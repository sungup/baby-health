import SwiftUI

/// Google 계정(처방전 인식), Gemini/Anthropic API 키를 설정하는 화면.
struct ConnectionSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var googleAuth: GoogleAuthManager

    @AppStorage(SettingsKey.googleOAuthClientID) private var clientID = ""
    @AppStorage(SettingsKey.googleCloudProjectID) private var projectID = ""
    @AppStorage(SettingsKey.geminiModel) private var geminiModel = GeminiPrescriptionReader.defaultModel
    @AppStorage(SettingsKey.anthropicModel) private var anthropicModel = AnthropicClient.defaultModel

    @State private var isWorking = false
    @State private var message: String?

    private var trimmedClientID: String {
        clientID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                googleSection

                ModelPickerSection(
                    title: "처방전 인식 모델 (Gemini)",
                    presets: ModelCatalog.geminiPresets,
                    footer: "\"불러오기\"는 연결된 Google 계정 또는 Gemini API 키로 쓸 수 있는 모델을 조회합니다. 목록에 없는 모델은 ID를 직접 입력할 수 있습니다.",
                    selection: $geminiModel,
                    fetch: { try await fetchGeminiModels() }
                )

                SecretKeySection(
                    title: "Gemini API 키 (대체 수단)",
                    placeholder: "Gemini API 키",
                    account: SecretAccount.geminiAPIKey,
                    footer: "Google 계정 연결이 거부되거나 설정이 번거로울 때 쓰는 대체 수단입니다. Google AI Studio에서 발급한 키를 입력하세요. 키는 이 기기의 Keychain에만 저장됩니다."
                )

                SecretKeySection(
                    title: "Anthropic API 키 (현황 점검)",
                    placeholder: "Anthropic API 키",
                    account: SecretAccount.anthropicAPIKey,
                    footer: "요약 탭의 \"지금 점검하기\"에 사용됩니다. 이름 등 식별 정보는 전송하지 않습니다."
                )

                ModelPickerSection(
                    title: "현황 점검 모델 (Anthropic)",
                    presets: ModelCatalog.anthropicPresets,
                    footer: "저장된 Anthropic API 키로 쓸 수 있는 모델을 불러옵니다. 모델마다 속도와 비용이 다릅니다.",
                    selection: $anthropicModel,
                    fetch: { try await fetchAnthropicModels() }
                )
            }
            .navigationTitle("연동 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private var googleSection: some View {
        Section {
            HStack {
                Text("상태")
                Spacer()
                if googleAuth.isSignedIn {
                    Label("연결됨", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("연결 안 됨")
                        .foregroundStyle(.secondary)
                }
            }

            TextField("OAuth 클라이언트 ID (iOS)", text: $clientID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Cloud 프로젝트 ID (선택)", text: $projectID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if googleAuth.isSignedIn {
                Button("연결 해제", role: .destructive) {
                    Task { await googleAuth.signOut() }
                }
            } else {
                Button {
                    connect()
                } label: {
                    if isWorking {
                        HStack {
                            ProgressView()
                            Text("연결 중...")
                        }
                    } else {
                        Label("Google 계정 연결", systemImage: "person.badge.key")
                    }
                }
                .disabled(trimmedClientID.isEmpty || isWorking)
            }

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Google 계정 (처방전 인식)")
        } footer: {
            Text("처방전 이미지를 Gemini로 해석할 때 사용합니다. Google Cloud에서 Generative Language API를 켜고 iOS용 OAuth 클라이언트(번들 ID: com.sungup.babyhealth)를 만든 뒤 클라이언트 ID를 입력하세요. 자세한 절차는 README를 참고하세요.")
        }
    }

    private func fetchGeminiModels() async throws -> [String] {
        let credentials = await GeminiCredentialResolver.credentials(
            auth: googleAuth,
            isGoogleSignedIn: googleAuth.isSignedIn,
            clientID: trimmedClientID,
            projectID: projectID
        )
        return try await GeminiModelLister().fetch(credentials: credentials)
    }

    private func fetchAnthropicModels() async throws -> [String] {
        let key = KeychainStore.read(account: SecretAccount.anthropicAPIKey) ?? ""
        return try await AnthropicModelLister().fetch(apiKey: key)
    }

    private func connect() {
        isWorking = true
        message = nil
        let config = GoogleOAuthConfig(clientID: trimmedClientID)

        Task {
            do {
                try await googleAuth.signIn(config: config)
                await MainActor.run { isWorking = false }
            } catch GoogleAuthError.cancelled {
                await MainActor.run { isWorking = false }
            } catch {
                await MainActor.run {
                    message = error.localizedDescription
                    isWorking = false
                }
            }
        }
    }
}

/// Keychain 에 저장되는 비밀 키 입력 섹션.
private struct SecretKeySection: View {
    let title: String
    let placeholder: String
    let account: String
    let footer: String

    @State private var value = ""
    @State private var hasSavedKey: Bool
    @State private var errorMessage: String?

    init(title: String, placeholder: String, account: String, footer: String) {
        self.title = title
        self.placeholder = placeholder
        self.account = account
        self.footer = footer
        _hasSavedKey = State(initialValue: KeychainStore.read(account: account) != nil)
    }

    private var trimmedValue: String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Section {
            SecureField(placeholder, text: $value)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button("저장") {
                save()
            }
            .disabled(trimmedValue.isEmpty)

            if hasSavedKey {
                Label("저장된 키가 있습니다", systemImage: "checkmark.seal")
                Button("저장된 키 삭제", role: .destructive) {
                    KeychainStore.delete(account: account)
                    hasSavedKey = false
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text(title)
        } footer: {
            Text(footer)
        }
    }

    private func save() {
        do {
            try KeychainStore.save(trimmedValue, account: account)
            value = ""
            hasSavedKey = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 사용할 모델을 고르는 섹션. 기본 후보 + 서버에서 불러온 목록 + 직접 입력.
private struct ModelPickerSection: View {
    let title: String
    let presets: [String]
    let footer: String
    @Binding var selection: String
    let fetch: () async throws -> [String]

    @State private var fetched: [String] = []
    @State private var isLoading = false
    @State private var customID = ""
    @State private var statusMessage: String?
    @State private var isError = false

    private var options: [String] {
        ModelCatalog.options(selection: selection, presets: presets, fetched: fetched)
    }

    private var trimmedCustomID: String {
        customID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Section {
            Picker("모델", selection: $selection) {
                ForEach(options, id: \.self) { id in
                    Text(id).tag(id)
                }
            }

            HStack {
                TextField("직접 입력 (모델 ID)", text: $customID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("적용") {
                    selection = trimmedCustomID
                    customID = ""
                }
                .buttonStyle(.borderless)
                .disabled(trimmedCustomID.isEmpty)
            }

            Button {
                refresh()
            } label: {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("불러오는 중...")
                    }
                } else {
                    Label("사용 가능한 모델 불러오기", systemImage: "arrow.clockwise")
                }
            }
            .disabled(isLoading)

            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(isError ? Color.red : Color.secondary)
            }
        } header: {
            Text(title)
        } footer: {
            Text(footer)
        }
    }

    private func refresh() {
        isLoading = true
        statusMessage = nil

        Task {
            do {
                let ids = try await fetch()
                await MainActor.run {
                    fetched = ids
                    isError = false
                    statusMessage = ids.isEmpty ? "불러온 모델이 없습니다." : "\(ids.count)개 모델을 불러왔습니다."
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isError = true
                    statusMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}
