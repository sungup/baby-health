import Foundation

// MARK: - 입력 (값 타입 스냅샷)

struct AlarmMedicationInput: Equatable {
    let name: String
    let dosage: String
    /// 실제 투약 시작 시점 (시각 포함).
    let start: Date
    let end: Date?
    let slots: [DoseSlotValue]
}

struct AlarmBabyInput: Equatable {
    let id: UUID
    let name: String
    let breakfastMinutes: Int
    let lunchMinutes: Int
    let dinnerMinutes: Int
    let bedtimeMinutes: Int
    let mealAlarmsEnabled: Bool
    let medicationAlarmsEnabled: Bool
    let medications: [AlarmMedicationInput]

    func minutes(for anchor: DoseAnchor) -> Int {
        switch anchor {
        case .breakfast: return breakfastMinutes
        case .lunch: return lunchMinutes
        case .dinner: return dinnerMinutes
        case .bedtime: return bedtimeMinutes
        }
    }
}

extension AlarmBabyInput {
    init(baby: Baby) {
        self.init(
            id: baby.uuid,
            name: baby.name,
            breakfastMinutes: baby.breakfastMinutes,
            lunchMinutes: baby.lunchMinutes,
            dinnerMinutes: baby.dinnerMinutes,
            bedtimeMinutes: baby.bedtimeMinutes,
            mealAlarmsEnabled: baby.mealAlarmsEnabled,
            medicationAlarmsEnabled: baby.medicationAlarmsEnabled,
            medications: baby.medications
                .sorted { $0.name < $1.name }
                .map {
                    AlarmMedicationInput(
                        name: $0.name,
                        dosage: $0.dosage,
                        start: $0.startDate,
                        end: $0.endDate,
                        slots: $0.slots.map(\.value).sorted { lhs, rhs in lhs.sortKey < rhs.sortKey }
                    )
                }
        )
    }
}

private extension DoseSlotValue {
    var sortKey: Int {
        if let anchor { return (DoseAnchor.allCases.firstIndex(of: anchor) ?? 0) * 10_000 + offsetMinutes + 5_000 }
        return 100_000 + (fixedMinutes ?? 0)
    }
}

// MARK: - 계산 결과

struct PlannedAlarm: Equatable, Identifiable {
    enum Kind: String { case medication, meal }

    let id: String
    let babyID: UUID
    let kind: Kind
    let fireDate: Date
    let title: String
    let body: String

    /// 제3의 앱에 공유할 텍스트.
    var shareText: String { title + "\n" + body }
}

// MARK: - 알람 계산 (순수 함수)

enum AlarmPlanner {
    static let defaultHorizonDays = 14
    /// iOS 는 앱당 예약 알림을 64개로 제한한다.
    static let defaultLimit = 60

