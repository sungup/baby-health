import SwiftUI
import SwiftData

struct MedicationListView: View {
    let baby: Baby

    @Environment(\.modelContext) private var context
    @State private var showingAdd = false

    private var items: [Medication] {
        baby.medications.sorted { $0.startDate > $1.startDate }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { medication in
                    MedicationRow(medication: medication)
                        .swipeActions(edge: .leading) {
                            if medication.isActive() {
                                Button("복용 기록") {
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
                        "투약 기록이 없습니다",
                        systemImage: "pills",
                        description: Text("오른쪽 위 + 버튼으로 추가하세요.")
                    )
                }
            }
            .navigationTitle("투약")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddMedicationView(baby: baby)
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
            Text(periodText)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if !medication.reason.isEmpty {
                Text("사유: \(medication.reason)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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

struct AddMedicationView: View {
    let baby: Baby

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var dosage = ""
    @State private var timesPerDay = 3
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
                TextField("약 이름", text: $name)
                TextField("1회 용량 (예: 2.5ml)", text: $dosage)
                Stepper("하루 \(timesPerDay)회", value: $timesPerDay, in: 1...8)
                DatePicker("시작일", selection: $startDate, displayedComponents: .date)
                Toggle("종료일 있음", isOn: $hasEndDate)
                if hasEndDate {
                    DatePicker("종료일", selection: $endDate, in: startDate..., displayedComponents: .date)
                }
                TextField("복용 사유 (선택)", text: $reason)
                TextField("메모 (선택)", text: $notes, axis: .vertical)
            }
            .navigationTitle("투약 추가")
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
            notes: notes
        )
        context.insert(medication)
        medication.baby = baby
        dismiss()
    }
}
