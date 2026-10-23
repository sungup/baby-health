import SwiftUI
import SwiftData

struct TemperatureListView: View {
    let baby: Baby

    @Environment(\.modelContext) private var context
    @State private var showingAdd = false

    private var items: [TemperatureRecord] {
        baby.temperatures.sorted { $0.measuredAt > $1.measuredAt }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(String(format: "%.1f", record.celsius))°C")
                                .font(.headline)
                                .foregroundStyle(record.isFever ? Color.red : Color.primary)
                            Text("\(record.method.label) · \(record.measuredAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if record.isFever {
                            Label("발열", systemImage: "thermometer.high")
                                .font(.caption)
                                .foregroundStyle(.red)
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
                        "체온 기록이 없습니다",
                        systemImage: "thermometer.medium",
                        description: Text("오른쪽 위 + 버튼으로 추가하세요.")
                    )
                }
            }
            .navigationTitle("체온")
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
                AddTemperatureView(baby: baby)
            }
        }
    }
}

struct AddTemperatureView: View {
    let baby: Baby

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var celsiusText = ""
    @State private var method = TemperatureMethod.ear
    @State private var measuredAt = Date.now
    @State private var notes = ""

    private var celsius: Double? {
        let normalized = celsiusText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), (34.0...42.0).contains(value) else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("체온 (°C, 예: 37.5)", text: $celsiusText)
                    .keyboardType(.decimalPad)
                Picker("측정 부위", selection: $method) {
                    ForEach(TemperatureMethod.allCases) { method in
                        Text(method.label).tag(method)
                    }
                }
                DatePicker("측정 시각", selection: $measuredAt, in: ...Date.now)
                TextField("메모 (선택)", text: $notes, axis: .vertical)
                if !celsiusText.isEmpty && celsius == nil {
                    Text("34.0 ~ 42.0 사이의 값을 입력하세요.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("체온 추가")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .disabled(celsius == nil)
                }
            }
        }
    }

    private func save() {
        guard let celsius else { return }
        let record = TemperatureRecord(
            measuredAt: measuredAt,
            celsius: celsius,
            method: method,
            notes: notes
        )
        context.insert(record)
        record.baby = baby
        dismiss()
    }
}
