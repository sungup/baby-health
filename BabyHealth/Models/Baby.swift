import Foundation
import SwiftData

@Model
final class Baby {
    var name: String
    var birthDate: Date
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Vaccination.baby)
    var vaccinations: [Vaccination] = []

    @Relationship(deleteRule: .cascade, inverse: \HospitalVisit.baby)
    var visits: [HospitalVisit] = []

    @Relationship(deleteRule: .cascade, inverse: \Medication.baby)
    var medications: [Medication] = []

    @Relationship(deleteRule: .cascade, inverse: \TemperatureRecord.baby)
    var temperatures: [TemperatureRecord] = []

    init(name: String, birthDate: Date, createdAt: Date = .now) {
        self.name = name
        self.birthDate = birthDate
        self.createdAt = createdAt
    }

    /// 만 개월 수 (생후 개월).
    func ageInMonths(asOf now: Date = .now, calendar: Calendar = .current) -> Int {
        max(0, calendar.dateComponents([.month], from: birthDate, to: now).month ?? 0)
    }
}
