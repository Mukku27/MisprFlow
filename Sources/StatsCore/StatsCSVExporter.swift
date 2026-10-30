import Foundation

/// Day-granular stats export. Numbers only: day, counts, durations, and
/// speeds. No transcripts, timestamps, or identifying metadata.
enum StatsCSVExporter {
    static let header = "day,dictations,attempts,words,speaking_sec,time_saved_sec,avg_wpm,baseline_wpm"

    static func csv(dailies: [DailyStat], baselineWPM: Int) -> String {
        var lines = [header]
        for daily in dailies.sorted(by: { $0.dayKey < $1.dayKey }) {
            let wpm = daily.avgWPM.map(StatsCalculator.format1) ?? ""
            lines.append([
                daily.dayKey,
                String(daily.dictations),
                String(daily.attempts),
                String(daily.words),
                StatsCalculator.format1(daily.speakingSec),
                StatsCalculator.format1(daily.timeSavedSec),
                wpm,
                String(baselineWPM)
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
