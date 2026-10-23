import Foundation
import SwiftData

enum TemperatureMethod: String, Codable, CaseIterable, Identifiable {
    case ear
    case forehead
    case armpit
    case rectal
    case oral

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ear: return "귀"
        case .forehead: return "이마"
        case .armpit: return "겨드랑이"
        case .rectal: return "항문"
        case .oral: return "입"
        }
    }
}

@Model
final class TemperatureRecord {
    /// 발열로 보는 기준 체온(°C). 앱 내 단순 규칙이며 의료적 판단을 대체하지 않는다.
    static let feverThreshold: Double = 38.0

    var measuredAt: Date
    var celsius: Double
    var method: TemperatureMethod
    var notes: String
    var baby: Baby?

    init(
        measuredAt: Date = .now,
        celsius: Double,
        method: TemperatureMethod = .ear,
        notes: String = ""
    ) {
        self.measuredAt = measuredAt
        self.celsius = celsius
        self.method = method
        self.notes = notes
    }

    var isFever: Bool { celsius >= Self.feverThreshold }
}
