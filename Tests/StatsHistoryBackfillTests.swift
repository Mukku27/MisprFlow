import Foundation

enum StatsHistoryBackfillTests {
    static func run() {
        testDictationRow()
        testEditRow()
        testFailedEditRow()
        testErrorRow()
        testMacroRow()
        testEmptyOutputRow()
    }

    private static func testDictationRow() {
        let run = StatsHistoryBackfill.run(for: StatsTestSupport.historyItem(
            status: "Post-processing succeeded",
            rawTranscript: StatsTestSupport.words(50),
            postProcessedTranscript: StatsTestSupport.words(48)
        ))
        TestSupport.expectEqual(run.kind, .dictation)
        TestSupport.expectEqual(run.producedOutput, true)
        TestSupport.expectEqual(run.spokenWordCount, 50)
        TestSupport.expectEqual(run.outputWordCount, 48)
        TestSupport.expectEqual(run.audioDurationSec, nil)
    }

    private static func testEditRow() {
        let run = StatsHistoryBackfill.run(for: StatsTestSupport.historyItem(
            intent: .commandAutomatic,
            status: "Edit mode succeeded (automatic)",
            rawTranscript: StatsTestSupport.words(12),
            postProcessedTranscript: StatsTestSupport.words(300)
        ))
        TestSupport.expectEqual(run.kind, .edit)
        TestSupport.expectEqual(run.producedOutput, true)
        TestSupport.expectEqual(run.spokenWordCount, 12)
        TestSupport.expectEqual(run.outputWordCount, 300)
    }

    private static func testFailedEditRow() {
        // A failed edit falls back to the untouched selection: the rewrite
        // must not count as dictated words.
        let run = StatsHistoryBackfill.run(for: StatsTestSupport.historyItem(
            intent: .commandManual,
            status: "Edit mode failed, using selected text (manual)",
            rawTranscript: StatsTestSupport.words(9),
            postProcessedTranscript: StatsTestSupport.words(300)
        ))
        TestSupport.expectEqual(run.kind, .edit)
        TestSupport.expectEqual(run.producedOutput, false)
        TestSupport.expectEqual(run.spokenWordCount, 0)
        TestSupport.expectEqual(run.outputWordCount, 0)
    }

    private static func testErrorRow() {
        let run = StatsHistoryBackfill.run(for: StatsTestSupport.historyItem(
            status: "Error: transcription failed",
            rawTranscript: StatsTestSupport.words(10),
            postProcessedTranscript: ""
        ))
        TestSupport.expectEqual(run.producedOutput, false)
        TestSupport.expectEqual(run.spokenWordCount, 0)
        TestSupport.expectEqual(run.outputWordCount, 0)
    }

    private static func testMacroRow() {
        // Macro runs were persisted as dictation intents; the status line
        // recovers the kind so only spoken words count.
        let run = StatsHistoryBackfill.run(for: StatsTestSupport.historyItem(
            status: "Voice macro used: standup",
            rawTranscript: StatsTestSupport.words(2),
            postProcessedTranscript: StatsTestSupport.words(60)
        ))
        TestSupport.expectEqual(run.kind, .macro)
        TestSupport.expectEqual(run.producedOutput, true)
        TestSupport.expectEqual(run.spokenWordCount, 2)
        TestSupport.expectEqual(run.outputWordCount, 60)
    }

    private static func testEmptyOutputRow() {
        let run = StatsHistoryBackfill.run(for: StatsTestSupport.historyItem(
            status: "Skipped macros and post-processing for empty raw transcript",
            rawTranscript: "",
            postProcessedTranscript: ""
        ))
        TestSupport.expectEqual(run.producedOutput, false)
        TestSupport.expectEqual(run.spokenWordCount, 0)
        TestSupport.expectEqual(run.outputWordCount, 0)
    }
}
