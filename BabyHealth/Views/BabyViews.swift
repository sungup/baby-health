import SwiftUI
import SwiftData

// MARK: - 등록/수정 폼

struct BabyFormView: View {
    let baby: Baby?
    let isOnboarding: Bool

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppStorageKey.selectedBabyID) private var selectedBabyID = ""

    @State private var name: String
    @State private var birthDate: Date

    init(baby: Baby?, isOnboarding: Bool = false) {
        self.baby = baby
        self.isOnboarding = isOnboarding
        _name = State(initialValue: baby?.name ?? "")
        _birthDate = State(initialValue: baby?.birthDate ?? Date.now)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var title: String {
        if isOnboarding { return "아기 등록" }
        return baby == nil ? "아기 추가" : "아기 정보 수정"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("이름 또는 별명", text: $name)
                    DatePicker("생년월일", selection: $birthDate, in: ...Date.now, displayedComponents: .date)
                } footer: {
                    if isOnboarding {
                        Text("처음 한 번만 등록하면 됩니다. 다른 아기는 나중에 추가할 수 있어요.")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isOnboarding {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private func save() {
        if let baby {
            baby.name = trimmedName
            baby.birthDate = birthDate
        } else {
            let newBaby = Baby(name: trimmedName, birthDate: birthDate)
            context.insert(newBaby)
            selectedBabyID = newBaby.uuid.uuidString
        }
        dismiss()
    }
}

// MARK: - 아기 관리 목록

private enum BabyFormTarget: Identifiable {
    case add
    case edit(Baby)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let baby):
            return baby.uuid.uuidString
        }
    }
}

struct BabyManagementView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Baby.createdAt) private var babies: [Baby]
    @AppStorage(AppStorageKey.selectedBabyID) private var selectedBabyID = ""

    @State private var formTarget: BabyFormTarget?
    @State private var babyToDelete: Baby?

    var body: some View {
        NavigationStack {
            List {
                ForEach(babies) { baby in
                    Button {
                        formTarget = .edit(baby)
                    } label: {
                        BabyRow(
                            baby: baby,
                            isSelected: BabySelection.resolve(selectedID: selectedBabyID, in: babies)?.uuid == baby.uuid
                        )
                    }
                    .foregroundStyle(.primary)
                    .swipeActions(edge: .leading) {
                        Button("선택") {
                            selectedBabyID = baby.uuid.uuidString
                        }
                        .tint(.blue)
                    }
                }
                .onDelete { offsets in
                    if let index = offsets.first {
                        babyToDelete = babies[index]
                    }
                }
            }
            .navigationTitle("아기 관리")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        formTarget = .add
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $formTarget) { target in
                switch target {
                case .add:
                    BabyFormView(baby: nil)
                case .edit(let baby):
                    BabyFormView(baby: baby)
                }
            }
            .confirmationDialog(
                "아기 정보를 삭제할까요?",
                isPresented: Binding(
                    get: { babyToDelete != nil },
                    set: { isPresented in
                        if !isPresented { babyToDelete = nil }
                    }
                ),
                titleVisibility: .visible,
                presenting: babyToDelete
            ) { baby in
                Button("\(baby.name) 삭제", role: .destructive) {
                    delete(baby)
                }
            } message: { _ in
                Text("접종, 병원, 투약, 체온 기록도 함께 삭제되며 되돌릴 수 없습니다.")
            }
        }
    }

    private func delete(_ baby: Baby) {
        let deletedID = baby.uuid.uuidString
        context.delete(baby)
        if selectedBabyID == deletedID {
            selectedBabyID = ""
        }
        babyToDelete = nil
    }
}

private struct BabyRow: View {
    let baby: Baby
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(baby.name)
                    .font(.headline)
                Text("\(baby.birthDate.formatted(date: .abbreviated, time: .omitted)) · 생후 \(baby.ageInMonths())개월")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
    }
}

// MARK: - 아기 전환 메뉴 (각 탭의 툴바에서 사용)

struct BabySwitcherMenu: View {
    @Query(sort: \Baby.createdAt) private var babies: [Baby]
    @AppStorage(AppStorageKey.selectedBabyID) private var selectedBabyID = ""
    @State private var showingManagement = false

    private var current: Baby? {
        BabySelection.resolve(selectedID: selectedBabyID, in: babies)
    }

    var body: some View {
        Menu {
            ForEach(babies) { baby in
                Button {
                    selectedBabyID = baby.uuid.uuidString
                } label: {
                    if baby.uuid == current?.uuid {
                        Label(baby.name, systemImage: "checkmark")
                    } else {
                        Text(baby.name)
                    }
                }
            }
            Divider()
            Button {
                showingManagement = true
            } label: {
                Label("아기 관리", systemImage: "person.2")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "person.crop.circle")
                Text(current?.name ?? "아기 선택")
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
        }
        .sheet(isPresented: $showingManagement) {
            BabyManagementView()
        }
    }
}
