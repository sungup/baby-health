import SwiftUI

/// 약 하나의 하루 복용 스케줄 편집. Form 안에서 Section 내용으로 쓴다.
struct DoseScheduleEditor: View {
    @Binding var schedule: DoseScheduleDraft

    var body: some View {
        Picker("복용 방식", selection: $schedule.mode) {
            ForEach(DoseScheduleDraft.Mode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)

        switch schedule.mode {
        case .meal:
            mealEditor
        case .fixed:
            fixedEditor
        case .asNeeded:
            Text("필요할 때만 복용하는 약이라 알람이 울리지 않습니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 식사 기준

    @ViewBuilder
    private var mealEditor: some View {
        ForEach($schedule.mealSlots) { $slot in
            HStack {
                Text(slot.anchor.label)
                    .frame(width: 44, alignment: .leading)
                Picker("기준", selection: $slot.relation) {
                    ForEach(MealSlotDraft.Relation.allCases) { relation in
                        Text(relation.label(for: slot.anchor)).tag(relation)
                    }
                }
                .labelsHidden()
                if slot.relation != .at {
                    Stepper("\(slot.minutes)분", value: $slot.minutes, in: 5...240, step: 5)
                }
            }
        }
        .onDelete { offsets in
            schedule.mealSlots.remove(atOffsets: offsets)
        }

        let remaining = DoseAnchor.allCases.filter { anchor in
            !schedule.mealSlots.contains(where: { $0.anchor == anchor })
        }
        if !remaining.isEmpty {
            Menu {
                ForEach(remaining) { anchor in
                    Button(anchor.label) {
                        let relation: MealSlotDraft.Relation = anchor == .bedtime ? .before : .after
                        schedule.mealSlots.append(MealSlotDraft(anchor: anchor, relation: relation, minutes: 30))
                        schedule.mealSlots.sort {
                            (DoseAnchor.allCases.firstIndex(of: $0.anchor) ?? 0)
                                < (DoseAnchor.allCases.firstIndex(of: $1.anchor) ?? 0)
                        }
                    }
                }
            } label: {
                Label("복용 시점 추가", systemImage: "plus.circle")
            }
        }

        if schedule.mealSlots.isEmpty {
            Text("복용 시점을 하나 이상 추가해 주세요.")
                .font(.footnote)
                .foregroundStyle(.red)
        } else {
            Text("식사 시간은 아기 설정(알람 설정)의 시간을 기준으로 합니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 시각 지정 (식사 기준 없음)

    @ViewBuilder
    private var fixedEditor: some View {
        Label("처방전에 식사 기준이 없어 최초 투약 시간이 필요합니다.", systemImage: "clock.badge.exclamationmark")
            .font(.footnote)
            .foregroundStyle(.orange)

        DatePicker(
            "최초 투약 시간",
            selection: Binding(
                get: { MinuteOfDay.date(for: schedule.firstDoseMinutes) },
                set: { schedule.firstDoseMinutes = MinuteOfDay.minutes(from: $0) }
            ),
            displayedComponents: .hourAndMinute
        )
        Stepper("\(schedule.intervalHours)시간 간격", value: $schedule.intervalHours, in: 1...24)
        Stepper("하루 \(schedule.fixedTimesPerDay)회", value: $schedule.fixedTimesPerDay, in: 1...8)

        Text("투약 시각: " + schedule.makeSlots().map(\.label).joined(separator: ", "))
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

/// 언제부터 투약했는지 고르는 보정 선택기.
struct StartChoiceEditor: View {
    @Binding var choice: StartChoice
    let prescribedDate: Date
    var now: Date = .now

    private var prescribedIsPast: Bool {
        Calendar.current.startOfDay(for: prescribedDate) < Calendar.current.startOfDay(for: now)
    }

    var body: some View {
        Picker("투약 시작", selection: $choice.kind) {
            ForEach(StartChoice.Kind.allCases) { kind in
                Text(kind.label).tag(kind)
            }
        }
        .pickerStyle(.segmented)

        if choice.kind == .custom {
            DatePicker("시작 일시", selection: $choice.customStart, in: ...Date.now)
        }

        if prescribedIsPast {
            Label("처방일이 오늘보다 앞섭니다. 실제로 투약을 시작한 때를 골라 주세요.", systemImage: "calendar.badge.exclamationmark")
                .font(.footnote)
                .foregroundStyle(.orange)
        }

        Toggle("지난 정해진 투약을 복용한 것으로 기록", isOn: $choice.backfillPastDoses)
        Text("끄면 지금부터의 알람만 울리고 복용 기록은 직접 입력합니다. 종료일은 실제 시작일 기준으로 계산됩니다.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
