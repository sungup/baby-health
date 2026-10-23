import XCTest
@testable import BabyHealth

private var cal: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return calendar
}

private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

final class MinuteOfDayTests: XCTestCase {
    func testStringFormatsAndWraps() {
        XCTAssertEqual(MinuteOfDay.string(from: 8 * 60 + 5), "08:05")
        XCTAssertEqual(MinuteOfDay.string(from: 1440 + 30), "00:30")
        XCTAssertEqual(MinuteOfDay.string(from: -30), "23:30")
    }

    func testRoundedUpToTenMinutes() {
        XCTAssertEqual(MinuteOfDay.roundedUpMinutes(from: at(23, 14, 3), calendar: cal), 14 * 60 + 10)
        XCTAssertEqual(MinuteOfDay.roundedUpMinutes(from: at(23, 14, 10), calendar: cal), 14 * 60 + 10)
        XCTAssertEqual(MinuteOfDay.roundedUpMinutes(from: at(23, 23, 55), calendar: cal), 0)
    }
}

final class TimingInterpreterTests: XCTestCase {
    private func interpret(_ timing: String?, _ count: Int? = nil, interval: Int? = nil) -> DoseScheduleDraft {
        TimingInterpreter.interpret(timing: timing, timesPerDay: count, intervalHours: interval, now: at(23, 14, 3), calendar: cal)
    }

    func testMealsWithRelation() {
        let draft = interpret("아침·저녁 식후 30분", 2)
        XCTAssertEqual(draft.mode, .meal)
        XCTAssertEqual(draft.makeSlots().map(\.label), ["아침 식후 30분", "저녁 식후 30분"])
    }

    func testSeparateSegmentsKeepOwnRelation() {
        let draft = interpret("아침 식전 20분, 저녁 식후 40분, 취침 전", 3)
        XCTAssertEqual(draft.makeSlots().map(\.label), ["아침 식전 20분", "저녁 식후 40분", "취침 30분 전"])
    }

    func testGenericRelationUsesDefaultMealsByCount() {
        XCTAssertEqual(interpret("식후 30분", 3).makeSlots().count, 3)
        XCTAssertEqual(interpret("식후 30분", 2).makeSlots().map(\.label), ["아침 식후 30분", "저녁 식후 30분"])
    }

    func testBetweenMealsDefaultsToTwoHoursAfter() {
        XCTAssertEqual(interpret("점심 식간", 1).makeSlots().map(\.label), ["점심 식후 120분"])
    }

    func testAsNeededHasNoSlots() {
        let draft = interpret("필요 시", nil)
        XCTAssertEqual(draft.mode, .asNeeded)
        XCTAssertTrue(draft.makeSlots().isEmpty)
    }

    func testNoAnchorFallsBackToFixedWithFirstDoseDefaultNow() {
        let draft = interpret(nil, 3)
        XCTAssertEqual(draft.mode, .fixed)
        XCTAssertEqual(draft.firstDoseMinutes, 14 * 60 + 10)
        XCTAssertEqual(draft.intervalHours, 8)
        XCTAssertEqual(draft.makeSlots().map(\.label), ["14:10", "22:10", "06:10"].sorted())
    }

    func testIntervalOnlyDerivesTimesPerDay() {
        let draft = interpret(nil, nil, interval: 6)
        XCTAssertEqual(draft.mode, .fixed)
        XCTAssertEqual(draft.timesPerDay, 4)
    }
}

final class StartChoiceTests: XCTestCase {
    func testMealModeUsesDays() {
        let schedule = DoseScheduleDraft()
        var choice = StartChoice()
        let now = at(23, 15)

        choice.kind = .prescribedDay
        XCTAssertEqual(choice.resolve(prescribedDate: at(20, 11), schedule: schedule, now: now, calendar: cal), at(20, 0))
        choice.kind = .today
        XCTAssertEqual(choice.resolve(prescribedDate: at(20, 11), schedule: schedule, now: now, calendar: cal), at(23, 0))
    }

    func testFixedModeAddsFirstDoseTime() {
        var schedule = DoseScheduleDraft()
        schedule.mode = .fixed
        schedule.firstDoseMinutes = 9 * 60 + 30
        var choice = StartChoice()
        choice.kind = .today
        XCTAssertEqual(choice.resolve(prescribedDate: at(20, 0), schedule: schedule, now: at(23, 15), calendar: cal), at(23, 9, 30))
    }

