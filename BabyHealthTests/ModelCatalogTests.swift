import XCTest
@testable import BabyHealth

final class ModelCatalogTests: XCTestCase {
    func testOptionsKeepPresetsFirstThenFetchedWithoutDuplicates() {
        let options = ModelCatalog.options(
            selection: "custom-model",
            presets: ["a", "b"],
            fetched: ["z", "b", "c"]
        )

        XCTAssertEqual(options, ["a", "b", "c", "z", "custom-model"])
    }

    func testOptionsIncludeCurrentSelectionEvenIfUnknown() {
        let options = ModelCatalog.options(selection: "x", presets: ["a"], fetched: [])

        XCTAssertTrue(options.contains("x"))
    }

    func testOptionsIgnoreEmptySelection() {
        let options = ModelCatalog.options(selection: "", presets: ["a"], fetched: [])

        XCTAssertEqual(options, ["a"])
    }

    func testEffectiveFallsBackToDefaultWhenBlank() {
        XCTAssertEqual(ModelCatalog.effective("  ", default: "d"), "d")
        XCTAssertEqual(ModelCatalog.effective(" m ", default: "d"), "m")
    }
}

final class ModelListParserTests: XCTestCase {
    func testGeminiParserKeepsGenerateContentModelsAndStripsPrefix() {
        let json = """
        {
          "models": [
            {"name": "models/gemini-3.8-flash", "supportedGenerationMethods": ["generateContent", "countTokens"]},
            {"name": "models/gemini-embedding-001", "supportedGenerationMethods": ["embedContent"]},
            {"name": "models/imagen-4", "supportedGenerationMethods": ["generateContent"]},
            {"name": "models/gemini-3.5-flash-lite"}
          ],
          "nextPageToken": "abc"
        }
        """
        let data = Data(json.utf8)

        XCTAssertEqual(ModelListParser.geminiModelIDs(from: data), ["gemini-3.8-flash", "gemini-3.5-flash-lite"])
        XCTAssertEqual(ModelListParser.geminiNextPageToken(from: data), "abc")
    }

    func testGeminiParserHandlesMissingFields() {
        XCTAssertEqual(ModelListParser.geminiModelIDs(from: Data("{}".utf8)), [])
        XCTAssertNil(ModelListParser.geminiNextPageToken(from: Data("{}".utf8)))
        XCTAssertEqual(ModelListParser.geminiModelIDs(from: Data("not json".utf8)), [])
    }

    func testAnthropicParserReturnsIDs() {
        let json = #"{"data":[{"id":"claude-sonnet-5-5","type":"model"},{"id":"claude-haiku-5-5","type":"model"}],"has_more":false}"#

        XCTAssertEqual(
            ModelListParser.anthropicModelIDs(from: Data(json.utf8)),
            ["claude-sonnet-5-5", "claude-haiku-5-5"]
        )
        XCTAssertEqual(ModelListParser.anthropicModelIDs(from: Data("oops".utf8)), [])
    }
}