    /// - Parameters:
    ///   - from: 이 시각 이후(포함) 알람만 만든다. 오늘 일정 표시용으로 자정을 줄 수도 있다.
    static func plan(
        inputs: [AlarmBabyInput],
        from: Date,
        horizonDays: Int = defaultHorizonDays,
        limit: Int = defaultLimit,
        calendar: Calendar = .current
    ) -> [PlannedAlarm] {
        var all: [PlannedAlarm] = []
        for input in inputs {
            all.append(contentsOf: plan(for: input, from: from, horizonDays: horizonDays, calendar: calendar))
        }
        all.sort { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
        return Array(all.prefix(limit))
    }

    static func plan(
        for input: AlarmBabyInput,
        from: Date,
        horizonDays: Int,
        calendar: Calendar = .current
    ) -> [PlannedAlarm] {
        struct Entry {
            let medication: AlarmMedicationInput
            let slot: DoseSlotValue
        }

        let firstDay = calendar.startOfDay(for: from)
        // (fireDate) → 같은 시각에 울릴 약들
        var medicationGroups: [(fire: Date, entries: [Entry])] = []
        var mealTimes: [(fire: Date, anchor: DoseAnchor, related: [Entry])] = []

        for offset in 0..<max(horizonDays, 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else { continue }

            // 이 날 복용 기간에 걸친 약만 (복용일 동안에만 알람)
            let activeToday = input.medications.filter { med in
                !med.slots.isEmpty
                    && calendar.startOfDay(for: med.start) <= day
                    && (med.end.map { calendar.startOfDay(for: $0) >= day } ?? true)
            }
            guard !activeToday.isEmpty else { continue }

            if input.medicationAlarmsEnabled {
                var dayGroups: [Date: [Entry]] = [:]
                for med in activeToday {
                    for slot in med.slots {
                        let fire = DoseTimes.fireDate(
                            for: slot, on: day, mealMinutes: { input.minutes(for: $0) }, calendar: calendar
                        )
                        guard fire >= med.start, fire >= from else { continue }
                        dayGroups[fire, default: []].append(Entry(medication: med, slot: slot))
                    }
                }
                for (fire, entries) in dayGroups {
                    medicationGroups.append((fire, entries))
                }
            }

            if input.mealAlarmsEnabled {
                for anchor in DoseAnchor.allCases where anchor.isMeal {
                    let fire = DoseTimes.fireDate(
                        for: DoseSlotValue(anchor: anchor, offsetMinutes: 0, fixedMinutes: nil),
                        on: day, mealMinutes: { input.minutes(for: $0) }, calendar: calendar
                    )
                    guard fire >= from else { continue }
                    let related = activeToday.flatMap { med in
                        med.slots.filter { $0.anchor == anchor }.map { Entry(medication: med, slot: $0) }
                    }
                    mealTimes.append((fire, anchor, related))
                }
            }
        }

        medicationGroups.sort { $0.fire < $1.fire }

        var alarms: [PlannedAlarm] = []
        let mealByFire = Dictionary(mealTimes.map { ($0.fire, $0.anchor) }, uniquingKeysWith: { first, _ in first })

        for (index, group) in medicationGroups.enumerated() {
            var lines = group.entries.map { entry in
                bullet(entry.medication)
            }
            lines = unique(lines)

            var labels = unique(group.entries.map { $0.slot.label })
            labels.sort()

            // 같은 시각의 식사 알람은 투약 알람에 합친다.
            var prefix: [String] = []
            if let anchor = mealByFire[group.fire] {
                prefix.append("🍚 \(anchor.label) 식사 시간입니다.")
            }

            var bodyLines = prefix + lines
            if index + 1 < medicationGroups.count {
                let next = medicationGroups[index + 1]
                bodyLines.append(nextLine(next.fire, names: unique(next.entries.map { $0.medication.name }), after: group.fire, calendar: calendar))
            }

            alarms.append(PlannedAlarm(
                id: "alarm-\(input.id.uuidString)-\(Int(group.fire.timeIntervalSince1970))-med",
                babyID: input.id,
                kind: .medication,
                fireDate: group.fire,
                title: "💊 \(input.name) 투약 · \(labels.joined(separator: ", ")) (\(clock(group.fire, calendar)))",
                body: bodyLines.joined(separator: "\n")
            ))
        }

        let medicationFires = Set(medicationGroups.map(\.fire))
        for meal in mealTimes where !medicationFires.contains(meal.fire) {
            let body: String
            if meal.related.isEmpty {
                body = "복용 중인 약이 있는 기간입니다. 식사 시간이에요."
            } else {
                let lines = unique(meal.related.map { "• \($0.medication.name)\(dose($0.medication)) (\($0.slot.label))" })
                body = "이 식사와 관련된 투약:\n" + lines.joined(separator: "\n")
            }
            alarms.append(PlannedAlarm(
                id: "alarm-\(input.id.uuidString)-\(Int(meal.fire.timeIntervalSince1970))-meal",
                babyID: input.id,
                kind: .meal,
                fireDate: meal.fire,
                title: "🍚 \(input.name) \(meal.anchor.label) 시간 (\(clock(meal.fire, calendar)))",
                body: body
            ))
        }

        return alarms.sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
    }

    // MARK: 문구 도우미

    private static func dose(_ med: AlarmMedicationInput) -> String {
        med.dosage.isEmpty ? "" : " \(med.dosage)"
    }

    private static func bullet(_ med: AlarmMedicationInput) -> String {
        "• \(med.name)\(dose(med))"
    }

    private static func clock(_ date: Date, _ calendar: Calendar) -> String {
        MinuteOfDay.string(from: MinuteOfDay.minutes(from: date, calendar: calendar))
    }

    private static func nextLine(_ next: Date, names: [String], after current: Date, calendar: Calendar) -> String {
        let dayPrefix: String
        if calendar.isDate(next, inSameDayAs: current) {
            dayPrefix = ""
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: current), calendar.isDate(next, inSameDayAs: tomorrow) {
            dayPrefix = "내일 "
        } else {
            let parts = calendar.dateComponents([.month, .day], from: next)
            dayPrefix = "\(parts.month ?? 0)/\(parts.day ?? 0) "
        }
        return "▶ 다음 \(dayPrefix)\(clock(next, calendar)) \(names.joined(separator: ", "))"
    }

    private static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }
}