    func testEndDateFollowsActualStart() {
        var draft = MedicationDraft(now: at(23, 15), calendar: cal)
        draft.name = "A"
        draft.dosage = "1정"
        draft.daysText = "3"
        let baby = Baby(name: "테스트", birthDate: at(1, 0))
        var choice = StartChoice()
        choice.kind = .today
        let built = MedicationBuilder.make(
            from: draft, baby: baby, prescribedDate: at(20, 0), prescriber: "",
            startChoice: choice, now: at(23, 15), calendar: cal
        )
        // 23일 시작 + 3일 → 25일까지
        XCTAssertEqual(cal.component(.day, from: built.medication.endDate!), 25)
    }

    func testBackfillRecordsOnlyPastDoses() {
        let baby = Baby(name: "테스트", birthDate: at(1, 0)) // 아침 08:00, 점심 12:00, 저녁 18:00
        var draft = MedicationDraft(now: at(23, 15), calendar: cal)
        draft.name = "A"
        draft.dosage = "1정"
        draft.daysText = "5"
        var choice = StartChoice()
        choice.kind = .custom
        choice.customStart = at(22, 0)
        choice.backfillPastDoses = true

        let built = MedicationBuilder.make(
            from: draft, baby: baby, prescribedDate: at(23, 0), prescriber: "",
            startChoice: choice, now: at(23, 13), calendar: cal
        )
        // 22일 3회 + 23일 아침/점심(13시 기준 08:30, 12:30 지남) = 5건
        XCTAssertEqual(built.backfilled.count, 5)
    }

    func testNoBackfillByDefault() {
        let baby = Baby(name: "테스트", birthDate: at(1, 0))
        var draft = MedicationDraft(now: at(23, 15), calendar: cal)
        draft.name = "A"
        draft.dosage = "1정"
        let built = MedicationBuilder.make(
            from: draft, baby: baby, prescribedDate: at(20, 0), prescriber: "",
            startChoice: StartChoice(), now: at(23, 15), calendar: cal
        )
        XCTAssertTrue(built.backfilled.isEmpty)
    }
}

final class AlarmPlannerTests: XCTestCase {
    private let babyID = UUID()

    private func input(
        meds: [AlarmMedicationInput],
        meal: Bool = true,
        medication: Bool = true
    ) -> AlarmBabyInput {
        AlarmBabyInput(
            id: babyID, name: "아기",
            breakfastMinutes: 480, lunchMinutes: 720, dinnerMinutes: 1080, bedtimeMinutes: 1260,
            mealAlarmsEnabled: meal, medicationAlarmsEnabled: medication, medications: meds
        )
    }

    private func med(
        _ name: String,
        start: Date,
        end: Date?,
        slots: [DoseSlotValue]
    ) -> AlarmMedicationInput {
        AlarmMedicationInput(name: name, dosage: "5ml", start: start, end: end, slots: slots)
    }

    private let afterBreakfast = DoseSlotValue(anchor: .breakfast, offsetMinutes: 30, fixedMinutes: nil)
    private let afterDinner = DoseSlotValue(anchor: .dinner, offsetMinutes: 30, fixedMinutes: nil)

    func testAlarmsOnlyWithinDosingPeriod() {
        let plan = AlarmPlanner.plan(
            inputs: [input(meds: [med("A", start: at(24, 0), end: at(25, 0), slots: [afterBreakfast])])],
            from: at(23, 7), horizonDays: 7, calendar: cal
        )
        let days = Set(plan.map { cal.component(.day, from: $0.fireDate) })
        XCTAssertEqual(days, [24, 25])
    }

    func testMedicationAlarmListsMedsAndNext() {
        let plan = AlarmPlanner.plan(
            inputs: [input(meds: [
                med("A", start: at(23, 0), end: at(24, 0), slots: [afterBreakfast, afterDinner]),
                med("B", start: at(23, 0), end: at(24, 0), slots: [afterBreakfast])
            ])],
            from: at(23, 0), horizonDays: 1, calendar: cal
        )
        let breakfast = plan.first { $0.kind == .medication }!
        XCTAssertEqual(breakfast.fireDate, at(23, 8, 30))
        XCTAssertTrue(breakfast.title.contains("아침 식후 30분"))
        XCTAssertTrue(breakfast.body.contains("• A 5ml"))
        XCTAssertTrue(breakfast.body.contains("• B 5ml"))
        XCTAssertTrue(breakfast.body.contains("▶ 다음 18:30 A"))
    }

