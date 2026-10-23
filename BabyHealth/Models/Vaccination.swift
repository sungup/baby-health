import Foundation
import SwiftData

@Model
final class Vaccination {
    var name: String
    var doseNumber: Int
    var scheduledDate: Date
    var administeredDate: Date?
    var clinic: String
    var notes: String
    var baby: Baby?

    init(
        name: String,
        doseNumber: Int = 1,
        scheduledDate: Date,
        administeredDate: Date? = nil,
        clinic: String = "",
        notes: String = ""
    ) {
        self.name = name
        self.doseNumber = doseNumber
        self.scheduledDate = scheduledDate
        self.administeredDate = administeredDate
        self.clinic = clinic
        self.notes = notes
    }

    var isCompleted: Bool { administeredDate != nil }

    /// 예정일이 오늘 이전이고 아직 접종하지 않았다면 true.
    func isOverdue(asOf now: Date = .now, calendar: Calendar = .current) -> Bool {
        administeredDate == nil && scheduledDate < calendar.startOfDay(for: now)
    }
}
