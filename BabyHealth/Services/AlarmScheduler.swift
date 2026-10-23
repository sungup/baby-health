import Foundation
import UserNotifications

enum AlarmNotification {
    static let categoryID = "dose-alarm"
    static let shareActionID = "share-dose"
    static let shareTextKey = "shareText"
    static let idPrefix = "alarm-"
}

/// 알람 계산 결과를 로컬 알림으로 예약한다. 호출할 때마다 기존 알람 예약을 지우고 다시 만든다.
actor AlarmScheduler {
    static let shared = AlarmScheduler()

    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    func registerCategories() {
        let share = UNNotificationAction(
            identifier: AlarmNotification.shareActionID,
            title: "공유",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: AlarmNotification.categoryID,
            actions: [share],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func reschedule(inputs: [AlarmBabyInput], now: Date = .now) async {
        registerCategories()

        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { $0.hasPrefix(AlarmNotification.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        let alarms = AlarmPlanner.plan(inputs: inputs, from: now)
        for alarm in alarms {
            let content = UNMutableNotificationContent()
            content.title = alarm.title
            content.body = alarm.body
            content.sound = .default
            content.categoryIdentifier = AlarmNotification.categoryID
            content.userInfo = [AlarmNotification.shareTextKey: alarm.shareText]

            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: alarm.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let request = UNNotificationRequest(identifier: alarm.id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}

/// 알림의 "공유" 동작으로 받은 텍스트를 화면에 전달한다.
@MainActor
final class AlarmShareCenter: ObservableObject {
    static let shared = AlarmShareCenter()
    @Published var pendingText: String?
}

/// 포그라운드 표시와 "공유" 동작 처리.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == AlarmNotification.shareActionID,
              let text = response.notification.request.content.userInfo[AlarmNotification.shareTextKey] as? String
        else { return }
        await MainActor.run { AlarmShareCenter.shared.pendingText = text }
    }
}
