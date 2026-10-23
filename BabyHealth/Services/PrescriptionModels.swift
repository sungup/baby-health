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
    var reason: String?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case name, dosage, timesPerDay, timing, days, reason, notes
    }

    init(
        name: String,
        dosage: String? = nil,
        timesPerDay: Int? = nil,
        timing: String? = nil,
        days: Int? = nil,
        reason: String? = nil,
        notes: String? = nil
    ) {
        self.name = name
        self.dosage = dosage
        self.timesPerDay = timesPerDay
        self.timing = timing
        self.days = days
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
    var timesPerDay: Int
    var timing: String
    var daysText: String
    var reason: String
    var notes: String

    init(parsed: ParsedMedication) {
        name = parsed.name.trimmingCharacters(in: .whitespacesAndNewlines)
        dosage = parsed.dosage ?? ""
        timesPerDay = min(max(parsed.timesPerDay ?? 1, 1), 8)
        timing = parsed.timing ?? ""
        daysText = parsed.days.map { String($0) } ?? ""
        reason = parsed.reason ?? ""
        notes = parsed.notes ?? ""
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

    static func makeMedication(
        from draft: MedicationDraft,
        prescribedDate: Date,
        startDate: Date,
        prescriber: String,
        calendar: Calendar = .current
    ) -> Medication {
        let start = calendar.startOfDay(for: startDate)
        var end: Date?
        if let days = Int(draft.daysText.trimmingCharacters(in: .whitespaces)), days > 0 {
            end = calendar.date(byAdding: .day, value: days - 1, to: start)
        }
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
            timingNote: draft.timing.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