    func testMealAlarmMergesIntoMedicationAlarmAtSameTime() {
        let atMeal = DoseSlotValue(anchor: .breakfast, offsetMinutes: 0, fixedMinutes: nil)
        let plan = AlarmPlanner.plan(
            inputs: [input(meds: [med("A", start: at(23, 0), end: at(23, 0), slots: [atMeal])])],
            from: at(23, 0), horizonDays: 1, calendar: cal
        )
        let at8 = plan.filter { $0.fireDate == at(23, 8) }
        XCTAssertEqual(at8.count, 1)
        XCTAssertEqual(at8.first?.kind, .medication)
        XCTAssertTrue(at8.first!.body.contains("아침 식사 시간"))
    }

    func testMealAlarmListsRelatedMedication() {
        let plan = AlarmPlanner.plan(
            inputs: [input(meds: [med("A", start: at(23, 0), end: at(23, 0), slots: [afterBreakfast])])],
            from: at(23, 0), horizonDays: 1, calendar: cal
        )
        let meal = plan.first { $0.kind == .meal && $0.fireDate == at(23, 8) }!
        XCTAssertTrue(meal.body.contains("• A 5ml (아침 식후 30분)"))
    }

    func testNoAlarmsWithoutActiveMedication() {
        let plan = AlarmPlanner.plan(inputs: [input(meds: [])], from: at(23, 0), horizonDays: 3, calendar: cal)
        XCTAssertTrue(plan.isEmpty)
    }

    func testAsNeededMedicationProducesNoAlarms() {
        let plan = AlarmPlanner.plan(
            inputs: [input(meds: [med("A", start: at(23, 0), end: nil, slots: [])])],
            from: at(23, 0), horizonDays: 3, calendar: cal
        )
        XCTAssertTrue(plan.isEmpty)
    }

    func testFixedSlotsSkipTimesBeforeFirstDose() {
        let fixed = [660, 1140].map { DoseSlotValue(anchor: nil, offsetMinutes: 0, fixedMinutes: $0) } // 11:00, 19:00
        let plan = AlarmPlanner.plan(
            inputs: [input(meds: [med("A", start: at(23, 15), end: at(23, 0), slots: fixed)], meal: false)],
            from: at(23, 0), horizonDays: 1, calendar: cal
        )
        XCTAssertEqual(plan.map(\.fireDate), [at(23, 19)])
    }

    func testTogglesDisableAlarms() {
        let meds = [med("A", start: at(23, 0), end: at(23, 0), slots: [afterBreakfast])]
        let noMeal = AlarmPlanner.plan(inputs: [input(meds: meds, meal: false)], from: at(23, 0), horizonDays: 1, calendar: cal)
        XCTAssertTrue(noMeal.allSatisfy { $0.kind == .medication })
        let noMed = AlarmPlanner.plan(inputs: [input(meds: meds, medication: false)], from: at(23, 0), horizonDays: 1, calendar: cal)
        XCTAssertTrue(noMed.allSatisfy { $0.kind == .meal })
    }

    func testLimitKeepsNearestAlarms() {
        let meds = [med("A", start: at(1, 0), end: nil, slots: [afterBreakfast, afterDinner])]
        let plan = AlarmPlanner.plan(inputs: [input(meds: meds)], from: at(23, 0), horizonDays: 14, limit: 10, calendar: cal)
        XCTAssertEqual(plan.count, 10)
        XCTAssertEqual(plan.map(\.fireDate), plan.map(\.fireDate).sorted())
    }

    func testShareTextContainsTitleAndBody() {
        let plan = AlarmPlanner.plan(
            inputs: [input(meds: [med("A", start: at(23, 0), end: at(23, 0), slots: [afterBreakfast])], meal: false)],
            from: at(23, 0), horizonDays: 1, calendar: cal
        )
        XCTAssertEqual(plan[0].shareText, plan[0].title + "\n" + plan[0].body)
    }
}
