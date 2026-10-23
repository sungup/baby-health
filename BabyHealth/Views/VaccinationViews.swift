import SwiftUI
import SwiftData

struct VaccinationListView: View {
    let baby: Baby

    @Environment(\.modelContext) private var context
    @State private var showingAdd = false

    private var items: [Vaccination] {
        baby.vaccinations.sorted { $0.scheduledDate < $1.scheduledDate }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { vaccination in
                    VaccinationRow(vaccination: vaccination)
                        .swipeActions(edge: .leading) {
                            if !vaccination.isCompleted {
                                Button("접종 완료") {
                                    vaccination.administeredDate = .now
                                }
                                .tint(.green)
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
                        "접종 기록이 없습니다",
                        systemImage: "syringe",
                        description: Text("오른쪽 위 + 버튼으로 추가하세요.")
                    )
                }
            }
            .navigationTitle("접종")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    BabySwitcherMenu()
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddVaccinationView(baby: baby)
            }
        }
    }
}

private struct VaccinationRow: View {
    let vaccination: Vaccination

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(vaccination.name) \(vaccination.doseNumber)차")
                    .font(.headline)
                Spacer()
                statusLabel
            }
            Text("예정일 \(vaccination.scheduledDate.formatted(date: .abbreviated, time: .omitted))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let administered = vaccination.administeredDate {
                Text("접종일 \(administered.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !vaccination.clinic.isEmpty {
                Text(vaccination.clinic)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusLabel: some View {
        if vaccination.isCompleted {
            Label("완료", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else if vaccination.isOverdue() {
            Label("지연", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        } else {
            Label("예정", systemImage: "calendar")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct AddVaccinationView: View {
    let baby: Baby

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var doseNumber = 1
    @State private var scheduledDate = Date.now
    @State private var alreadyAdministered = false
    @State private var administeredDate = Date.now
    @State private var clinic = ""
    @State private var notes = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("백신 이름", text: $name)
                Stepper("차수: \(doseNumber)차", value: $doseNumber, in: 1...10)
                DatePicker("예정일", selection: $scheduledDate, displayedComponents: .date)
                Toggle("이미 접종함", isOn: $alreadyAdministered)
                if alreadyAdministered {
                    DatePicker("접종일", selection: $administeredDate, in: ...Date.now, displayedComponents: .date)
                }
                TextField("병원 (선택)", text: $clinic)
                TextField("메모 (선택)", text: $notes, axis: .vertical)
            }
            .navigationTitle("접종 추가")
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
        let vaccination = Vaccination(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            doseNumber: doseNumber,
            scheduledDate: scheduledDate,
            administeredDate: alreadyAdministered ? administeredDate : nil,
            clinic: clinic,
            notes: notes
        )
        context.insert(vaccination)
        vaccination.baby = baby
        dismiss()
    }
}
