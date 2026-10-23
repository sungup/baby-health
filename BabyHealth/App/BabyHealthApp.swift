import SwiftUI
import SwiftData
import UserNotifications

@main
struct BabyHealthApp: App {
    @StateObject private var googleAuth = GoogleAuthManager()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        Task { await AlarmScheduler.shared.registerCategories() }
    }

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
                DoseSlot.self,
                TemperatureRecord.self
            ]
        )
    }
}
