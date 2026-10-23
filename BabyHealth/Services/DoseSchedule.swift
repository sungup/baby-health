import Foundation

// MARK: - 식사 기준 슬롯 (편집용)

struct MealSlotDraft: Identifiable, Equatable {
    enum Relation: String, CaseIterable, Identifiable {
        case before
        case after
        case at

        var id: String { rawValue }

        func label(for anchor: DoseAnchor) -> String {
            if anchor == .bedtime {
                switch self {
                case .before: return "취침 전"
                case .after: return "취침 후"
                case .at: return "취침 시"
                }
            }
            switch self {
            case .before: return "식전"
            case .after: return "식후"
            case .at: return "식사 때"
            }
        }
    }

    var id = UUID()
    var anchor: DoseAnchor
    var relation: Relation
    /// 식전/식후 분 (relation == .at 이면 무시)
    var minutes: Int

    var signedOffset: Int {
        switch relation {
        case .before: return -minutes
        case .after: return minutes
        case .at: return 0
        }
    }

    var value: DoseSlotValue {
        DoseSlotValue(anchor: anchor, offsetMinutes: signedOffset, fixedMinutes: nil)
    }
}

// MARK: - 복용 스케줄 초안

/// 한 약의 하루 복용 스케줄 편집 상태.
/// - meal: 식사/취침 시간을 기준으로 (식전/식후 N분)
/// - fixed: 식사 기준이 없을 때. 최초 투약 시간 + 간격으로 정시 알람
/// - asNeeded: 필요할 때만 복용. 알람 없음
struct DoseScheduleDraft: Equatable {
    enum Mode: String, CaseIterable, Identifiable {
        case meal
        case fixed
        case asNeeded

        var id: String { rawValue }

        var label: String {
            switch self {
            case .meal: return "식사 기준"
            case .fixed: return "시각 지정"
            case .asNeeded: return "필요 시"
            }
        }
    }

    var mode: Mode = .meal
    var mealSlots: [MealSlotDraft] = DoseScheduleDraft.defaultMealSlots
    /// 최초 투약 시간 (fixed 모드, 자정 기준 분)
    var firstDoseMinutes: Int = 8 * 60
    var intervalHours: Int = 8
    var fixedTimesPerDay: Int = 3

    static var defaultMealSlots: [MealSlotDraft] {
        [DoseAnchor.breakfast, .lunch, .dinner].map {
            MealSlotDraft(anchor: $0, relation: .after, minutes: 30)
        }
    }

    var timesPerDay: Int {
        switch mode {
        case .meal: return min(max(mealSlots.count, 1), 8)
        case .fixed: return min(max(fixedTimesPerDay, 1), 8)
        case .asNeeded: return 1
        }
    }

    /// 저장 가능한 상태인지 (식사 기준인데 슬롯이 없으면 불가)
    var isValid: Bool {
        mode != .meal || !mealSlots.isEmpty
    }

    /// 알람 계산에 쓰는 슬롯 목록.
    func makeSlots() -> [DoseSlotValue] {
        switch mode {
        case .meal:
            return mealSlots
                .sorted { Self.order($0.anchor) < Self.order($1.anchor) }
                .map(\.value)
        case .fixed:
            let interval = max(intervalHours, 1) * 60
            let times = (0..<timesPerDay).map { (firstDoseMinutes + $0 * interval) % 1440 }
            return Array(Set(times)).sorted().map {
                DoseSlotValue(anchor: nil, offsetMinutes: 0, fixedMinutes: $0)
            }
        case .asNeeded:
            return []
        }
    }

    /// 사람이 읽는 한 줄 요약. (복용 시점 메모가 비어 있을 때 대신 쓴다)
    var summary: String {
        switch mode {
        case .meal:
            return makeSlots().map(\.label).joined(separator: ", ")
        case .fixed:
            return "\(MinuteOfDay.string(from: firstDoseMinutes)) 시작, \(intervalHours)시간 간격, 하루 \(timesPerDay)회"
        case .asNeeded:
            return "필요 시 복용"
        }
    }

    /// fixed 모드는 최초 투약 시간을 시작 시각으로 쓴다. 그 외에는 받은 값을 그대로 쓴다.
    func startDateTime(onDayOf date: Date, calendar: Calendar = .current) -> Date {
        guard mode == .fixed else { return date }
        let day = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .minute, value: firstDoseMinutes, to: day) ?? day
    }

    private static func order(_ anchor: DoseAnchor) -> Int {
        DoseAnchor.allCases.firstIndex(of: anchor) ?? 0
    }
}

// MARK: - 투약 시작 시점 보정

/// 처방전을 등록한 시점이 실제 첫 투약보다 늦을 수 있어, 언제부터 투약했는지 고르게 한다.
struct StartChoice: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case prescribedDay
        case today
        case custom

        var id: String { rawValue }

        var label: String {
            switch self {
            case .prescribedDay: return "처방일부터"
            case .today: return "오늘부터"
            case .custom: return "직접 선택"
            }
        }
    }

    var kind: Kind = .prescribedDay
    var customStart: Date = .now
    /// 시작 시점부터 지금까지 지난 정해진 투약을 복용한 것으로 기록할지
    var backfillPastDoses = false

    /// 실제 투약 시작 시점. (식사 기준이면 날짜/시각 그대로, 시각 지정이면 날짜에 최초 투약 시간을 합친다)
    func resolve(
        prescribedDate: Date,
        schedule: DoseScheduleDraft,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date {
        switch kind {
        case .prescribedDay:
            return schedule.startDateTime(onDayOf: calendar.startOfDay(for: prescribedDate), calendar: calendar)
        case .today:
            return schedule.startDateTime(onDayOf: calendar.startOfDay(for: now), calendar: calendar)
        case .custom:
            return schedule.startDateTime(onDayOf: customStart, calendar: calendar)
        }
    }
}

