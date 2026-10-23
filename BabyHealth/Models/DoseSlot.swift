import Foundation
import SwiftData

/// 투약 시점의 기준이 되는 식사/취침.
enum DoseAnchor: String, Codable, CaseIterable, Identifiable {
    case breakfast
    case lunch
    case dinner
    case bedtime

    var id: String { rawValue }

    var label: String {
        switch self {
        case .breakfast: return "아침"
        case .lunch: return "점심"
        case .dinner: return "저녁"
        case .bedtime: return "취침"
        }
    }

    var isMeal: Bool { self != .bedtime }
}

/// 하루 중 한 번의 투약 시점 (값 타입). 알람 계산과 편집 화면에서 쓴다.
/// - anchor 가 있으면 "그 식사/취침 시간 + offsetMinutes"
/// - anchor 가 nil 이면 하루 중 `fixedMinutes`(자정 기준 분) 정시
struct DoseSlotValue: Equatable, Hashable {
    var anchor: DoseAnchor?
    /// 음수 = 식전/취침 전, 양수 = 식후/취침 후
    var offsetMinutes: Int = 0
    var fixedMinutes: Int?

    var label: String {
        guard let anchor else {
            return fixedMinutes.map { MinuteOfDay.string(from: $0) } ?? "정시"
        }
        if anchor == .bedtime {
            if offsetMinutes < 0 { return "취침 \(-offsetMinutes)분 전" }
            if offsetMinutes > 0 { return "취침 \(offsetMinutes)분 후" }
            return "취침 시"
        }
        if offsetMinutes < 0 { return "\(anchor.label) 식전 \(-offsetMinutes)분" }
        if offsetMinutes > 0 { return "\(anchor.label) 식후 \(offsetMinutes)분" }
        return "\(anchor.label) 식사 때"
    }
}

@Model
final class DoseSlot {
    var anchor: DoseAnchor?
    var offsetMinutes: Int
    var fixedMinutes: Int?
    var medication: Medication?

    init(_ value: DoseSlotValue) {
        self.anchor = value.anchor
        self.offsetMinutes = value.offsetMinutes
        self.fixedMinutes = value.fixedMinutes
    }

    var value: DoseSlotValue {
        DoseSlotValue(anchor: anchor, offsetMinutes: offsetMinutes, fixedMinutes: fixedMinutes)
    }
}
