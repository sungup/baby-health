import Foundation

// MARK: - Gemini 가 돌려주는 JSON

struct ParsedPrescription: Decodable {
    var prescribedDate: String?
    var prescriber: String?
    var medications: [ParsedMedication]
    var warnings: [String]

    enum CodingKeys: String, CodingKey {
        case prescribedDate, prescriber, medications, warnings
    }

    init(prescribedDate: String? = nil, prescriber: String? = nil, medications: [ParsedMedication] = [], warnings: [String] = []) {
        self.prescribedDate = prescribedDate
        self.prescriber = prescriber
        self.medications = medications
        self.warnings = warnings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        prescribedDate = try container.decodeIfPresent(String.self, forKey: .prescribedDate)
        prescriber = try container.decodeIfPresent(String.self, forKey: .prescriber)
        medications = try container.decodeIfPresent([ParsedMedication].self, forKey: .medications) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }
}

struct ParsedMedication: Decodable {
    var name: String
    /// 1회 용량 (단위 포함, 예: "2.5ml", "1정")
    var dosage: String?
    var timesPerDay: Int?
    /// 복용 시점 원문 (예: "아침·저녁 식후 30분", "취침 전", "필요 시")
    var timing: String?
    /// 총 투약 일수
    var days: Int?
    /// 식사 기준이 없는 약의 투약 간격(시간). 예: "8시간마다" → 8
    var intervalHours: Int?
    var reason: String?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case name, dosage, timesPerDay, timing, days, intervalHours, reason, notes
    }

    init(
        name: String,
        dosage: String? = nil,
        timesPerDay: Int? = nil,
        timing: String? = nil,
        days: Int? = nil,
        intervalHours: Int? = nil,
        reason: String? = nil,
        notes: String? = nil
    ) {
        self.name = name
        self.dosage = dosage
        self.timesPerDay = timesPerDay
        self.timing = timing
        self.days = days
        self.intervalHours = intervalHours
        self.reason = reason
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        dosage = try container.decodeIfPresent(String.self, forKey: .dosage)
        timesPerDay = Self.decodeInt(container, .timesPerDay)
        timing = try container.decodeIfPresent(String.self, forKey: .timing)
        days = Self.decodeInt(container, .days)
        intervalHours = Self.decodeInt(container, .intervalHours)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }

    /// 모델이 숫자를 "3" 같은 문자열로 줄 때도 받아준다.
    private static func decodeInt(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let text = try? container.decodeIfPresent(String.self, forKey: key) {
            return Int(text.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
}

// MARK: - 검토 화면에서 편집하는 초안

struct MedicationDraft: Identifiable {
    let id = UUID()
    var include = true
    var name: String
    var dosage: String
    var timing: String
    var daysText: String
    var reason: String
    var notes: String
    var schedule: DoseScheduleDraft

    /// 하루 복용 횟수는 스케줄에서 계산한다.
    var timesPerDay: Int { schedule.timesPerDay }

    init(parsed: ParsedMedication, now: Date = .now, calendar: Calendar = .current) {
        name = parsed.name.trimmingCharacters(in: .whitespacesAndNewlines)
        dosage = parsed.dosage ?? ""
        timing = parsed.timing ?? ""
        daysText = parsed.days.map { String($0) } ?? ""
        reason = parsed.reason ?? ""
        notes = parsed.notes ?? ""
        schedule = TimingInterpreter.interpret(
            timing: parsed.timing,
            timesPerDay: parsed.timesPerDay,
            intervalHours: parsed.intervalHours,
            now: now,
            calendar: calendar
        )
    }

    /// 수동 입력용 빈 초안.
    init(now: Date = .now, calendar: Calendar = .current) {
        name = ""
        dosage = ""
        timing = ""
        daysText = ""
        reason = ""
        notes = ""
        schedule = DoseScheduleDraft()
        schedule.firstDoseMinutes = MinuteOfDay.roundedUpMinutes(from: now, calendar: calendar)
    }

    var totalDays: Int? {
        guard let days = Int(daysText.trimmingCharacters(in: .whitespaces)), days > 0 else { return nil }
        return days
    }
}

// MARK: - 파싱 / 변환

enum PrescriptionParseError: LocalizedError {
    case invalidJSON

    var errorDescription: String? {
        "처방전 분석 결과를 해석하지 못했습니다. 더 선명하게 다시 촬영해 보세요."
    }
}

enum PrescriptionParser {
    static func parse(_ text: String) throws -> ParsedPrescription {
        let json = extractJSON(from: text)
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(ParsedPrescription.self, from: data) else {
            throw PrescriptionParseError.invalidJSON
        }
        return parsed
    }

    /// ```json ... ``` 코드 블록이나 앞뒤 설명이 붙어 있어도 첫 `{` ~ 마지막 `}` 만 꺼낸다.
    static func extractJSON(from text: String) -> String {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end else {
            return text
        }
        return String(text[start...end])
    }
}

enum PrescriptionImporter {
    /// "yyyy-MM-dd" 형식의 날짜를 읽는다. 형식이 다르면 nil.
    static func parseDate(_ text: String?, calendar: Calendar = .current) -> Date? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    /// 초안을 Medication 으로 만든다. `start` 는 실제 투약 시작 시점(시각 지정 모드면 최초 투약 시각 포함).
    static func makeMedication(
        from draft: MedicationDraft,
        prescribedDate: Date,
        start: Date,
        prescriber: String,
        calendar: Calendar = .current
    ) -> Medication {
        var end: Date?
        if let days = draft.totalDays {
            end = calendar.date(byAdding: .day, value: days - 1, to: calendar.startOfDay(for: start))
        }
        let timing = draft.timing.trimmingCharacters(in: .whitespacesAndNewlines)
        return Medication(
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            dosage: draft.dosage.trimmingCharacters(in: .whitespacesAndNewlines),
            timesPerDay: draft.timesPerDay,
            startDate: start,
            endDate: end,
            reason: draft.reason,
            notes: draft.notes,
            prescribedDate: prescribedDate,
            prescriber: prescriber.trimmingCharacters(in: .whitespacesAndNewlines),
            timingNote: timing.isEmpty ? draft.schedule.summary : timing,
            slots: draft.schedule.makeSlots()
        )
    }
}
