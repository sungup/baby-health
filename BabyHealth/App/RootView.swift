import SwiftUI
import SwiftData
import UserNotifications

struct RootView: View {
    @Query(sort: \Baby.createdAt) private var babies: [Baby]
    @AppStorage(AppStorageKey.selectedBabyID) private var selectedBabyID = ""
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var shareCenter = AlarmShareCenter.shared

    /// 알람 계산에 영향을 주는 값이 바뀌었는지 비교하는 서명.
    private var alarmInputs: [AlarmBabyInput] {
        babies.map { AlarmBabyInput(baby: $0) }
    }

    private var sharePresented: Binding<Bool> {
        Binding(
            get: { shareCenter.pendingText != nil },
            set: { if !$0 { shareCenter.pendingText = nil } }
        )
    }

    var body: some View {
        content
            .task { await refreshAlarms(requestIfNeeded: true) }
            .onChange(of: alarmInputs) { _, _ in
                Task { await refreshAlarms(requestIfNeeded: true) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await refreshAlarms(requestIfNeeded: false) }
                }
            }
            .sheet(isPresented: sharePresented) {
                ShareSheet(items: [shareCenter.pendingText ?? ""])
            }
    }

    private func refreshAlarms(requestIfNeeded: Bool) async {
        let inputs = alarmInputs
        if requestIfNeeded,
           inputs.contains(where: { $0.medications.contains { !$0.slots.isEmpty } }),
           await AlarmScheduler.shared.authorizationStatus() == .notDetermined {
            await AlarmScheduler.shared.requestAuthorization()
        }
        await AlarmScheduler.shared.reschedule(inputs: inputs)
    }

    @ViewBuilder
    private var content: some View {
        if let baby = BabySelection.resolve(selectedID: selectedBabyID, in: babies) {
            // .id(baby.uuid): 아기를 바꾸면 각 화면의 @State(점검 결과 등)를 초기화한다.
            TabView {
                DashboardView(baby: baby)
                    .id(baby.uuid)
                    .tabItem { Label("요약", systemImage: "heart.text.square") }
                VaccinationListView(baby: baby)
                    .id(baby.uuid)
                    .tabItem { Label("접종", systemImage: "syringe") }
                HospitalVisitListView(baby: baby)
                    .id(baby.uuid)
                    .tabItem { Label("병원", systemImage: "cross.case") }
                MedicationListView(baby: baby)
                    .id(baby.uuid)
                    .tabItem { Label("투약", systemImage: "pills") }
                TemperatureListView(baby: baby)
                    .id(baby.uuid)
                    .tabItem { Label("체온", systemImage: "thermometer.medium") }
            }
        } else {
            BabyFormView(baby: nil, isOnboarding: true)
        }
    }
}
