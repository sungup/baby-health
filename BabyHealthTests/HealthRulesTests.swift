import XCTest
@testable import BabyHealth

final class HealthRulesTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func snapshot(
        now: Date,
        vaccinations: [HealthSnapshot.Vaccine] = [],
        temperatures: [HealthSnapshot.Temperature] = [],
        medications: [HealthSnapshot.Medicine] = []
    ) -> HealthSnapshot {
        HealthSnapshot(
            generatedAt: now,
            ageInMonths: 4,
            vaccinations: vaccinations,
            temperatures: temperatures,
            visits: [],
            medications: medications
        )
    }

    func testOverdueVaccineProducesWarning() {
        let now = date(2026, 10, 23)
        let result = HealthRules.findings(
            for: snapshot(
                now: now,
                vaccinations: [
                    .init(name: "DTaP", doseNumber: 2, scheduledDate: date(2026, 10, 20), administeredDate: nil)
                ]
            ),
            calendar: calendar
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.severity, .warning)
        XCTAssertTrue(result.first?.message.contains("DTaP") ?? false)
    }

    func testAdministeredVaccineProducesNoFinding() {
        let now = date(2026, 10, 23)
        let result = HealthRules.findings(
            for: snapshot(
                now: now,
                vaccinations: [
                    .init(
                        name: "BCG",
                        doseNumber: 1,
                        scheduledDate: date(2026, 10, 1),
                        administeredDate: date(2026, 10, 2)
                    )
                ]
            ),
            calendar: calendar
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testRecentFeverProducesAlert() {
        let now = date(2026, 10, 23)
        let result = HealthRules.findings(
            for: snapshot(
                now: now,
                temperatures: [
                    .init(measuredAt: now.addingTimeInterval(-3600), celsius: 38.4, method: .ear)
                ]
            ),
            calendar: calendar
        )

        XCTAssertEqual(result.first?.severity, .alert)
    }

    func testOldFeverIsIgnored() {
        let now = date(2026, 10, 23)
        let result = HealthRules.findings(
            for: snapshot(
                now: now,
                temperatures: [
                    .init(measuredAt: now.addingTimeInterval(-3 * 24 * 3600), celsius: 38.9, method: .ear)
                ]
            ),
            calendar: calendar
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testMissingDosesProduceInfo() {
        let now = date(2026, 10, 23)
        let result = HealthRules.findings(
            for: snapshot(
                now: now,
                medications: [
                    .init(
                        name: "해열제",
                        dosage: "2.5ml",
                        timesPerDay: 3,
                        startDate: date(2026, 10, 22),
                        endDate: nil,
                        dosesTakenToday: 1
                    )
                ]
            ),
            calendar: calendar
        )

        XCTAssertEqual(result.first?.severity, .info)
        XCTAssertTrue(result.first?.message.contains("1/3") ?? false)
    }

    func testFindingsAreSortedBySeverity() {
        let now = date(2026, 10, 23)
        let result = HealthRules.findings(
            for: snapshot(
                now: now,
                vaccinations: [
                    .init(name: "DTaP", doseNumber: 1, scheduledDate: date(2026, 10, 1), administeredDate: nil)
                ],
                temperatures: [
                    .init(measuredAt: now.addingTimeInterval(-600), celsius: 39.0, method: .rectal)
                ]
            ),
            calendar: calendar
        )

        XCTAssertEqual(result.map(\.severity), [.alert, .warning])
    }
}
