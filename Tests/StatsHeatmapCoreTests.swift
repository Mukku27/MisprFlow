import Foundation

enum StatsHeatmapCoreTests {
    static func run() {
        testBucket()
        testBucketEmptyRange()
        testColumnsSundayStart()
        testColumnsPadsLeadingAndTrailing()
        testColumnsEmpty()
        testTooltipLines()
    }

    private static func testBucket() {
        // Quartile boundaries against a visible max of 100.
        TestSupport.expectEqual(StatsHeatmapCore.bucket(words: 0, maxWords: 100), 0)
        TestSupport.expectEqual(StatsHeatmapCore.bucket(words: 1, maxWords: 100), 1)
        TestSupport.expectEqual(StatsHeatmapCore.bucket(words: 25, maxWords: 100), 1)
        TestSupport.expectEqual(StatsHeatmapCore.bucket(words: 26, maxWords: 100), 2)
        TestSupport.expectEqual(StatsHeatmapCore.bucket(words: 50, maxWords: 100), 2)
        TestSupport.expectEqual(StatsHeatmapCore.bucket(words: 51, maxWords: 100), 3)
        TestSupport.expectEqual(StatsHeatmapCore.bucket(words: 75, maxWords: 100), 3)
        TestSupport.expectEqual(StatsHeatmapCore.bucket(words: 76, maxWords: 100), 4)
        TestSupport.expectEqual(StatsHeatmapCore.bucket(words: 100, maxWords: 100), 4)
    }

    private static func testBucketEmptyRange() {
        // No data in range: everything maps to empty, never divides by zero.
        TestSupport.expectEqual(StatsHeatmapCore.bucket(words: 0, maxWords: 0), 0)
        TestSupport.expectEqual(StatsHeatmapCore.bucket(words: 5, maxWords: 0), 0)
        TestSupport.expectEqual(StatsHeatmapCore.bucket(words: -3, maxWords: 100), 0)
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int, words: Int = 10) -> DailyStat {
        let date = StatsTestSupport.date(year, month, day)
        return DailyStat(
            dayKey: StatsCalendar.dayKey(for: date, calendar: StatsTestSupport.gmtCalendar()),
            date: date,
            words: words,
            dictations: 1,
            attempts: 1,
            speakingSec: 60,
            timeSavedSec: 0,
            avgWPM: 60
        )
    }

    private static func testColumnsSundayStart() {
        // 2026-08-30 is a Sunday: two full weeks, no padding.
        var days: [DailyStat] = []
        for offset in 0..<14 {
            let date = StatsTestSupport.gmtCalendar().date(
                byAdding: .day, value: offset, to: StatsTestSupport.date(2026, 8, 30)
            )!
            let components = StatsTestSupport.gmtCalendar().dateComponents([.year, .month, .day], from: date)
            days.append(day(components.year!, components.month!, components.day!))
        }
        let columns = StatsHeatmapCore.columns(days: days, calendar: StatsTestSupport.gmtCalendar())
        TestSupport.expectEqual(columns.count, 2)
        TestSupport.expectEqual(columns[0].count, 7)
        TestSupport.expectEqual(columns[0][0]?.dayKey, "2026-08-30")
        TestSupport.expectEqual(columns[1][6]?.dayKey, "2026-09-12")
        TestSupport.expectEqual(columns.flatMap { $0 }.compactMap { $0 }.count, 14)
    }

    private static func testColumnsPadsLeadingAndTrailing() {
        // Wed 2026-09-09 .. Fri 2026-09-11: 3 leading blanks (Sun/Tue),
        // 1 trailing blank (Sat, a future day that must not read as zero).
        let days = [day(2026, 9, 9), day(2026, 9, 10), day(2026, 9, 11)]
        let columns = StatsHeatmapCore.columns(days: days, calendar: StatsTestSupport.gmtCalendar())
        TestSupport.expectEqual(columns.count, 1)
        TestSupport.expectEqual(
            columns[0].map { $0?.dayKey },
            [nil, nil, nil, "2026-09-09", "2026-09-10", "2026-09-11", nil]
        )
    }

    private static func testColumnsEmpty() {
        let columns = StatsHeatmapCore.columns(days: [], calendar: StatsTestSupport.gmtCalendar())
        TestSupport.expectEqual(columns.count, 0)
    }

    private static func testTooltipLines() {
        TestSupport.expectEqual(StatsHeatmapCore.wordsLine(1), "1 word")
        TestSupport.expectEqual(StatsHeatmapCore.wordsLine(255), "255 words")
        TestSupport.expectEqual(StatsHeatmapCore.speedLine(words: 0, avgWPM: nil), "No dictations")
        TestSupport.expectEqual(StatsHeatmapCore.speedLine(words: 10, avgWPM: nil), "—")
        TestSupport.expectEqual(StatsHeatmapCore.speedLine(words: 255, avgWPM: 72.4), "72 WPM")
    }
}
