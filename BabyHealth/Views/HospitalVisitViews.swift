import SwiftUI
import SwiftData

struct HospitalVisitListView: View {
    let baby: Baby

    @Environment(\.modelContext) private var context
    @State private var showingAdd = false

    private var items: [HospitalVisit] {
        baby.visits.sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { visit in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(visit.hospitalName)
                                .font(.headline)
                            Spacer()
                            Text(visit.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text("사유: \(visit.reason)")
                            .font(.subheadline)
                        if !visit.diagnosis.isEmpty {
                            Text("진단: \(visit.diagnosis)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
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
                        "병원 방문 기록이 없습니다",
                        systemImage: "cross.case",
                        description: Text("오른쪽 위 + 버튼으로 추가하세요.")
                    )
                }
            }
            .navigationTitle("병원")
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
                AddHospitalVisitView(baby: baby)
            }
        }
    }
}

struct AddHospitalVisitView: View {
    let baby: Baby

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date.now
    @State private var hospitalName = ""
    @State private var reason = ""
    @State private var diagnosis = ""
    @State private var notes = ""

    private var canSave: Bool {
        !hospitalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("방문일", selection: $date, in: ...Date.now, displayedComponents: .date)
                TextField("병원 이름", text: $hospitalName)
                TextField("방문 사유", text: $reason)
                TextField("진단 (선택)", text: $diagnosis)
                TextField("메모 (선택)", text: $notes, axis: .vertical)
            }
            .navigationTitle("병원 방문 추가")
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
        let visit = HospitalVisit(
            date: date,
            hospitalName: hospitalName.trimmingCharacters(in: .whitespacesAndNewlines),
            reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
            diagnosis: diagnosis,
            notes: notes
        )
        context.insert(visit)
        visit.baby = baby
        dismiss()
    }
}
