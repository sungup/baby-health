import SwiftUI

private enum DashboardSheet: Identifiable {
    case temperature
    case dose
    case apiKey

    var id: Self { self }
}

struct DashboardView: View {
    let baby: Baby

    @State private var result: HealthCheckResult?
    @State private var isRunning = false
    @State private var activeSheet: DashboardSheet?

    private var latestTemperature: TemperatureRecord? {
        baby.temperatures.max { $0.measuredAt < $1.measuredAt }
    }

    private var nextVaccination: Vaccination? {
        baby.vaccinations
            .filter { !$0.isCompleted }
            .min { $0.scheduledDate < $1.scheduledDate }
    }

    private var activeMedications: [Medication] {
        baby.medications
            .filter { $0.isActive() }
            .sorted { $0.name < $1.name }
    }

    private var lastVisit: HospitalVisit? {
        baby.visits.max { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                profileSection
                temperatureSection
                medicationSection
                vaccinationSection
                visitSection
                checkSection
                resultSections

                Section {
                    Text("이 내용은 참고용이며 의료진 상담을 대체하지 않습니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("요약")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    BabySwitcherMenu()
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        activeSheet = .apiKey
                    } label: {
                        Image(systemName: "key")
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .temperature:
                    AddTemperatureView(baby: baby)
                case .dose:
                    AddMedicationDoseView(baby: baby)
                case .apiKey:
                    APIKeySettingsView()
                }
            }
        }
    }

    // MARK: 섹션

    private var profileSection: some View {
        Section("아기 정보") {
            LabeledContent("이름", value: baby.name)
            LabeledContent("생년월일", value: baby.birthDate.formatted(date: .abbreviated, time: .omitted))
            LabeledContent("월령", value: "생후 \(baby.ageInMonths())개월")
        }
    }

    private var temperatureSection: some View {
        Section("체온") {
            if let record = latestTemperature {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(String(format: "%.1f", record.celsius))°C")
                            .font(.title2.bold())
                            .foregroundStyle(record.isFever ? Color.red : Color.primary)
                        Text("\(record.method.label) · \(record.measuredAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if record.isFever {
                        Label("발열", systemImage: "thermometer.high")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            } else {
                Text("체온 기록이 없습니다.")
                    .foregroundStyle(.secondary)
            }
            Button {
                activeSheet = .temperature
            } label: {
                Label("체온 입력", systemImage: "plus.circle")
            }
        }
    }

    private var medicationSection: some View {
        Section("진행 중인 투약") {
            if activeMedications.isEmpty {
                Text("진행 중인 처방이 없습니다.")
                    .foregroundStyle(.secondary)
            }
            ForEach(activeMedications) { medication in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(medication.name)
                        Text("\(medication.dosage) · 하루 \(medication.timesPerDay)회")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("오늘 \(medication.doseCount(on: .now))/\(medication.timesPerDay)")
                        .font(.subheadline)
                        .foregroundStyle(medication.doseCount(on: .now) >= medication.timesPerDay ? Color.green : Color.blue)
                }
            }
            Button {
                activeSheet = .dose
            } label: {
                Label("투약 기록 입력", systemImage: "plus.circle")
            }
            .disabled(activeMedications.isEmpty)
        }
    }

    private var vaccinationSection: some View {
        Section("다음 접종") {
            if let vaccination = nextVaccination {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(vaccination.name) \(vaccination.doseNumber)차")
                        Text("예정일 \(vaccination.scheduledDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if vaccination.isOverdue() {
                        Label("지연", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                Text("예정된 접종이 없습니다.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var visitSection: some View {
        Section("최근 병원 방문") {
            if let visit = lastVisit {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(visit.hospitalName) · \(visit.reason)")
                    Text(visit.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("병원 방문 기록이 없습니다.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var checkSection: some View {
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
    }

    @ViewBuilder
    private var resultSections: some View {
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
                    Text(error)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: 동작

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
