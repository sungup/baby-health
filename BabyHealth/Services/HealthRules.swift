import Foundation

struct HealthFinding: Identifiable, Equatable {
    enum Severity: Int, Comparable {
        case info = 0
        case warning = 1
        case alert = 2

        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let id = UUID()
    let severity: Severity
    let message: String

    static func == (lhs: HealthFinding, rhs: HealthFinding) -> Bool {
        lhs.severity == rhs.severity && lhs.message == rhs.message
    }
}

/// LLM 없이 항상 동작하는 규칙 기반 점검. LLM 검토의 비교 기준이 된다.
enum HealthRules {
    static func findings(
        for snapshot: HealthSnapshot,
        calendar: Calendar = .current
    ) -> [HealthFinding] {
        var results: [HealthFinding] = []
        let now = snapshot.generatedAt
        let startOfToday = calendar.startOfDay(for: now)

        // 1) 접종 지연
        for vaccine in snapshot.vaccinations
        where vaccine.administeredDate == nil && vaccine.scheduledDate < startOfToday {
            let days = calendar.dateComponents([.day], from: vaccine.scheduledDate, to: startOfToday).day ?? 0
            results.append(
                HealthFinding(
                    severity: .warning,
                    message: "\(vaccine.name) \(vaccine.doseNumber)차 접종이 \(days)일 지연되었습니다."
                )
            )
        }

        // 2) 최근 24시간 발열
        let dayAgo = now.addingTimeInterval(-24 * 60 * 60)
        let recentFevers = snapshot.temperatures.filter {
            $0.measuredAt >= dayAgo && $0.celsius >= TemperatureRecord.feverThreshold
        }
        if let highest = recentFevers.map(\.celsius).max() {
            results.append(
                HealthFinding(
                    severity: .alert,
                    message: "최근 24시간 내 발열 기록이 \(recentFevers.count)건 있습니다 (최고 \(String(format: "%.1f", highest))°C)."
                )
            )
        }

        // 3) 오늘 투약 기록 부족
        for medicine in snapshot.medications where medicine.dosesTakenToday < medicine.timesPerDay {
            results.append(
                HealthFinding(
                    severity: .info,
                    message: "\(medicine.name): 오늘 복용 기록 \(medicine.dosesTakenToday)/\(medicine.timesPerDay)회."
                )
            )
        }

        return results.sorted { $0.severity > $1.severity }
    }
}
