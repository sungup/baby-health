import SwiftUI
import SwiftData

@main
struct BabyHealthApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
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
