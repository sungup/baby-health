import Foundation
import SwiftData

/// 투약 슬롯을 실제 시각으로 바꾸는 계산. 알람과 소급 기록(backfill)이 함께 쓴다.
enum DoseTimes {
    /// 해당 날짜(day)의 슬롯 시각. 식사 기준이면 "식사 시간 + offset", 정시면 그 시각.
    static func fireDate(
        for slot: DoseSlotValue,
        on day: Date,
        mealMinutes: (DoseAnchor) -> Int,
        calendar: Calendar = .current
    ) -> Date {
        let minutes: Int
        if let anchor = slot.anchor {
            minutes = mealMinutes(anchor) + slot.offsetMinutes
        } else {
            minutes = slot.fixedMinutes ?? 0
        }
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .minute, value: minutes, to: start) ?? start
    }

    /// start ~ now 사이에 이미 지나간 정해진 투약 시각들 (endDate 가 있으면 그 날까지).
    static func pastDoseTimes(
        slots: [DoseSlotValue],
        start: Date,
        end: Date?,
        now: Date,
        mealMinutes: (DoseAnchor) -> Int,
        calendar: Calendar = .current
    ) -> [Date] {
        guard !slots.isEmpty else { return [] }
        var result: [Date] = []
        var day = calendar.startOfDay(for: start)
        let lastDay = min(calendar.startOfDay(for: now), end.map { calendar.startOfDay(for: $0) } ?? .distantFuture)
        while day <= lastDay {
            for slot in slots {
                let time = fireDate(for: slot, on: day, mealMinutes: mealMinutes, calendar: calendar)
                if time >= start && time <= now {
                    result.append(time)
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result.sorted()
    }
}

enum MedicationBuilder {
    /// 초안 하나를 저장 가능한 Medication 으로 만들고, 선택 시 지난 투약을 복용 기록으로 채운다.
    static func make(
        from draft: MedicationDraft,
        baby: Baby,
        prescribedDate: Date,
        prescriber: String,
        startChoice: StartChoice,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> (medication: Medication, backfilled: [MedicationDose]) {
        let start = startChoice.resolve(
            prescribedDate: prescribedDate,
            schedule: draft.schedule,
            now: now,
            calendar: calendar
        )
        let medication = PrescriptionImporter.makeMedication(
            from: draft,
            prescribedDate: prescribedDate,
            start: start,
            prescriber: prescriber,
            calendar: calendar
        )
        var doses: [MedicationDose] = []
        if startChoice.backfillPastDoses {
            let times = DoseTimes.pastDoseTimes(
                slots: draft.schedule.makeSlots(),
                start: start,
                end: medication.endDate,
                now: now,
                mealMinutes: { baby.minutes(for: $0) },
                calendar: calendar
            )
            doses = times.map { MedicationDose(takenAt: $0, notes: "시작 시점 보정으로 기록") }
        }
        return (medication, doses)
    }

    /// 컨텍스트에 넣고 아기와 연결한다. (호출 쪽에서 insert 후 관계 설정)
    static func attach(
        _ built: (medication: Medication, backfilled: [MedicationDose]),
        to baby: Baby,
        insert: (any PersistentModel) -> Void
    ) {
        insert(built.medication)
        built.medication.baby = baby
        for dose in built.backfilled {
            insert(dose)
            dose.medication = built.medication
        }
    }
}
