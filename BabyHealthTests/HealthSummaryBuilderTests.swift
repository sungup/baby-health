import XCTest
@testable import BabyHealth

final class HealthSummaryBuilderTests: XCTestCase {
    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    func testPromptContainsRecordsButNoIdentifyingFields() {
        let snapshot = HealthSnapshot(
            generatedAt: makeDate(2026, 10, 23),
            ageInMonths: 5,
            vaccinations: [
                .init(name: "DTaP", doseNumber: 2, scheduledDate: makeDate(2026, 10, 20), administeredDate: nil)
            ],
            temperatures: [],
            visits: [
                .init(date: makeDate(2026, 10, 18), reason: "기침", diagnosis: "감기")
            ],
            medications: []
        )

        let prompt = HealthSummaryBuilder.userPrompt(for: snapshot)

        XCTAssertTrue(prompt.contains("생후 5개월"))
        XCTAssertTrue(prompt.contains("DTaP 2차"))
        XCTAssertTrue(prompt.contains("미접종"))
        XCTAssertTrue(prompt.contains("기침"))
        XCTAssertTrue(prompt.contains("체온"))
    }

    func testEmptySectionsAreMarked() {
        let snapshot = HealthSnapshot(
            generatedAt: makeDate(2026, 10, 23),
            ageInMonths: 0,
            vaccinations: [],
            temperatures: [],
            visits: [],
            medications: []
        )

        let prompt = HealthSummaryBuilder.userPrompt(for: snapshot)

        XCTAssertEqual(prompt.components(separatedBy: "- 기록 없음").count - 1, 4)
    }
}

private struct StubLLMClient: LLMClient {
    var response: Result<String, Error>

    func complete(system: String, user: String) async throws -> String {
        try response.get()
    }
}

final class HealthCheckServiceTests: XCTestCase {
    private let emptySnapshot = HealthSnapshot(
        generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
        ageInMonths: 3,
        vaccinations: [],
        temperatures: [],
        visits: [],
        medications: []
    )

    func testReturnsLLMReviewWhenClientSucceeds() async {
        let service = HealthCheckService(client: StubLLMClient(response: .success("이상 없음")))

        let result = await service.run(snapshot: emptySnapshot)

        XCTAssertEqual(result.llmReview, "이상 없음")
        XCTAssertNil(result.llmError)
    }

    func testKeepsRuleFindingsWhenClientFails() async {
        let service = HealthCheckService(client: StubLLMClient(response: .failure(LLMError.badStatus(500))))

        let result = await service.run(snapshot: emptySnapshot)

        XCTAssertNil(result.llmReview)
        XCTAssertNotNil(result.llmError)
    }

    func testReportsMissingKeyWhenNoClient() async {
        let service = HealthCheckService(client: nil)

        let result = await service.run(snapshot: emptySnapshot)

        XCTAssertNil(result.llmReview)
        XCTAssertEqual(result.llmError, LLMError.missingAPIKey.errorDescription)
    }
}
