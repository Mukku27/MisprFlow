import Foundation

enum GroqModelCatalogTests {
    static func run() {
        testParseValidModelsResponse()
        testParseIgnoresMalformedEntries()
        testDropdownGroqIntersectsKnownAndLive()
        testDropdownFallsBackToKnownWithoutLive()
        testDropdownFallsBackToKnownOnEmptyIntersection()
        testDropdownNonGroqShowsFullLiveList()
        testDeprecatedSelectionDetection()
        testStoredModelMigration()
    }

    private static func testParseValidModelsResponse() {
        let json = """
        {"object":"list","data":[
        {"id":"qwen/qwen3.8-27b","object":"model"},
        {"id":"whisper-large-v3-turbo","object":"model"},
        {"id":"qwen/qwen3.8-27b","object":"model"},
        {"id":"  openai/gpt-oss-20b  ","object":"model"}
        ]}
        """
        TestSupport.expectEqual(
            GroqModelCatalog.parseModelsResponse(Data(json.utf8)),
            ["openai/gpt-oss-20b", "qwen/qwen3.8-27b", "whisper-large-v3-turbo"]
        )
    }

    private static func testParseIgnoresMalformedEntries() {
        TestSupport.expectEqual(GroqModelCatalog.parseModelsResponse(Data("not json".utf8)), [])
        let missingIDs = """
        {"object":"list","data":[{"object":"model"},{"id":"","object":"model"}]}
        """
        TestSupport.expectEqual(GroqModelCatalog.parseModelsResponse(Data(missingIDs.utf8)), [])
        let wrongShape = """
        {"models":["qwen/qwen3.8-27b"]}
        """
        TestSupport.expectEqual(GroqModelCatalog.parseModelsResponse(Data(wrongShape.utf8)), [])
    }

    private static func testDropdownGroqIntersectsKnownAndLive() {
        let known = ["openai/gpt-oss-20b", "qwen/qwen3.8-27b", "groq/compound"]
        let live = ["groq/compound", "QWEN/QWEN3.8-27B", "whisper-large-v3-turbo"]
        TestSupport.expectEqual(
            GroqModelCatalog.dropdownModels(known: known, live: live, isGroqHost: true),
            ["qwen/qwen3.8-27b", "groq/compound"]
        )
    }

    private static func testDropdownFallsBackToKnownWithoutLive() {
        let known = ["openai/gpt-oss-20b", "qwen/qwen3.8-27b"]
        TestSupport.expectEqual(
            GroqModelCatalog.dropdownModels(known: known, live: nil, isGroqHost: true),
            known
        )
        TestSupport.expectEqual(
            GroqModelCatalog.dropdownModels(known: known, live: [], isGroqHost: true),
            known
        )
    }

    private static func testDropdownFallsBackToKnownOnEmptyIntersection() {
        TestSupport.expectEqual(
            GroqModelCatalog.dropdownModels(
                known: ["openai/gpt-oss-20b"],
                live: ["some/future-model"],
                isGroqHost: true
            ),
            ["openai/gpt-oss-20b"]
        )
    }

    private static func testDropdownNonGroqShowsFullLiveList() {
        let live = ["custom/text-model", "custom/vision-model"]
        TestSupport.expectEqual(
            GroqModelCatalog.dropdownModels(
                known: ["openai/gpt-oss-20b"],
                live: live,
                isGroqHost: false
            ),
            live
        )
    }

    private static func testDeprecatedSelectionDetection() {
        let live = ["qwen/qwen3.8-27b", "openai/gpt-oss-20b"]
        TestSupport.expectEqual(
            GroqModelCatalog.isDeprecatedSelection("qwen/qwen3.6-27b", live: live),
            true
        )
        TestSupport.expectEqual(
            GroqModelCatalog.isDeprecatedSelection("QWEN/QWEN3.8-27B", live: live),
            false
        )
        TestSupport.expectEqual(
            GroqModelCatalog.isDeprecatedSelection("qwen/qwen3.6-27b", live: nil),
            false
        )
        TestSupport.expectEqual(
            GroqModelCatalog.isDeprecatedSelection("", live: live),
            false
        )
    }

    private static func testStoredModelMigration() {
        let migrations = ["qwen/qwen3.6-27b": "qwen/qwen3.8-27b"]
        TestSupport.expectEqual(
            GroqModelCatalog.migratedStoredModel(stored: nil, migrations: migrations, default: "qwen/qwen3.8-27b"),
            "qwen/qwen3.8-27b"
        )
        TestSupport.expectEqual(
            GroqModelCatalog.migratedStoredModel(stored: "   ", migrations: migrations, default: "qwen/qwen3.8-27b"),
            "qwen/qwen3.8-27b"
        )
        TestSupport.expectEqual(
            GroqModelCatalog.migratedStoredModel(stored: "qwen/qwen3.6-27b", migrations: migrations, default: "openai/gpt-oss-20b"),
            "qwen/qwen3.8-27b"
        )
        TestSupport.expectEqual(
            GroqModelCatalog.migratedStoredModel(stored: "QWEN/QWEN3.6-27B", migrations: migrations, default: "openai/gpt-oss-20b"),
            "qwen/qwen3.8-27b"
        )
        TestSupport.expectEqual(
            GroqModelCatalog.migratedStoredModel(stored: "openai/gpt-oss-20b", migrations: migrations, default: "qwen/qwen3.8-27b"),
            "openai/gpt-oss-20b"
        )
    }
}
