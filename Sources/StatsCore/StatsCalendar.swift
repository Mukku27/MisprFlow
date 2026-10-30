import Foundation

/// Fixed Gregorian calendar for stats day math.
///
/// The system calendar can be non-Gregorian (Buddhist, Japanese, ...) and the
/// time zone can change between launches. Stats freeze the day facts (day
/// key, hour, weekday) at record time on a Gregorian calendar in the
/// then-local time zone, so charts and streaks never reinterpret timestamps.
enum StatsCalendar {
    static func make(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(zeroPadded(components.year ?? 0, width: 4))-\(zeroPadded(components.month ?? 0))-\(zeroPadded(components.day ?? 0))"
    }

    static func date(fromDayKey dayKey: String, calendar: Calendar) -> Date? {
        let parts = dayKey.split(separator: "-")
        guard parts.count == 3,
            let year = Int(parts[0]),
            let month = Int(parts[1]),
            let day = Int(parts[2])
        else {
            return nil
        }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private static func zeroPadded(_ value: Int, width: Int = 2) -> String {
        let text = String(value)
        if text.count >= width {
            return text
        }
        return String(repeating: "0", count: width - text.count) + text
    }
}

/// Day facts frozen at record time: a Gregorian `yyyy-MM-dd` key plus the
/// local hour and weekday the run happened in.
struct StatsDay: Equatable, Sendable {
    let key: String
    /// 0-23 in the then-local time zone.
    let hour: Int
    /// 1-7, Sunday-first, in the then-local time zone.
    let weekday: Int

    init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .weekday], from: date)
        self.key = StatsCalendar.dayKey(for: date, calendar: calendar)
        self.hour = components.hour ?? 0
        self.weekday = components.weekday ?? 1
    }

    init(key: String, hour: Int, weekday: Int) {
        self.key = key
        self.hour = hour
        self.weekday = weekday
    }
}
