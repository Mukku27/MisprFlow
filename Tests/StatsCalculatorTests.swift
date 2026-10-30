import Foundation

enum StatsCalculatorTests {
    static func run() {
        testMakeRun()
        testMakeRunNeverProducesEmptyOutput()
        testStreaks()
        testAggregatesExcludeFailures()
        testAggregatesExcludeUnknownDurationsFromSpeed()
        testAggregatesExcludeShortRunsFromWPM()
        testAggregatesUseSpokenWordsForWPM()
        testAggregatesCountEditAndMacroRuns()
        testOverallAverageIsTotalOverTotal()
        testLast14IsZeroFilled()
        testHeatmapDaysIsZeroFilled252()
        testStreakDayKeys()
        testBestDayTieBreaksEarliest()
        testMostActiveTieBreaksEarliest()
        testWeekOverWeekUsesCompleteDays()
        testSummaryLine()
        testFormatters()
        testCSVExport()
    }

    private static func testMakeRun() {
        let run = StatsCalculator.makeRun(
            kind: .dictation,
            producedOutput: true,
            spokenText: "  hello world  ",
            outputText: "Hello, world! Polished.",
            audioDurationSec: 60
        )
        TestSupport.expectEqual(run.producedOutput, true)
        TestSupport.expectEqual(run.spokenWordCount, 2)
        TestSupport.expectEqual(run.outputWordCount, 3)
        TestSupport.expectEqual(run.audioDurationSec, 60)
    }

    private static func testMakeRunNeverProducesEmptyOutput() {
        let run = StatsCalculator.makeRun(
            kind: .dictation,
            producedOutput: true,
            spokenText: "   ",
            outputText: "   ",
            audioDurationSec: 60
        )
        TestSupport.expectEqual(run.producedOutput, false)
        TestSupport.expectEqual(run.spokenWordCount, 0)
        TestSupport.expectEqual(run.outputWordCount, 0)
    }

    private static func testStreaks() {
        let calendar = StatsTestSupport.gmtCalendar()
        let today = StatsTestSupport.date(2026, 9, 11)

        // Missing today starts counting from yesterday without penalty.
        var result = StatsCalculator.streaks(
            qualifyingDayKeys: ["2026-09-10", "2026-09-09"],
            calendar: calendar,
            today: today
        )
        TestSupport.expectEqual(result.current, 2)
        TestSupport.expectEqual(result.longest, 2)

        // A gap breaks the current streak.
        result = StatsCalculator.streaks(
            qualifyingDayKeys: ["2026-09-11", "2026-09-09"],
            calendar: calendar,
            today: today
        )
        TestSupport.expectEqual(result.current, 1)
        TestSupport.expectEqual(result.longest, 1)

        // Longest spans the full history, current counts back from today.
        result = StatsCalculator.streaks(
            qualifyingDayKeys: [
                "2026-09-01", "2026-09-02", "2026-09-03", "2026-09-04", "2026-09-05",
                "2026-09-10", "2026-09-11"
            ],
            calendar: calendar,
            today: today
        )
        TestSupport.expectEqual(result.current, 2)
        TestSupport.expectEqual(result.longest, 5)

        result = StatsCalculator.streaks(qualifyingDayKeys: [], calendar: calendar, today: today)
        TestSupport.expectEqual(result.current, 0)
        TestSupport.expectEqual(result.longest, 0)
    }

    private static func testAggregatesExcludeFailures() {
        let events = [
            StatsTestSupport.dictationEvent(timestamp: StatsTestSupport.date(2026, 9, 11, 9), words: 100, durationSec: 60),
            StatsTestSupport.runEvent(
                timestamp: StatsTestSupport.date(2026, 9, 11, 10),
                kind: .dictation,
                producedOutput: false,
                spokenWords: 0,
                outputWords: 0,
                durationSec: 60
            )
        ]
        let dailies = StatsCalculator.dailies(events: events, baselineWPM: 40, calendar: StatsTestSupport.gmtCalendar())
        TestSupport.expectEqual(dailies.count, 1)
        TestSupport.expectEqual(dailies[0].words, 100)
        TestSupport.expectEqual(dailies[0].dictations, 1)
        TestSupport.expectEqual(dailies[0].attempts, 2)
        TestSupport.expectApproximatelyEqual(dailies[0].speakingSec, 60)
    }