// MARK: - 복용 시점 문구 해석

/// "아침·저녁 식후 30분, 취침 전" 같은 처방전 문구를 스케줄 초안으로 바꾼다.
/// 식사/취침 기준을 찾지 못하면 시각 지정(fixed) 모드가 되어 최초 투약 시간을 입력받는다.
enum TimingInterpreter {
    static func interpret(
        timing: String?,
        timesPerDay: Int?,
        intervalHours: Int?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> DoseScheduleDraft {
        let text = (timing ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let count = min(max(timesPerDay ?? 0, 0), 8)

        var draft = DoseScheduleDraft()
        draft.firstDoseMinutes = MinuteOfDay.roundedUpMinutes(from: now, calendar: calendar)

        if isAsNeeded(text) {
            draft.mode = .asNeeded
            draft.mealSlots = []
            return draft
        }

        let slots = mealSlots(from: text, expectedCount: count)
        if !slots.isEmpty {
            draft.mode = .meal
            draft.mealSlots = slots
            return draft
        }

        // 식사 기준이 없다 → 최초 투약 시간 + 간격
        var perDay = count
        var interval = max(intervalHours ?? 0, 0)
        if perDay == 0 {
            perDay = interval > 0 ? max(24 / interval, 1) : 1
        }
        if interval == 0 {
            interval = max(24 / perDay, 1)
        }
        draft.mode = .fixed
        draft.mealSlots = []
        draft.fixedTimesPerDay = perDay
        draft.intervalHours = interval
        return draft
    }

    // MARK: 내부

    private static func isAsNeeded(_ text: String) -> Bool {
        let keywords = ["필요 시", "필요시", "필요할 때", "증상 시", "증상시", "열이 날 때", "열날 때", "PRN", "prn"]
        return keywords.contains { text.contains($0) }
    }

    private static func mealSlots(from text: String, expectedCount: Int) -> [MealSlotDraft] {
        guard !text.isEmpty else { return [] }

        let normalized = text
            .replacingOccurrences(of: "및", with: ",")
            .replacingOccurrences(of: "그리고", with: ",")
        let separators = CharacterSet(charactersIn: ",/+;\n")
        let segments = normalized
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var result: [MealSlotDraft] = []

        for segment in segments {
            var anchors = anchors(in: segment)
            let parsed = relation(in: segment)
            var usedGenericMeals = false

            if anchors.isEmpty {
                // "식후 30분" 처럼 식사 지정 없이 기준만 있는 경우 → 횟수만큼 기본 식사에 적용
                guard parsed != nil else { continue }
                anchors = defaultAnchors(count: expectedCount > 0 ? expectedCount : 3)
                usedGenericMeals = true
            }

            let explicitMinutes = minutes(in: segment)
            for anchor in anchors where !result.contains(where: { $0.anchor == anchor }) {
                var relation = parsed?.relation ?? .at
                var minutes = explicitMinutes ?? parsed?.defaultMinutes ?? 0
                if usedGenericMeals && anchor == .bedtime {
                    relation = .before
                    minutes = explicitMinutes ?? 30
                }
                if relation == .at { minutes = 0 }
                result.append(MealSlotDraft(anchor: anchor, relation: relation, minutes: minutes))
            }
        }

        return result.sorted {
            (DoseAnchor.allCases.firstIndex(of: $0.anchor) ?? 0) < (DoseAnchor.allCases.firstIndex(of: $1.anchor) ?? 0)
        }
    }

    private static func anchors(in segment: String) -> [DoseAnchor] {
        var found: [DoseAnchor] = []
        if segment.contains("아침") { found.append(.breakfast) }
        if segment.contains("점심") { found.append(.lunch) }
        if segment.contains("저녁") { found.append(.dinner) }
        let bedtimeWords = ["취침", "자기 전", "자기전", "잠자기", "잠들기", "수면", "자기 직전"]
        if bedtimeWords.contains(where: { segment.contains($0) }) { found.append(.bedtime) }
        return found
    }

    private static func relation(in segment: String) -> (relation: MealSlotDraft.Relation, defaultMinutes: Int)? {
        if segment.contains("식간") { return (.after, 120) }
        if segment.contains("식전") || segment.contains("식사 전") || segment.contains("취침 전")
            || segment.contains("자기 전") || segment.contains("자기전") || segment.contains("잠들기 전")
            || segment.contains("자기 직전") {
            return (.before, 30)
        }
        if segment.contains("식후") || segment.contains("식사 후") || segment.contains("취침 후") {
            return (.after, 30)
        }
        let atWords = ["식사 중", "식사중", "식중", "식사 때", "식사와", "함께", "취침 시", "잘 때"]
        if atWords.contains(where: { segment.contains($0) }) { return (.at, 0) }
        return nil
    }

    private static func minutes(in segment: String) -> Int? {
        if let value = firstNumber(before: "분", in: segment) { return value }
        if let hours = firstNumber(before: "시간", in: segment) { return hours * 60 }
        return nil
    }

    private static func firstNumber(before unit: String, in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: "(\\d+)\\s*" + unit) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let numberRange = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[numberRange])
    }

    private static func defaultAnchors(count: Int) -> [DoseAnchor] {
        switch count {
        case ...1: return [.breakfast]
        case 2: return [.breakfast, .dinner]
        case 3: return [.breakfast, .lunch, .dinner]
        default: return [.breakfast, .lunch, .dinner, .bedtime]
        }
    }
}
