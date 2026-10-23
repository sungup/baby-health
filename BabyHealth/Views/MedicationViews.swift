import SwiftUI
import SwiftData

private enum MedicationSheet: Identifiable {
    case scanPrescription
    case addPrescription
    case addDose

    var id: Self { self }
}

// MARK: - 처방/투약 목록

struct MedicationListView: View {
    let baby: Baby

    @Environment(\.modelContext) private var context
    @State private var activeSheet: MedicationSheet?

    private var items: [Medication] {
        baby.medications.sorted { $0.prescribedDate > $1.prescribedDate }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { medication in
                    NavigationLink {
                        MedicationDetailView(baby: baby, medication: medication)
                    } label: {
                        MedicationRow(medication: medication)
                    }
                    .swipeActions(edge: .leading) {
                        if medication.isActive() {
                            Button("지금 복용") {
                                let dose = MedicationDose(takenAt: .now)
                                context.insert(dose)
                                dose.medication = medication
                            }
                            .tint(.blue)
                        }
                    }
                }
                .onDelete { offsets in
                    let current = items
                    for index in offsets {
                        context.delete(current[index])
                    }
                }
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView(
                        "처방 기록이 없습니다",
                        systemImage: "pills",
                        description: Text("오른쪽 위 + 버튼에서 처방전을 촬영하거나 직접 입력하세요.")
                    )
                }
            }
            .navigationTitle("투약")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    BabySwitcherMenu()
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            activeSheet = .scanPrescription
                        } label: {
                            Label("처방전 촬영·인식", systemImage: "camera.viewfinder")
                        }
                        Button {
                            activeSheet = .addPrescription
                        } label: {
                            Label("처방 직접 입력", systemImage: "square.and.pencil")
                        }
                        Button {
                            activeSheet = .addDose
                        } label: {
                            Label("투약 기록 추가", systemImage: "checkmark.circle")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .scanPrescription:
                    PrescriptionScanView(baby: baby)
                case .addPrescription:
                    AddMedicationView(baby: baby)
                case .addDose:
                    AddMedicationDoseView(baby: baby)
                }
            }
        }
    }
}