    private static func testAggregatesExcludeUnknownDurationsFromSpeed() {
        // Backfilled rows carry words but no duration: they count toward
        // words and streaks, never toward speaking time or speed.
        let events = [
            StatsTestSupport.dictationEvent(timestamp: StatsTestSupport.date(2026, 9, 11, 9), words: 80, durationSec: nil),
            StatsTestSupport.dictationEvent(timestamp: StatsTestSupport.date(2026, 9, 11, 10), words: 120, durationSec: 60)
        ]
        let snapshot = StatsCalculator.snapshot(
            events: events,
            baselineWPM: 40,
            calendar: StatsTestSupport.gmtCalendar(),
            today: StatsTestSupport.date(2026, 9, 11, 18)
        )
        TestSupport.expectEqual(snapshot.totalWords, 200)
        TestSupport.expectApproximatelyEqual(snapshot.totalSpeakingSec, 60)
        TestSupport.expectApproximatelyEqual(snapshot.overallAvgWPM ?? 0, 120)
        TestSupport.expectEqual(snapshot.currentStreakDays, 1)
    }

    private static func testAggregatesExcludeShortRunsFromWPM() {
        let events = [
            StatsTestSupport.dictationEvent(timestamp: StatsTestSupport.date(2026, 9, 11, 9), words: 120, durationSec: 60),
            StatsTestSupport.dictationEvent(timestamp: StatsTestSupport.date(2026, 9, 11, 10), words: 2, durationSec: 1)
        ]
        let snapshot = StatsCalculator.snapshot(
            events: events,
            baselineWPM: 40,
            calendar: StatsTestSupport.gmtCalendar(),
            today: StatsTestSupport.date(2026, 9, 11, 18)
        )
        TestSupport.expectEqual(snapshot.totalWords, 122)
        TestSupport.expectEqual(snapshot.totalDictations, 2)
        TestSupport.expectApproximatelyEqual(snapshot.overallAvgWPM ?? 0, 120)
    }

    private static func testAggregatesUseSpokenWordsForWPM() {
        let events = [
            StatsTestSupport.runEvent(
                timestamp: StatsTestSupport.date(2026, 9, 11, 9),
                kind: .dictation,
                producedOutput: true,
                spokenWords: 100,
                outputWords: 80,
                durationSec: 60
            )
        ]
        let snapshot = StatsCalculator.snapshot(
            events: events,
            baselineWPM: 40,
            calendar: StatsTestSupport.gmtCalendar(),
            today: StatsTestSupport.date(2026, 9, 11, 18)
        )
        TestSupport.expectEqual(snapshot.totalWords, 80)
        TestSupport.expectApproximatelyEqual(snapshot.overallAvgWPM ?? 0, 100)
        TestSupport.expectApproximatelyEqual(snapshot.totalTimeSavedSec, 60)
        TestSupport.expectEqual(
            StatsCalculator.summaryLine(for: events[0], baselineWPM: 40),
            "80w · 1:00 · 100 WPM · +1m"
        )
    }

    private static func testAggregatesCountEditAndMacroRuns() {
        // Edit and macro runs contribute spoken words toward dictations and
        // streaks, but never toward speed or time saved.
        let events = [
            StatsTestSupport.dictationEvent(timestamp: StatsTestSupport.date(2026, 9, 11, 9), words: 120, durationSec: 60),
            StatsTestSupport.runEvent(
                timestamp: StatsTestSupport.date(2026, 9, 11, 10),
                kind: .edit,
                producedOutput: true,
                spokenWords: 12,
                outputWords: 300,
                durationSec: 3
            ),
            StatsTestSupport.runEvent(
                timestamp: StatsTestSupport.date(2026, 9, 11, 11),
                kind: .macro,
                producedOutput: true,
                spokenWords: 2,
                outputWords: 60,
                durationSec: 1.5
            )
        ]
        let snapshot = StatsCalculator.snapshot(
            events: events,
            baselineWPM: 40,
            calendar: StatsTestSupport.gmtCalendar(),
            today: StatsTestSupport.date(2026, 9, 11, 18)
        )
        TestSupport.expectEqual(snapshot.totalWords, 134)
        TestSupport.expectEqual(snapshot.totalDictations, 3)
        TestSupport.expectApproximatelyEqual(snapshot.overallAvgWPM ?? 0, 120)
        TestSupport.expectApproximatelyEqual(snapshot.totalTimeSavedSec, 120)
        TestSupport.expectApproximatelyEqual(snapshot.totalSpeakingSec, 64.5)
    }

