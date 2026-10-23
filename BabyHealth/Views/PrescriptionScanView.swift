import SwiftUI
import SwiftData
import PhotosUI

/// 처방전을 촬영/선택 → Gemini 분석 → 결과 검토·수정 → 처방(약)으로 저장.
struct PrescriptionScanView: View {
    let baby: Baby

    private enum Phase {
        case pick
        case analyzing
        case review
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var googleAuth: GoogleAuthManager

    @AppStorage(SettingsKey.googleOAuthClientID) private var clientID = ""
    @AppStorage(SettingsKey.googleCloudProjectID) private var projectID = ""
    @AppStorage(SettingsKey.geminiModel) private var geminiModel = GeminiPrescriptionReader.defaultModel

    @State private var phase: Phase = .pick
    @State private var images: [UIImage] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showingScanner = false
    @State private var showingSettings = false
    @State private var consented = false
    @State private var errorMessage: String?

    @State private var prescribedDate = Date.now
    @State private var startDate = Date.now
    @State private var prescriber = ""
    @State private var drafts: [MedicationDraft] = []
    @State private var warnings: [String] = []

    private var includedCount: Int {
        drafts.filter { $0.include && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .pick:
                    pickForm
                case .analyzing:
                    analyzingView
                case .review:
                    reviewForm
                }
            }
            .navigationTitle("처방전 인식")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                if phase == .review {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("저장") { save() }
                            .disabled(includedCount == 0)
                    }
                }
            }
            .fullScreenCover(isPresented: $showingScanner) {
                DocumentScannerView(
                    onFinish: { scanned in
                        images.append(contentsOf: scanned)
                        showingScanner = false
                    },
                    onCancel: {
                        showingScanner = false
                    }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showingSettings) {
                ConnectionSettingsView()
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await loadPhotos(items) }
            }
        }
    }

    // MARK: - 1) 촬영 / 선택

    private var pickForm: some View {
        Form {
            Section {
                Button {
                    showingScanner = true
                } label: {
                    Label("카메라로 촬영", systemImage: "camera.viewfinder")
                }
                .disabled(!DocumentScannerView.isSupported)

                PhotosPicker(selection: $photoItems, maxSelectionCount: 4, matching: .images) {
                    Label("사진 보관함에서 선택", systemImage: "photo.on.rectangle")
                }
            } header: {
                Text("처방전 이미지")
            } footer: {
                if DocumentScannerView.isSupported {
                    Text("처방전 전체가 선명하게 나오도록 평평한 곳에서 촬영하세요. 여러 장도 가능합니다.")
                } else {
                    Text("이 기기에서는 카메라 촬영을 사용할 수 없습니다. 사진 보관함에서 선택해 주세요.")
                }
            }

            if !images.isEmpty {
                Section("선택한 이미지 \(images.count)장") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(images.indices, id: \.self) { index in
                                thumbnail(for: index)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section {
                Toggle(isOn: $consented) {
                    Text("이미지를 Google Gemini로 전송해 분석하는 데 동의합니다.")
                }
            } footer: {
                Text("처방전에는 아기 이름·주민등록번호 등 개인정보가 있을 수 있습니다. 가능하면 해당 부분을 가리고 촬영하세요. 이미지는 분석에만 쓰이고 이 앱에 저장되지 않습니다.")
            }

            Section {
                Button {
                    analyze()
                } label: {
                    Label("분석하기", systemImage: "sparkles")
                }
                .disabled(images.isEmpty || !consented)

                Button {
                    showingSettings = true
                } label: {
                    Label("연동 설정", systemImage: "key")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func thumbnail(for index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: images[index])
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Button {
                images.remove(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .padding(4)
        }
    }

    // MARK: - 2) 분석 중

    private var analyzingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("처방전을 읽고 있습니다...")
                .font(.headline)
            Text("보통 10~30초 정도 걸립니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 3) 결과 검토

    private var reviewForm: some View {
        Form {
            Section {
                Label("AI가 읽은 결과입니다. 처방전과 반드시 대조한 뒤 저장하세요.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                ForEach(warnings, id: \.self) { warning in
                    Label(warning, systemImage: "questionmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("처방 정보") {
                DatePicker("처방일", selection: $prescribedDate, in: ...Date.now, displayedComponents: .date)
                TextField("처방 병원/의사", text: $prescriber)
                DatePicker("복용 시작일", selection: $startDate, displayedComponents: .date)
            }

            ForEach($drafts) { $draft in
                Section {
                    Toggle("이 약 저장", isOn: $draft.include)
                    TextField("약 이름", text: $draft.name)
                    TextField("1회 용량 (예: 2.5ml)", text: $draft.dosage)
                    Stepper("하루 \(draft.timesPerDay)회", value: $draft.timesPerDay, in: 1...8)
                    TextField("복용 시점 (예: 아침·저녁 식후)", text: $draft.timing)
                    TextField("투약 일수", text: $draft.daysText)
                        .keyboardType(.numberPad)
                    TextField("복용 사유", text: $draft.reason)
                    TextField("메모", text: $draft.notes, axis: .vertical)
                } header: {
                    Text(draft.name.isEmpty ? "약" : draft.name)
                }
            }

            Section {
                Button("다시 촬영/선택") {
                    phase = .pick
                }
            }
        }
    }

    // MARK: - 동작

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        var loaded: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                loaded.append(image)
            }
        }
        await MainActor.run {
            images.append(contentsOf: loaded)
            photoItems = []
        }
    }

    private func analyze() {
        errorMessage = nil
        let imageData = images.compactMap { ImagePreprocessor.jpegData(from: $0) }
        guard !imageData.isEmpty else {
            errorMessage = "이미지를 처리하지 못했습니다. 다시 시도해 주세요."
            return
        }

        phase = .analyzing

        let auth = googleAuth
        let signedIn = googleAuth.isSignedIn
        let oauthClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cloudProjectID = projectID

        let model = ModelCatalog.effective(geminiModel, default: GeminiPrescriptionReader.defaultModel)
        let reader = GeminiPrescriptionReader(model: model, credentials: {
            await GeminiCredentialResolver.credentials(
                auth: auth,
                isGoogleSignedIn: signedIn,
                clientID: oauthClientID,
                projectID: cloudProjectID
            )
        })

        Task {
            do {
                let parsed = try await reader.read(images: imageData)
                await MainActor.run { apply(parsed) }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    phase = .pick
                }
            }
        }
    }

    private func apply(_ parsed: ParsedPrescription) {
        let newDrafts = parsed.medications
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { MedicationDraft(parsed: $0) }

        guard !newDrafts.isEmpty else {
            errorMessage = "처방된 약 정보를 찾지 못했습니다. 더 선명하게 다시 촬영해 보세요."
            phase = .pick
            return
        }

        let date = min(PrescriptionImporter.parseDate(parsed.prescribedDate) ?? Date.now, Date.now)
        prescribedDate = date
        startDate = date
        prescriber = parsed.prescriber ?? ""
        warnings = parsed.warnings
        drafts = newDrafts
        phase = .review
    }

    private func save() {
        for draft in drafts where draft.include && !draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
            let medication = PrescriptionImporter.makeMedication(
                from: draft,
                prescribedDate: prescribedDate,
                startDate: startDate,
                prescriber: prescriber
            )
            context.insert(medication)
            medication.baby = baby
        }
        dismiss()
    }
}
