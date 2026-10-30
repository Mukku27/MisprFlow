import Foundation

@main
struct MisprFlowTests {
    static func main() {
        AgentModeServiceTests.run()
        AppContextServiceTests.run()
        CoreDataStoreBootstrapTests.run()
        ModelConfigurationTests.run()
        GroqModelCatalogTests.run()
        ShortcutCoreTests.run()
        SemanticVersionTests.run()
        LLMCooldownManagerTests.run()
        TranscriptionErrorPresentationCoreTests.run()
        TranscriptTextCoreTests.run()
        StatsPolicyTests.run()
        StatsCalendarTests.run()
        StatsCalculatorTests.run()
        StatsHeatmapCoreTests.run()
        StatsHistoryBackfillTests.run()
        StatsStoreTests.run()
        UsageBreakdownTests.run()
        VoiceMacroExpanderTests.run()
        MisprPaletteTests.run()
        print("MisprFlowTests passed")
    }
}