    private static func testOverallAverageIsTotalOverTotal() {
        // 60w/60s + 240w/120s = 300w/180s = 100 WPM, not the mean of 60 and 120.
        let events = [
            StatsTestSupport.dictationEvent(timestamp: StatsTestSupport.date(2026, 9, 11, 9), words: 60, durationSec: 60),
            StatsTestSupport.dictationEvent(timestamp: StatsTestSupport.date(2026, 9, 11, 10), words: 240, durationSec: 120)
        ]
        let snapshot = StatsCalculator.snapshot(
            events: events,
            baselineWPM: 40,
            calendar: StatsTestSupport.gmtCalendar(),
            today: StatsTestSupport.date(2026, 9, 11, 18)
        )
        TestSupport.expectApproximatelyEqual(snapshot.overallAvgWPM ?? 0, 100)
    }

    private static func testLast14IsZeroFilled() {
        let events = [
            StatsTestSupport.dictationEvent(timestamp: StatsTestSupport.date(2026, 9, 1, 9), words: 50, durationSec: 60),
            StatsTestSupport.dictationEvent(timestamp: StatsTestSupport.date(2026, 9, 11, 9), words: 100, durationSec: 60)
        ]
        let snapshot = StatsCalculator.snapshot(
            events: events,
            baselineWPM: 40,
            calendar: StatsTestSupport.gmtCalendar(),
            today: StatsTestSupport.date(2026, 9, 11, 18)
        )
        TestSupport.expectEqual(snapshot.last14.count, 14)
        TestSupport.expectEqual(snapshot.last14.first?.dayKey, "2026-08-29")
        TestSupport.expectEqual(snapshot.last14.last?.dayKey, "2026-09-11")
        TestSupport.expectEqual(snapshot.last14.last?.words, 100)
        TestSupport.expectEqual(snapshot.last14[1].words, 0)
        TestSupport.expectEqual(snapshot.last14[1].avgWPM, nil)
        TestSupport.expectEqual(snapshot.today.words, 100)
    }

    private static func testBestDayTieBreaksEarliest() {
        let events = [
            StatsTestSupport.dictationEvent(timestamp: StatsTestSupport.date(2026, 9, 9, 9), words: 100, durationSec: 60),
            StatsTestSupport.dictationEvent(timestamp: StatsTestSupport.date(2026, 9, 10, 9), words: 100, durationSec: 60)
        ]
        let snapshot = StatsCalculator.snapshot(
            events: events,
            baselineWPM: 40,
            calendar: StatsTestSupport.gmtCalendar(),
            today: StatsTestSupport.date(2026, 9, 11, 18)
        )
        TestSupport.expectEqual(snapshot.bestDay?.dayKey, "2026-09-09")
    }

    private static func testMostActiveTieBreaksEarliest() {
        let events = [
            StatsTestSupport.dictationEvent(timestamp: StatsTestSupport.date(2026, 9, 9, 9), words: 10, durationSec: 60),
            StatsTestSupport.dictationEvent(timestamp: StatsTestSupport.date(2026, 9, 10, 14), words: 10, durationSec: 60)
        ]
        let snapshot = StatsCalculator.snapshot(
            events: events,
            baselineWPM: 40,
            calendar: StatsTestSupport.gmtCalendar(),
            today: StatsTestSupport.date(2026, 9, 11, 18)
        )
        TestSupport.expectEqual(snapshot.mostActiveHour, 9)
    }