private struct MedicationRow: View {
    let medication: Medication

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(medication.name)
                    .font(.headline)
                Spacer()
                if medication.isActive() {
                    Text("오늘 \(medication.doseCount(on: .now))/\(medication.timesPerDay)회")
                        .font(.caption)
                        .foregroundStyle(.blue)
                } else {
                    Text("종료")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("\(medication.dosage) · 하루 \(medication.timesPerDay)회")
                .font(.subheadline)
            if !medication.timingNote.isEmpty {
                Text(medication.timingNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(periodText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var periodText: String {
        let start = medication.startDate.formatted(date: .abbreviated, time: .omitted)
        if let end = medication.endDate {
            return "\(start) ~ \(end.formatted(date: .abbreviated, time: .omitted))"
        }
        return "\(start) ~ 종료일 미정"
    }
}

// MARK: - 처방 상세 + 투약 기록

struct MedicationDetailView: View {
    let baby: Baby
    let medication: Medication

    @Environment(\.modelContext) private var context
    @State private var showingAddDose = false

    private var doses: [MedicationDose] {
        medication.doses.sorted { $0.takenAt > $1.takenAt }
    }

    var body: some View {
        List {
            Section("처방 정보") {
                LabeledContent("약 이름", value: medication.name)
                LabeledContent("1회 용량", value: medication.dosage)
                LabeledContent("횟수", value: "하루 \(medication.timesPerDay)회")
                if !medication.timingNote.isEmpty {
                    LabeledContent("복용 시점", value: medication.timingNote)
                }
                LabeledContent("처방일", value: medication.prescribedDate.formatted(date: .abbreviated, time: .omitted))
                if !medication.prescriber.isEmpty {
                    LabeledContent("처방 병원/의사", value: medication.prescriber)
                }
                LabeledContent("복용 기간", value: periodText)
                if !medication.reason.isEmpty {
                    LabeledContent("사유", value: medication.reason)
                }
                if !medication.notes.isEmpty {
                    Text(medication.notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("투약 기록 (\(doses.count)회)") {
                if doses.isEmpty {
                    Text("아직 투약 기록이 없습니다.")
                        .foregroundStyle(.secondary)
                }
                ForEach(doses) { dose in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dose.takenAt.formatted(date: .abbreviated, time: .shortened))
                        if !dose.notes.isEmpty {
                            Text(dose.notes)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    let current = doses
                    for index in offsets {
                        context.delete(current[index])
                    }
                }
            }
        }
        .navigationTitle(medication.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddDose = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddDose) {
            AddMedicationDoseView(baby: baby, medication: medication)
        }
    }

    private var periodText: String {
        let start = medication.startDate.formatted(date: .abbreviated, time: .omitted)
        if let end = medication.endDate {
            return "\(start) ~ \(end.formatted(date: .abbreviated, time: .omitted))"
        }
        return "\(start) ~ 종료일 미정"
    }
}

// MARK: - 처방 추가

struct AddMedicationView: View {
    let baby: Baby

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var dosage = ""
    @State private var timesPerDay = 3
    @State private var prescribedDate = Date.now
    @State private var prescriber = ""
    @State private var timingNote = ""
    @State private var startDate = Date.now
    @State private var hasEndDate = false
    @State private var endDate = Date.now
    @State private var reason = ""
    @State private var notes = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !dosage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("처방") {
                    DatePicker("처방일", selection: $prescribedDate, in: ...Date.now, displayedComponents: .date)
                    TextField("처방 병원/의사 (선택)", text: $prescriber)
                    TextField("복용 사유 (선택)", text: $reason)
                }
                Section("약") {
                    TextField("약 이름", text: $name)
                    TextField("1회 용량 (예: 2.5ml)", text: $dosage)
                    Stepper("하루 \(timesPerDay)회", value: $timesPerDay, in: 1...8)
                    TextField("복용 시점 (예: 아침·저녁 식후)", text: $timingNote)
                }
                Section("복용 기간") {
                    DatePicker("시작일", selection: $startDate, displayedComponents: .date)
                    Toggle("종료일 있음", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("종료일", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                }
                Section {
                    TextField("메모 (선택)", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("처방 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let medication = Medication(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            dosage: dosage.trimmingCharacters(in: .whitespacesAndNewlines),
            timesPerDay: timesPerDay,
            startDate: startDate,
            endDate: hasEndDate ? endDate : nil,
            reason: reason,
            notes: notes,
            prescribedDate: prescribedDate,
            prescriber: prescriber,
            timingNote: timingNote.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        context.insert(medication)
        medication.baby = baby
        dismiss()
    }
}

// MARK: - 투약 기록 추가

struct AddMedicationDoseView: View {
    let baby: Baby

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var selectedID: PersistentIdentifier?
    @State private var takenAt = Date.now
    @State private var notes = ""

    init(baby: Baby, medication: Medication? = nil) {
        self.baby = baby
        _selectedID = State(initialValue: medication?.persistentModelID)
    }

    private var activeMedications: [Medication] {
        baby.medications
            .filter { $0.isActive() }
            .sorted { $0.name < $1.name }
    }

    private var selectedMedication: Medication? {
        baby.medications.first { $0.persistentModelID == selectedID }
    }

    var body: some View {
        NavigationStack {
            Form {
                if activeMedications.isEmpty && selectedMedication == nil {
                    Section {
                        Text("진행 중인 처방이 없습니다. 먼저 처방을 추가해 주세요.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("약") {
                        Picker("약 선택", selection: $selectedID) {
                            Text("선택").tag(PersistentIdentifier?.none)
                            ForEach(activeMedications) { medication in
                                Text("\(medication.name) (\(medication.dosage))")
                                    .tag(Optional(medication.persistentModelID))
                            }
                        }
                    }
                    Section("복용") {
                        DatePicker("복용 시각", selection: $takenAt, in: ...Date.now)
                        TextField("메모 (선택)", text: $notes, axis: .vertical)
                    }
                }
            }
            .navigationTitle("투약 기록 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .disabled(selectedMedication == nil)
                }
            }
        }
    }

    private func save() {
        guard let medication = selectedMedication else { return }
        let dose = MedicationDose(takenAt: takenAt, notes: notes)
        context.insert(dose)
        dose.medication = medication
        dismiss()
    }
}
