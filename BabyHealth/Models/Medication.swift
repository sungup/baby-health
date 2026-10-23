import Foundation
import SwiftData

/// 처방받은 약 한 건. 복용 기록은 `doses` 로 쌓는다.
@Model
final class Medication {
    var name: String
    /// 1회 용량 (예: "2.5ml"). 단위가 제각각이라 문자열로 보관한다.
    var dosage: String
    var timesPerDay: Int
    var startDate: Date
    var endDate: Date?
    var reason: String
    var notes: String
    /// 처방받은 날짜.
    var prescribedDate: Date
    /// 처방한 병원/의사 (선택).
    var prescriber: String
    /// 복용 시점 메모 (예: "아침·저녁 식후 30분", "취침 전"). 약마다 다를 수 있다.
    var timingNote: String
    var baby: Baby?

    @Relationship(deleteRule: .cascade, inverse: \MedicationDose.medication)
    var doses: [MedicationDose] = []

    init(
        name: String,
        dosage: String,
        timesPerDay: Int,
        startDate: Date,
        endDate: Date? = nil,
        reason: String = "",
        notes: String = "",
        prescribedDate: Date = .now,
        prescriber: String = "",
        timingNote: String = ""
    ) {
        self.name = name
        self.dosage = dosage
        self.timesPerDay = timesPerDay
        self.startDate = startDate
        self.endDate = endDate
        self.reason = reason
        self.notes = notes
        self.prescribedDate = prescribedDate
        self.prescriber = prescriber
        self.timingNote = timingNote
    }

    func isActive(asOf now: Date = .now, calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        guard calendar.startOfDay(for: startDate) <= today else { return false }
        if let endDate {
            return calendar.startOfDay(for: endDate) >= today
        }
        return true
    }

    func doseCount(on day: Date, calendar: Calendar = .current) -> Int {
        doses.filter { calendar.isDate($0.takenAt, inSameDayAs: day) }.count
    }
}

@Model
final class MedicationDose {
    var takenAt: Date
    var notes: String
    var medication: Medication?

    init(takenAt: Date = .now, notes: String = "") {
        self.takenAt = takenAt
        self.notes = notes
    }
}
