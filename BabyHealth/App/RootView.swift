import SwiftUI
import SwiftData

struct RootView: View {
    @Query(sort: \Baby.createdAt) private var babies: [Baby]

    var body: some View {
        if let baby = babies.first {
            TabView {
                DashboardView(baby: baby)
                    .tabItem { Label("요약", systemImage: "heart.text.square") }
                VaccinationListView(baby: baby)
                    .tabItem { Label("접종", systemImage: "syringe") }
                HospitalVisitListView(baby: baby)
                    .tabItem { Label("병원", systemImage: "cross.case") }
                MedicationListView(baby: baby)
                    .tabItem { Label("투약", systemImage: "pills") }
                TemperatureListView(baby: baby)
                    .tabItem { Label("체온", systemImage: "thermometer.medium") }
            }
        } else {
            BabyOnboardingView()
        }
    }
}
