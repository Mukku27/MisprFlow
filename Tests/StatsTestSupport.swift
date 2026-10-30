import Foundation

/// Shared synthetic fixtures for stats tests. All data is invented; no test
/// may use real transcripts, selections, or user metadata.
enum StatsTestSupport {
    static func gmtCalendar() -> Calendar {
        StatsCalendar.make(timeZone: TimeZone(secondsFromGMT: 0)!)
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        gmtCalendar().date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    static func words(_ count: Int) -> String {
        Array(repeating: "word", count: count).joined(separator: " ")
    }

    static func dictationEvent(
        timestamp: Date,
        words: Int,
        durationSec: Double? = 60,
        producedOutput: Bool = true,
        bundleID: String? = nil,
        appName: String? = nil
    ) -> DictationStatEvent {
        let produced = producedOutput && words > 0
        return runEvent(
            timestamp: timestamp,
            kind: .dictation,
            producedOutput: produced,
            spokenWords: words,
            outputWords: words,
            durationSec: durationSec,
            bundleID: bundleID,
            appName: appName
        )
    }

    static func runEvent(
        timestamp: Date,
        kind: StatsRunKind,
        producedOutput: Bool,
        spokenWords: Int,
        outputWords: Int,
        durationSec: Double?,
        bundleID: String? = nil,
        appName: String? = nil
    ) -> DictationStatEvent {
        DictationStatEvent(
            timestamp: timestamp,
            day: StatsDay(date: timestamp, calendar: gmtCalendar()),
            run: StatsRunRecord(
                kind: kind,
                producedOutput: producedOutput,
                spokenWordCount: producedOutput ? spokenWords : 0,
                outputWordCount: producedOutput ? outputWords : 0,
                audioDurationSec: durationSec
            ),
            bundleID: bundleID,
            appName: appName
        )
    }

    static func historyItem(
        intent: PipelineHistoryItemIntent = .dictation,
        status: String,
        rawTranscript: String,
        postProcessedTranscript: String
    ) -> PipelineHistoryItem {
        PipelineHistoryItem(
            intent: intent,
            timestamp: date(2026, 9, 10, 9),
            rawTranscript: rawTranscript,
            postProcessedTranscript: postProcessedTranscript,
            postProcessingPrompt: nil,
            contextSummary: "synthetic summary",
            contextScreenshotDataURL: nil,
            contextScreenshotStatus: "synthetic status",
            postProcessingStatus: status,
            debugStatus: "synthetic debug",
            customVocabulary: ""
        )
    }
}
