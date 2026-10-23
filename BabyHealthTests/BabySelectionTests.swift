import XCTest
@testable import BabyHealth

final class BabySelectionTests: XCTestCase {
    private func makeBaby(_ name: String) -> Baby {
        Baby(name: name, birthDate: Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testReturnsNilWhenThereAreNoBabies() {
        XCTAssertNil(BabySelection.resolve(selectedID: "", in: []))
    }

    func testFallsBackToFirstBabyWhenNothingSelected() {
        let first = makeBaby("첫째")
        let second = makeBaby("둘째")

        let resolved = BabySelection.resolve(selectedID: "", in: [first, second])

        XCTAssertEqual(resolved?.uuid, first.uuid)
    }

    func testReturnsBabyMatchingSelectedID() {
        let first = makeBaby("첫째")
        let second = makeBaby("둘째")

        let resolved = BabySelection.resolve(selectedID: second.uuid.uuidString, in: [first, second])

        XCTAssertEqual(resolved?.uuid, second.uuid)
    }

    func testFallsBackToFirstBabyWhenSelectedBabyWasDeleted() {
        let first = makeBaby("첫째")

        let resolved = BabySelection.resolve(selectedID: UUID().uuidString, in: [first])

        XCTAssertEqual(resolved?.uuid, first.uuid)
    }
}
