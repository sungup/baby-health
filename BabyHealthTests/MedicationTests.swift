import XCTest
@testable import BabyHealth

final class MedicationTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func makeMedication(start: Date, end: Date? = nil) -> Medication {
        Medication(name: "해열제", dosage: "2.5ml", timesPerDay: 3, startDate: start, endDate: end)
    }

    func testIsActiveBetweenStartAndEnd() {
        let medication = makeMedication(start: date(2026, 10, 20), end: date(2026, 10, 25))

        XCTAssertTrue(medication.isActive(asOf: date(2026, 10, 23), calendar: calendar))
        XCTAssertTrue(medication.isActive(asOf: date(2026, 10, 25, 23), calendar: calendar))
    }

    func testIsNotActiveBeforeStartOrAfterEnd() {
        let medication = makeMedication(start: date(2026, 10, 20), end: date(2026, 10, 25))

        XCTAssertFalse(medication.isActive(asOf: date(2026, 10, 19), calendar: calendar))
        XCTAssertFalse(medication.isActive(asOf: date(2026, 10, 26), calendar: calendar))
    }

    func testIsActiveWithoutEndDate() {
        let medication = makeMedication(start: date(2026, 10, 20))

        XCTAssertTrue(medication.isActive(asOf: date(2026, 12, 1), calendar: calendar))
    }

    func testDoseCountOnlyCountsTheGivenDay() {
        let medication = makeMedication(start: date(2026, 10, 20))
        medication.doses = [
            MedicationDose(takenAt: date(2026, 10, 23, 8)),
            MedicationDose(takenAt: date(2026, 10, 23, 14)),
            MedicationDose(takenAt: date(2026, 10, 22, 20))
        ]

        XCTAssertEqual(medication.doseCount(on: date(2026, 10, 23), calendar: calendar), 2)
        XCTAssertEqual(medication.doseCount(on: date(2026, 10, 22), calendar: calendar), 1)
        XCTAssertEqual(medication.doseCount(on: date(2026, 10, 21), calendar: calendar), 0)
    }

    func testFeverThresholdFlag() {
        XCTAssertTrue(TemperatureRecord(celsius: 38.0).isFever)
        XCTAssertFalse(TemperatureRecord(celsius: 37.9).isFever)
    }
}
