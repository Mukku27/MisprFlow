import Foundation

enum StatsCalendarTests {
    static func run() {
        testDayKeyBoundaries()
        testDayKeyIsGregorian()
        testStatsDayFreezesFacts()
        testDateFromDayKeyRoundTrip()
        testDateFromDayKeyRejectsGarbage()
        testStreaksAcrossDaylightSaving()
    }

    private static func testDayKeyBoundaries() {
        let calendar = StatsTestSupport.gmtCalendar()
        TestSupport.expectEqual(
            StatsCalendar.dayKey(for: StatsTestSupport.date(2026, 9, 10, 23, 59), calendar: calendar),
            "2026-09-10"
        )
        TestSupport.expectEqual(
            StatsCalendar.dayKey(for: StatsTestSupport.date(2026, 9, 11, 0, 1), calendar: calendar),
            "2026-09-11"
        )
    }

    private static func testDayKeyIsGregorian() {
        // A Buddhist calendar reports year 2569 for the same instant; stats
        // keys stay Gregorian regardless of the system calendar.
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = StatsTestSupport.date(2026, 9, 11, 9)
        TestSupport.expect(
            buddhist.component(.year, from: date) != 2026,
            "Test setup should use a non-Gregorian calendar year"
        )
        TestSupport.expectEqual(
            StatsCalendar.dayKey(for: date, calendar: StatsTestSupport.gmtCalendar()),
            "2026-09-11"
        )
    }

    private static func testStatsDayFreezesFacts() {
        // 2026-09-10 23:30 in GMT+2 freezes to that local day, hour, and
        // weekday even though the instant is 21:30 UTC.
        let plusTwo = StatsCalendar.make(timeZone: TimeZone(secondsFromGMT: 7200)!)
        let date = plusTwo.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 23, minute: 30))!
        let day = StatsDay(date: date, calendar: plusTwo)
        TestSupport.expectEqual(day.key, "2026-09-10")
        TestSupport.expectEqual(day.hour, 23)
        // 2026-09-10 is a Thursday; Sunday-first weekday is 5.
        TestSupport.expectEqual(day.weekday, 5)
    }

    private static func testDateFromDayKeyRoundTrip() {
        let calendar = StatsTestSupport.gmtCalendar()
        guard let date = StatsCalendar.date(fromDayKey: "2026-09-11", calendar: calendar) else {
            TestSupport.expect(false, "Day key should parse")
            return
        }
        TestSupport.expectEqual(date, StatsTestSupport.date(2026, 9, 11, 0))
        TestSupport.expectEqual(StatsCalendar.dayKey(for: date, calendar: calendar), "2026-09-11")
    }

    private static func testDateFromDayKeyRejectsGarbage() {
        let calendar = StatsTestSupport.gmtCalendar()
        TestSupport.expectEqual(StatsCalendar.date(fromDayKey: "", calendar: calendar), nil)
        TestSupport.expectEqual(StatsCalendar.date(fromDayKey: "2026-09", calendar: calendar), nil)
        TestSupport.expectEqual(StatsCalendar.date(fromDayKey: "not-a-date", calendar: calendar), nil)
    }

    private static func testStreaksAcrossDaylightSaving() {
        // US daylight saving starts 2026-03-08. Consecutive local days
        // still form an unbroken streak across the short day.
        let newYork = StatsCalendar.make(timeZone: TimeZone(identifier: "America/New_York")!)
        let today = newYork.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12))!
        let result = StatsCalculator.streaks(
            qualifyingDayKeys: ["2026-03-07", "2026-03-08", "2026-03-09"],
            calendar: newYork,
            today: today
        )
        TestSupport.expectEqual(result.current, 3)
        TestSupport.expectEqual(result.longest, 3)
    }
}
