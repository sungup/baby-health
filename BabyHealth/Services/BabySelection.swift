import Foundation

enum AppStorageKey {
    static let selectedBabyID = "selectedBabyID"
}

enum BabySelection {
    /// 저장된 ID와 일치하는 아기를 돌려주고, 없으면(삭제됨/미설정) 첫 번째 아기로 대체한다.
    static func resolve(selectedID: String, in babies: [Baby]) -> Baby? {
        babies.first { $0.uuid.uuidString == selectedID } ?? babies.first
    }
}