    private static func testWeekOverWeekUsesCompleteDays() {
        let calendar = StatsTestSupport.gmtCalendar()
        let today = StatsTestSupport.date(2026, 9, 11, 18)
        // Last-7 window: 09-04..09-10. Prior-7 window: 08-28..09-03.
        let priorWeek = StatsTestSupport.dictationEvent(timestamp: StatsTestSupport.date(2026, 9, 1, 9), words: 100, durationSec: 60)
        let thisWeek = StatsTestSupport.dictationEvent(timestamp: StatsTestSupport.date(2026, 9, 10, 9), words: 200, durationSec: 60)
        let grown = StatsCalculator.snapshot(
            events: [priorWeek, thisWeek],
            baselineWPM: 40,
            calendar: calendar,
            today: today
        )
        TestSupport.expectApproximatelyEqual(grown.weekOverWeekPct ?? 0, 100)

        // A partial today must not move the comparison.
        let todayBurst = StatsTestSupport.dictationEvent(timestamp: StatsTestSupport.date(2026, 9, 11, 9), words: 1000, durationSec: 60)
        let withToday = StatsCalculator.snapshot(
            events: [priorWeek, thisWeek, todayBurst],
            baselineWPM: 40,
            calendar: calendar,
            today: today
        )
        TestSupport.expectApproximatelyEqual(withToday.weekOverWeekPct ?? 0, 100)

        let noPrior = StatsCalculator.snapshot(
            events: [thisWeek],
            baselineWPM: 40,
            calendar: calendar,
            today: today
        )
        TestSupport.expectEqual(noPrior.weekOverWeekPct, nil)
    }

    private static func testSummaryLine() {
        let full = StatsTestSupport.dictationEvent(timestamp: StatsTestSupport.date(2026, 9, 11, 9), words: 142, durationSec: 48)
        TestSupport.expectEqual(
            StatsCalculator.summaryLine(for: full, baselineWPM: 40),
            "142w · 0:48 · 178 WPM · +2m 45s"
        )
        let unknown = StatsTestSupport.dictationEvent(timestamp: StatsTestSupport.date(2026, 9, 11, 9), words: 80, durationSec: nil)
        TestSupport.expectEqual(StatsCalculator.summaryLine(for: unknown, baselineWPM: 40), "80w · —")
        let short = StatsTestSupport.dictationEvent(timestamp: StatsTestSupport.date(2026, 9, 11, 9), words: 2, durationSec: 1)
        TestSupport.expectEqual(
            StatsCalculator.summaryLine(for: short, baselineWPM: 40),
            "2w · 0:01 · too short for WPM"
        )
        let failed = StatsTestSupport.runEvent(
            timestamp: StatsTestSupport.date(2026, 9, 11, 9),
            kind: .dictation,
            producedOutput: false,
            spokenWords: 0,
            outputWords: 0,
            durationSec: 60
        )
        TestSupport.expectEqual(StatsCalculator.summaryLine(for: failed, baselineWPM: 40), nil)
        let edit = StatsTestSupport.runEvent(
            timestamp: StatsTestSupport.date(2026, 9, 11, 9),
            kind: .edit,
            producedOutput: true,
            spokenWords: 12,
            outputWords: 300,
            durationSec: 3
        )
        TestSupport.expectEqual(StatsCalculator.summaryLine(for: edit, baselineWPM: 40), "12w · 0:03")
    }

