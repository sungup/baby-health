import Foundation

/// LLM에 보낼 프롬프트를 만든다. 식별 정보(이름, 생년월일, 병원명)는 보내지 않는다.
enum HealthSummaryBuilder {
    static let systemPrompt = """
    당신은 영유아 건강 기록을 검토하는 보조자입니다. 의사가 아니며 진단이나 처방을 하지 않습니다.
    주어진 기록에서 다음을 점검해 한국어로 간결하게 답하세요.
    1. 접종 일정에서 누락되었거나 지연된 항목, 기록이 모순되는 항목
    2. 체온 추이에서 주의가 필요한 패턴
    3. 투약 기록의 이상 (용량·횟수·기간이 비정상적으로 보이는 경우, 기록 누락)
    4. 병원 방문 내용과 투약/체온 기록 사이의 불일치
    확실하지 않은 내용은 추측하지 말고 "확인 필요"라고 표시하세요.
    응급 가능성이 있어 보이면 맨 앞에 "즉시 의료진 상담 권장"을 쓰세요.
    마지막에 "이 내용은 참고용이며 의료진 상담을 대체하지 않습니다."를 붙이세요.
    """

    static func userPrompt(for snapshot: HealthSnapshot) -> String {
        var lines: [String] = []
        lines.append("기준일: \(format(snapshot.generatedAt))")
        lines.append("월령: 생후 \(snapshot.ageInMonths)개월")

        lines.append("")
        lines.append("[접종]")
        if snapshot.vaccinations.isEmpty {
            lines.append("- 기록 없음")
        }
        for vaccine in snapshot.vaccinations {
            let status = vaccine.administeredDate.map { "완료(\(format($0)))" } ?? "미접종"
            lines.append("- \(vaccine.name) \(vaccine.doseNumber)차 / 예정 \(format(vaccine.scheduledDate)) / \(status)")
        }

        lines.append("")
        lines.append("[체온 - 최근 기록]")
        if snapshot.temperatures.isEmpty {
            lines.append("- 기록 없음")
        }
        for temperature in snapshot.temperatures {
            lines.append(
                "- \(formatDateTime(temperature.measuredAt)) \(String(format: "%.1f", temperature.celsius))°C (\(temperature.method.label))"
            )
        }

        lines.append("")
        lines.append("[병원 방문 - 최근]")
        if snapshot.visits.isEmpty {
            lines.append("- 기록 없음")
        }
        for visit in snapshot.visits {
            let diagnosis = visit.diagnosis.isEmpty ? "진단 기록 없음" : visit.diagnosis
            lines.append("- \(format(visit.date)) / 사유: \(visit.reason) / \(diagnosis)")
        }

        lines.append("")
        lines.append("[투약 - 진행 중]")
        if snapshot.medications.isEmpty {
            lines.append("- 기록 없음")
        }
        for medicine in snapshot.medications {
            let end = medicine.endDate.map { format($0) } ?? "종료일 미정"
            let timing = medicine.timingNote.isEmpty ? "" : " (\(medicine.timingNote))"
            lines.append(
                "- \(medicine.name) \(medicine.dosage) 하루 \(medicine.timesPerDay)회\(timing) / \(format(medicine.startDate)) ~ \(end) / 오늘 \(medicine.dosesTakenToday)회 복용"
            )
        }

        return lines.joined(separator: "\n")
    }

    private static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
