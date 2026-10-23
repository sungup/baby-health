import SwiftUI

struct DashboardView: View {
    let baby: Baby

    @State private var result: HealthCheckResult?
    @State private var isRunning = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            List {
                Section("기본 정보") {
                    LabeledContent("이름", value: baby.name)
                    LabeledContent("월령", value: "생후 \(baby.ageInMonths())개월")
                }

                Section("현황 점검") {
                    Button {
                        runCheck()
                    } label: {
                        if isRunning {
                            HStack {
                                ProgressView()
                                Text("점검 중...")
                            }
                        } else {
                            Label("지금 점검하기", systemImage: "checkmark.shield")
                        }
                    }
                    .disabled(isRunning)
                }

                if let result {
                    Section("규칙 기반 결과") {
                        if result.findings.isEmpty {
                            Label("특이 사항이 없습니다.", systemImage: "checkmark.circle")
                                .foregroundStyle(.green)
                        }
                        ForEach(result.findings) { finding in
                            Label(finding.message, systemImage: icon(for: finding.severity))
                                .foregroundStyle(color(for: finding.severity))
                        }
                    }

                    Section("LLM 검토") {
                        if let review = result.llmReview {
                            Text(review)
                        } else if let error = result.llmError {
                            Text(error).foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Text("이 내용은 참고용이며 의료진 상담을 대체하지 않습니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("요약")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "key")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                APIKeySettingsView()
            }
        }
    }

    private func runCheck() {
        isRunning = true
        let snapshot = HealthSnapshot(baby: baby)
        let key = KeychainStore.read(account: SecretAccount.anthropicAPIKey) ?? ""
        let client: LLMClient? = key.isEmpty ? nil : AnthropicClient(apiKey: key)

        Task {
            let outcome = await HealthCheckService(client: client).run(snapshot: snapshot)
            await MainActor.run {
                result = outcome
                isRunning = false
            }
        }
    }

    private func icon(for severity: HealthFinding.Severity) -> String {
        switch severity {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .alert: return "exclamationmark.octagon"
        }
    }

    private func color(for severity: HealthFinding.Severity) -> Color {
        switch severity {
        case .info: return .secondary
        case .warning: return .orange
        case .alert: return .red
        }
    }
}
