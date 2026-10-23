import Foundation
import SwiftData

@Model
final class Baby {
    /// 선택된 아기를 저장(AppStorage)하기 위한 안정적인 식별자.
    var uuid: UUID
    var name: String
    var birthDate: Date
    var createdAt: Date

    /// 식사/취침 시간 (자정 기준 분). 식사 기준 투약 알람의 기준점.
    var breakfastMinutes: Int
    var lunchMinutes: Int
    var dinnerMinutes: Int
    var bedtimeMinutes: Int
    var mealAlarmsEnabled: Bool
    var medicationAlarmsEnabled: Bool

    @Relationship(deleteRule: .cascade, inverse: \Vaccination.baby)
    var vaccinations: [Vaccination] = []

    @Relationship(deleteRule: .cascade, inverse: \HospitalVisit.baby)
    var visits: [HospitalVisit] = []

    @Relationship(deleteRule: .cascade, inverse: \Medication.baby)
    var medications: [Medication] = []

    @Relationship(deleteRule: .cascade, inverse: \TemperatureRecord.baby)
    var temperatures: [TemperatureRecord] = []

    init(name: String, birthDate: Date, createdAt: Date = .now, uuid: UUID = UUID()) {
        self.uuid = uuid
        self.name = name
        self.birthDate = birthDate
        self.createdAt = createdAt
        self.breakfastMinutes = 8 * 60
        self.lunchMinutes = 12 * 60
        self.dinnerMinutes = 18 * 60
        self.bedtimeMinutes = 21 * 60
        self.mealAlarmsEnabled = true
        self.medicationAlarmsEnabled = true
    }

    func minutes(for anchor: DoseAnchor) -> Int {
        switch anchor {
        case .breakfast: return breakfastMinutes
        case .lunch: return lunchMinutes
        case .dinner: return dinnerMinutes
        case .bedtime: return bedtimeMinutes
        }
    }

    /// 만 개월 수 (생후 개월).
    func ageInMonths(asOf now: Date = .now, calendar: Calendar = .current) -> Int {
        max(0, calendar.dateComponents([.month], from: birthDate, to: now).month ?? 0)
    }
}
