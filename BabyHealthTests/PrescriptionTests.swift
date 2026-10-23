import XCTest
@testable import BabyHealth

final class PrescriptionParserTests: XCTestCase {
    func testParsesJSONWrappedInCodeFence() throws {
        let text = """
        ```json
        {
          "prescribedDate": "2026-10-20",
          "prescriber": "행복소아과",
          "medications": [
            {
              "name": "타이레놀 시럽",
              "dosage": "5ml",
              "timesPerDay": 3,
              "timing": "아침·점심·저녁 식후",
              "days": 3,
              "reason": "해열",
              "notes": null
            },
            {
              "name": "항히스타민 시럽",
              "dosage": "2.5ml",
              "timesPerDay": 1,
              "timing": "취침 전",
              "days": 5
            }
          ],
          "warnings": ["두 번째 약의 용량이 흐리게 보임"]
        }
        ```
        """

        let result = try PrescriptionParser.parse(text)

        XCTAssertEqual(result.prescribedDate, "2026-10-20")
        XCTAssertEqual(result.prescriber, "행복소아과")
        XCTAssertEqual(result.medications.count, 2)
        XCTAssertEqual(result.medications[0].name, "타이레놀 시럽")
        XCTAssertEqual(result.medications[0].timesPerDay, 3)
        XCTAssertEqual(result.medications[1].timing, "취침 전")
        XCTAssertEqual(result.warnings.count, 1)
    }

    func testAcceptsNumbersGivenAsStrings() throws {
        let text = #"{"medications":[{"name":"A","timesPerDay":"2","days":"7"}]}"#

        let result = try PrescriptionParser.parse(text)

        XCTAssertEqual(result.medications.first?.timesPerDay, 2)
        XCTAssertEqual(result.medications.first?.days, 7)
    }

    func testMissingMedicationsBecomesEmptyList() throws {
        let result = try PrescriptionParser.parse(#"{"prescriber":"X"}"#)

        XCTAssertTrue(result.medications.isEmpty)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testInvalidTextThrows() {
        XCTAssertThrowsError(try PrescriptionParser.parse("읽을 수 없습니다"))
    }
}

final class PrescriptionImporterTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }

    private func makeDraft(days: String = "3") -> MedicationDraft {
        MedicationDraft(
            parsed: ParsedMedication(
                name: " 타이레놀 시럽 ",
                dosage: "5ml",
                timesPerDay: 3,
                timing: "식후 30분",
                days: Int(days),
                reason: "해열"
            )
        )
    }

    func testParseDate() {
        let date = PrescriptionImporter.parseDate("2026-10-20", calendar: calendar)

        XCTAssertNotNil(date)
        XCTAssertEqual(calendar.component(.day, from: date!), 20)
        XCTAssertNil(PrescriptionImporter.parseDate("20/10/2026", calendar: calendar))
        XCTAssertNil(PrescriptionImporter.parseDate(nil, calendar: calendar))
        XCTAssertNil(PrescriptionImporter.parseDate("  ", calendar: calendar))
    }

    func testDraftClampsTimesPerDay() {
        XCTAssertEqual(MedicationDraft(parsed: ParsedMedication(name: "A", timesPerDay: 0)).timesPerDay, 1)
        XCTAssertEqual(MedicationDraft(parsed: ParsedMedication(name: "A", timesPerDay: 20)).timesPerDay, 8)
        XCTAssertEqual(MedicationDraft(parsed: ParsedMedication(name: "A", timesPerDay: nil)).timesPerDay, 1)
    }

    func testMakeMedicationComputesEndDateFromDays() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 15))!

        let medication = PrescriptionImporter.makeMedication(
            from: makeDraft(days: "3"),
            prescribedDate: start,
            startDate: start,
            prescriber: " 행복소아과 ",
            calendar: calendar
        )

        XCTAssertEqual(medication.name, "타이레놀 시럽")
        XCTAssertEqual(medication.dosage, "5ml")
        XCTAssertEqual(medication.timingNote, "식후 30분")
        XCTAssertEqual(medication.prescriber, "행복소아과")
        // 20일 시작 + 3일 → 22일까지
        XCTAssertEqual(calendar.component(.day, from: medication.endDate!), 22)
    }

    func testMakeMedicationWithoutDaysHasNoEndDate() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20))!

        let medication = PrescriptionImporter.makeMedication(
            from: makeDraft(days: ""),
            prescribedDate: start,
            startDate: start,
            prescriber: "",
            calendar: calendar
        )

        XCTAssertNil(medication.endDate)
    }
}

// MARK: - Gemini 호출 (URLProtocol 스텁)

private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class GeminiPrescriptionReaderTests: XCTestCase {
    private var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private let successBody = #"{"candidates":[{"content":{"parts":[{"text":"{\"medications\":[{\"name\":\"A\"}]}"}]}}]}"#
    private let forbiddenBody = #"{"error":{"message":"denied"}}"#

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testReadsMedicationsFromResponse() async throws {
        StubURLProtocol.handler = { [successBody] _ in (200, Data(successBody.utf8)) }
        let reader = GeminiPrescriptionReader(credentials: { [.apiKey("k")] }, session: session)

        let result = try await reader.read(images: [Data([1, 2, 3])])

        XCTAssertEqual(result.medications.first?.name, "A")
    }

    func testFallsBackToAPIKeyWhenOAuthIsForbidden() async throws {
        StubURLProtocol.handler = { [successBody, forbiddenBody] request in
            if request.value(forHTTPHeaderField: "Authorization") != nil {
                return (403, Data(forbiddenBody.utf8))
            }
            return (200, Data(successBody.utf8))
        }
        let reader = GeminiPrescriptionReader(
            credentials: { [.oauth(accessToken: "t", projectID: nil), .apiKey("k")] },
            session: session
        )

        let result = try await reader.read(images: [Data([1])])

        XCTAssertEqual(result.medications.count, 1)
    }

    func testThrowsWhenEveryCredentialIsForbidden() async {
        StubURLProtocol.handler = { [forbiddenBody] _ in (403, Data(forbiddenBody.utf8)) }
        let reader = GeminiPrescriptionReader(
            credentials: { [.oauth(accessToken: "t", projectID: nil), .apiKey("k")] },
            session: session
        )

        do {
            _ = try await reader.read(images: [Data([1])])
            XCTFail("403 이면 오류가 나야 합니다.")
        } catch GeminiError.badStatus(let code, _) {
            XCTAssertEqual(code, 403)
        } catch {
            XCTFail("예상하지 못한 오류: \(error)")
        }
    }

    func testThrowsNotConnectedWithoutCredentials() async {
        let reader = GeminiPrescriptionReader(credentials: { [] }, session: session)

        do {
            _ = try await reader.read(images: [Data([1])])
            XCTFail("연결이 없으면 오류가 나야 합니다.")
        } catch GeminiError.notConnected {
            // expected
        } catch {
            XCTFail("예상하지 못한 오류: \(error)")
        }
    }
}
