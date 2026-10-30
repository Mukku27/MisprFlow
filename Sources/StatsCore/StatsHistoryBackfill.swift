import Foundation

/// One-time translation of legacy pipeline-history rows into stats facts.
///
/// This is the only place that interprets the persisted human-readable
/// post-processing statuses ("Error: …", "Edit mode failed, …",
/// "Voice macro used: …"). New runs carry typed outcomes instead; the string
/// parsing here exists solely because legacy rows predate it.
enum StatsHistoryBackfill {
    static func run(for item: PipelineHistoryItem) -> StatsRunRecord {
        let outputWords = StatsPolicy.wordCount(item.postProcessedTranscript.trimmingCharacters(in: .whitespacesAndNewlines))
        let failed = item.postProcessingStatus.hasPrefix("Error:")
            || item.postProcessingStatus.hasPrefix("Edit mode failed")
            || item.postProcessingStatus.hasPrefix("Agent task failed")
            || item.postProcessingStatus.hasPrefix("Agent edit failed")
        let kind: StatsRunKind
        if item.postProcessingStatus.hasPrefix("Voice macro used:") {
            kind = .macro
        } else {
            switch item.intent {
            case .dictation:
                kind = .dictation
            case .commandAutomatic, .commandManual,
                .agentTask, .agentEdit:
                kind = .edit
            }
        }
        let producedOutput = !failed && outputWords > 0
        let spokenWords = StatsPolicy.wordCount(item.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines))
        return StatsRunRecord(
            kind: kind,
            producedOutput: producedOutput,
            spokenWordCount: producedOutput ? spokenWords : 0,
            outputWordCount: producedOutput ? outputWords : 0,
            audioDurationSec: nil
        )
    }
}
