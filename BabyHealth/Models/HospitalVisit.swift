import Foundation
import SwiftData

@Model
final class HospitalVisit {
    var date: Date
    var hospitalName: String
    var reason: String
    var diagnosis: String
    var notes: String
    var baby: Baby?

    init(
        date: Date,
        hospitalName: String,
        reason: String,
        diagnosis: String = "",
        notes: String = ""
    ) {
        self.date = date
        self.hospitalName = hospitalName
        self.reason = reason
        self.diagnosis = diagnosis
        self.notes = notes
    }
}
