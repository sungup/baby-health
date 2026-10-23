import SwiftUI
import SwiftData

@main
struct BabyHealthApp: App {
    @StateObject private var googleAuth = GoogleAuthManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(googleAuth)
        }
        .modelContainer(
            for: [
                Baby.self,
                Vaccination.self,
                HospitalVisit.self,
                Medication.self,
                MedicationDose.self,
                TemperatureRecord.self
            ]
        )
    }
}
