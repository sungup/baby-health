import SwiftUI
import SwiftData

struct RootView: View {
    @Query(sort: \Baby.createdAt) private var babies: [Baby]
    @AppStorage(AppStorageKey.selectedBabyID) private var selectedBabyID = ""

    var body: some View {
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
