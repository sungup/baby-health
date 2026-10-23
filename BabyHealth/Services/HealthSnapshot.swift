import Foundation

/// 검증/요약에 쓰는 값 타입 스냅샷. SwiftData 모델과 분리해 테스트하기 쉽게 한다.
/// 이름 등 식별 정보는 의도적으로 포함하지 않는다.
struct HealthSnapshot: Equatable {
    struct Vaccine: Equatable {
        let name: String
        let doseNumber: Int
        let scheduledDate: Date
        let administeredDate: Date?
    }

    struct Temperature: Equatable {
        let measuredAt: Date
        let celsius: Double
        let method: TemperatureMethod
    }

    struct Visit: Equatable {
        let date: Date
        let reason: String
        let diagnosis: String
    }

    struct Medicine: Equatable {
        let name: String
        let dosage: String
        let timesPerDay: Int
        let startDate: Date
        let endDate: Date?
        let dosesTakenToday: Int
        var timingNote: String = ""
    }

    let generatedAt: Date
    let ageInMonths: Int
    let vaccinations: [Vaccine]
    let temperatures: [Temperature]
    let visits: [Visit]
    let medications: [Medicine]
}

extension HealthSnapshot {
    /// 최근 `temperatureDays`일 체온, 최근 `visitDays`일 방문, 진행 중인 투약만 담는다.
    init(
        baby: Baby,
        now: Date = .now,
        calendar: Calendar = .current,
        temperatureDays: Int = 7,
        visitDays: Int = 30
    ) {
        let tempSince = calendar.date(byAdding: .day, value: -temperatureDays, to: now) ?? now
        let visitSince = calendar.date(byAdding: .day, value: -visitDays, to: now) ?? now

        self.init(
            generatedAt: now,
            ageInMonths: baby.ageInMonths(asOf: now, calendar: calendar),
            vaccinations: baby.vaccinations
                .sorted { $0.scheduledDate < $1.scheduledDate }
                .map {
                    Vaccine(
                        name: $0.name,
                        doseNumber: $0.doseNumber,
                        scheduledDate: $0.scheduledDate,
                        administeredDate: $0.administeredDate
                    )
                },
            temperatures: baby.temperatures
                .filter { $0.measuredAt >= tempSince }
                .sorted { $0.measuredAt < $1.measuredAt }
                .map { Temperature(measuredAt: $0.measuredAt, celsius: $0.celsius, method: $0.method) },
            visits: baby.visits
                .filter { $0.date >= visitSince }
                .sorted { $0.date < $1.date }
                .map { Visit(date: $0.date, reason: $0.reason, diagnosis: $0.diagnosis) },
            medications: baby.medications
                .filter { $0.isActive(asOf: now, calendar: calendar) }
                .sorted { $0.startDate < $1.startDate }
                .map {
                    Medicine(
                        name: $0.name,
                        dosage: $0.dosage,
                        timesPerDay: $0.timesPerDay,
                        startDate: $0.startDate,
                        endDate: $0.endDate,
                        dosesTakenToday: $0.doseCount(on: now, calendar: calendar),
                        timingNote: $0.timingNote
                    )
                }
        )
    }
}
