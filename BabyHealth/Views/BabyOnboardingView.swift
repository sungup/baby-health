import SwiftUI
import SwiftData

struct BabyOnboardingView: View {
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var birthDate = Date.now

    var body: some View {
        NavigationStack {
            Form {
                Section("아기 정보") {
                    TextField("이름 또는 별명", text: $name)
                    DatePicker("생년월일", selection: $birthDate, in: ...Date.now, displayedComponents: .date)
                }
                Section {
                    Button("시작하기") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        context.insert(Baby(name: trimmed, birthDate: birthDate))
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("아기 등록")
        }
    }
}
