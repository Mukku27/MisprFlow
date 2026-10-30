import Foundation

/// Pure heatmap math for the Words contribution grid. Foundation-only so the
/// deterministic test runner can exercise it; SwiftUI color mapping lives in
/// `WordsHeatmapView` and stays untested.
enum StatsHeatmapCore {
    /// Days shown in the heatmap: 36 weeks.
    static let visibleDayCount = 252

    /// Bucket for a day's word count: 0 (empty) through 4 (darkest), using
    /// relative quartiles of the visible max so the scale self-normalizes.
    /// `maxWords <= 0` (no data in range) maps everything to 0.
    static func bucket(words: Int, maxWords: Int) -> Int {
        guard words > 0, maxWords > 0 else { return 0 }
        let ratio = Double(words) / Double(maxWords)
        if ratio <= 0.25 { return 1 }
        if ratio <= 0.5 { return 2 }
        if ratio <= 0.75 { return 3 }
        return 4
    }

    /// Groups consecutive days (oldest-first) into Sunday-first week columns
    /// for display. Leading `nil`s pad the first column so rows stay
    /// weekday-aligned; trailing `nil`s pad the final column past today so
    /// future days render as blank spacers, never as zero-activity cells.
    static func columns(days: [DailyStat], calendar: Calendar) -> [[DailyStat?]] {
        guard let first = days.first else { return [] }
        let firstWeekday = calendar.component(.weekday, from: first.date)
        var cells: [DailyStat?] = Array(repeating: nil, count: max(0, firstWeekday - 1))
        cells += days.map { Optional($0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0 ..< $0 + 7]) }
    }

    static func wordsLine(_ words: Int) -> String {
        words == 1 ? "1 word" : "\(words) words"
    }

    /// Hover-card speed line. Zero words means no dictations that day; a
    /// missing average means the day's runs were too short for WPM.
    static func speedLine(words: Int, avgWPM: Double?) -> String {
        guard words > 0 else { return "No dictations" }
        guard let avgWPM else { return "—" }
        return "\(Int(avgWPM.rounded())) WPM"
    }
}