    private static func testFormatters() {
        TestSupport.expectEqual(StatsCalculator.formatClock(48), "0:48")
        TestSupport.expectEqual(StatsCalculator.formatClock(754), "12:34")
        TestSupport.expectEqual(StatsCalculator.formatClock(3723), "1:02:03")
        TestSupport.expectEqual(StatsCalculator.formatSavedShort(42), "+42s")
        TestSupport.expectEqual(StatsCalculator.formatSavedShort(165), "+2m 45s")
        TestSupport.expectEqual(StatsCalculator.formatSavedShort(120), "+2m")
        TestSupport.expectEqual(StatsCalculator.formatSavedShort(3900), "+1h 5m")
        TestSupport.expectEqual(StatsCalculator.formatTotalTime(42), "42s")
        TestSupport.expectEqual(StatsCalculator.formatTotalTime(720), "12m")
        TestSupport.expectEqual(StatsCalculator.formatTotalTime(50760), "14.1 hrs")
        TestSupport.expectEqual(StatsCalculator.formatWPM(177.5), "178 WPM")
        TestSupport.expectEqual(StatsCalculator.formatWPM(nil), "—")
        TestSupport.expectEqual(StatsCalculator.format1(512.0), "512.0")
        TestSupport.expectEqual(StatsCalculator.format1(145.25), "145.3")
    }

    private static func testCSVExport() {
        let events = [
            StatsTestSupport.dictationEvent(timestamp: StatsTestSupport.date(2026, 9, 10, 9), words: 120, durationSec: 60),
            StatsTestSupport.runEvent(
                timestamp: StatsTestSupport.date(2026, 9, 10, 10),
                kind: .dictation,
                producedOutput: false,
                spokenWords: 0,
                outputWords: 0,
                durationSec: 60
            )
        ]
        let dailies = StatsCalculator.dailies(events: events, baselineWPM: 40, calendar: StatsTestSupport.gmtCalendar())
        TestSupport.expectEqual(
            StatsCSVExporter.csv(dailies: dailies, baselineWPM: 40),
            "day,dictations,attempts,words,speaking_sec,time_saved_sec,avg_wpm,baseline_wpm\n"
                + "2026-09-10,1,2,120,60.0,120.0,120.0,40\n"
        )
        TestSupport.expectEqual(
            StatsCSVExporter.csv(dailies: [], baselineWPM: 40),
            "day,dictations,attempts,words,speaking_sec,time_saved_sec,avg_wpm,baseline_wpm\n"
        )
    }

    private static func testHeatmapDaysIsZeroFilled252() {
        let calendar = StatsTestSupport.gmtCalendar()
        let today = StatsTestSupport.date(2026, 9, 11)
        let events = [StatsTestSupport.dictationEvent(timestamp: today, words: 100)]
        let snapshot = StatsCalculator.snapshot(
            events: events, baselineWPM: 40, calendar: calendar, today: today
        )
        TestSupport.expectEqual(snapshot.heatmapDays.count, 252)
        TestSupport.expectEqual(snapshot.heatmapDays.first?.dayKey, "2026-01-03")
        TestSupport.expectEqual(snapshot.heatmapDays.last?.dayKey, "2026-09-11")
        TestSupport.expectEqual(snapshot.heatmapDays.last?.words, 100)
        TestSupport.expectEqual(snapshot.heatmapDays[0].words, 0)
        TestSupport.expectEqual(snapshot.heatmapDays[0].avgWPM, nil)
        // The extraction must not change the existing window.
        TestSupport.expectEqual(snapshot.last14.count, 14)
    }

    private static func testStreakDayKeys() {
        let calendar = StatsTestSupport.gmtCalendar()
        let today = StatsTestSupport.date(2026, 9, 11)

        // A gap breaks the run: the 8th is excluded.
        var keys = StatsCalculator.streakDayKeys(
            qualifyingDayKeys: ["2026-09-11", "2026-09-10", "2026-09-08"],
            calendar: calendar,
            today: today
        )
        TestSupport.expectEqual(keys, ["2026-09-11", "2026-09-10"])

        // Missing today starts from yesterday without penalty.
        keys = StatsCalculator.streakDayKeys(
            qualifyingDayKeys: ["2026-09-10", "2026-09-09"],
            calendar: calendar,
            today: today
        )
        TestSupport.expectEqual(keys, ["2026-09-10", "2026-09-09"])

        // Empty history: no keys.
        keys = StatsCalculator.streakDayKeys(
            qualifyingDayKeys: [],
            calendar: calendar,
            today: today
        )
        TestSupport.expectEqual(keys.isEmpty, true)
    }
}
