import Foundation

/// Pure aggregation over stat events. All per-run semantics come from
/// ``StatsPolicy``; this file only groups, sums, and formats.
enum StatsCalculator {
    /// Reduces spoken/pasted text to numbers. The single place where user
    /// text becomes stats facts; the store only ever sees the result.
    static func makeRun(
        kind: StatsRunKind,
        producedOutput: Bool,
        spokenText: String,
        outputText: String,
        audioDurationSec: Double?
    ) -> StatsRunRecord {
        let spokenWords = StatsPolicy.wordCount(spokenText.trimmingCharacters(in: .whitespacesAndNewlines))
        let outputWords = StatsPolicy.wordCount(outputText.trimmingCharacters(in: .whitespacesAndNewlines))
        let effectiveProducedOutput = producedOutput && outputWords > 0
        return StatsRunRecord(
            kind: kind,
            producedOutput: effectiveProducedOutput,
            spokenWordCount: effectiveProducedOutput ? spokenWords : 0,
            outputWordCount: effectiveProducedOutput ? outputWords : 0,
            audioDurationSec: audioDurationSec
        )
    }

    static func dailies(
        events: [DictationStatEvent],
        baselineWPM: Int,
        calendar: Calendar
    ) -> [DailyStat] {
        let grouped = Dictionary(grouping: events, by: { $0.day.key })
        return grouped.map { (key, dayEvents) -> DailyStat in
            let date = StatsCalendar.date(fromDayKey: key, calendar: calendar)
                ?? calendar.startOfDay(for: dayEvents.first?.timestamp ?? Date())
            var words = 0
            var dictations = 0
            var speakingSec = 0.0
            var savedSec = 0.0
            var wpmWords = 0
            var wpmSec = 0.0
            for event in dayEvents {
                let contribution = StatsPolicy.contribution(of: event.run, baselineWPM: baselineWPM)
                guard contribution.countsAsDictation else { continue }
                dictations += 1
                words += contribution.words
                savedSec += contribution.timeSavedSec
                if let duration = event.run.audioDurationSec, duration > 0 {
                    speakingSec += duration
                }
                if let sample = contribution.speedSample {
                    wpmWords += sample.words
                    wpmSec += sample.seconds
                }
            }
            return DailyStat(
                dayKey: key,
                date: date,
                words: words,
                dictations: dictations,
                attempts: dayEvents.count,
                speakingSec: speakingSec,
                timeSavedSec: savedSec,
                avgWPM: wpmSec > 0 ? Double(wpmWords) / wpmSec * 60 : nil
            )
        }.sorted { $0.dayKey < $1.dayKey }
    }

    /// A day qualifies for streaks when it has at least one successful
    /// dictation. A missing today doesn't break the current streak; counting
    /// starts from yesterday in that case.
    static func streaks(
        qualifyingDayKeys: Set<String>,
        calendar: Calendar,
        today: Date = Date()
    ) -> (current: Int, longest: Int) {
        var current = 0
        var cursor = calendar.startOfDay(for: today)
        if !qualifyingDayKeys.contains(StatsCalendar.dayKey(for: cursor, calendar: calendar)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                return (0, longestStreak(qualifyingDayKeys: qualifyingDayKeys, calendar: calendar))
            }
            cursor = yesterday
        }
        while qualifyingDayKeys.contains(StatsCalendar.dayKey(for: cursor, calendar: calendar)) {
            current += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return (current, longestStreak(qualifyingDayKeys: qualifyingDayKeys, calendar: calendar))
    }

    /// Last `count` days ending today, zero-filled for days without events.
    /// `last14` and `heatmapDays` share this so windowing can't drift.
    static func trailingDays(
        count: Int,
        byDay: [String: DailyStat],
        calendar: Calendar,
        today: Date
    ) -> [DailyStat] {
        let startOfToday = calendar.startOfDay(for: today)
        var days: [DailyStat] = []
        days.reserveCapacity(count)
        for offset in stride(from: count - 1, through: 0, by: -1) {
            let date = calendar.date(byAdding: .day, value: -offset, to: startOfToday) ?? startOfToday
            let key = StatsCalendar.dayKey(for: date, calendar: calendar)
            if let daily = byDay[key] {
                days.append(daily)
            } else {
                days.append(DailyStat(
                    dayKey: key,
                    date: calendar.startOfDay(for: date),
                    words: 0,
                    dictations: 0,
                    attempts: 0,
                    speakingSec: 0,
                    timeSavedSec: 0,
                    avgWPM: nil
                ))
            }
        }
        return days
    }

    /// Day keys in the current streak (for heatmap outlining). Mirrors
    /// `streaks(_:calendar:today:)`: a missing today doesn't break the run.
    static func streakDayKeys(
        qualifyingDayKeys: Set<String>,
        calendar: Calendar,
        today: Date = Date()
    ) -> Set<String> {
        var keys: Set<String> = []
        var cursor = calendar.startOfDay(for: today)
        if !qualifyingDayKeys.contains(StatsCalendar.dayKey(for: cursor, calendar: calendar)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return keys }
            cursor = yesterday
        }
        while qualifyingDayKeys.contains(StatsCalendar.dayKey(for: cursor, calendar: calendar)) {
            keys.insert(StatsCalendar.dayKey(for: cursor, calendar: calendar))
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return keys
    }

    static func snapshot(
        events: [DictationStatEvent],
        baselineWPM: Int,
        calendar: Calendar,
        today: Date = Date(),
        categoryOverrides: [String: UsageCategory] = [:]
    ) -> StatsSnapshot {
        let allDailies = dailies(events: events, baselineWPM: baselineWPM, calendar: calendar)
        let byDay = Dictionary(
            allDailies.map { ($0.dayKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let qualifying = Set(allDailies.filter { $0.dictations > 0 }.map { $0.dayKey })
        let (currentStreak, longestStreak) = streaks(
            qualifyingDayKeys: qualifying,
            calendar: calendar,
            today: today
        )
        let startOfToday = calendar.startOfDay(for: today)
        let todayKey = StatsCalendar.dayKey(for: startOfToday, calendar: calendar)

        let last14 = trailingDays(count: 14, byDay: byDay, calendar: calendar, today: today)
        let heatmapDays = trailingDays(
            count: StatsHeatmapCore.visibleDayCount, byDay: byDay, calendar: calendar, today: today
        )
        let streakDayKeys = streakDayKeys(qualifyingDayKeys: qualifying, calendar: calendar, today: today)

        var bestDay: DailyStat?
        for daily in allDailies where daily.dictations > 0 {
            if let best = bestDay {
                if daily.words > best.words {
                    bestDay = daily
                }
            } else {
                bestDay = daily
            }
        }

        var wpmWords = 0
        var wpmSec = 0.0
        for event in events {
            if let sample = StatsPolicy.contribution(of: event.run, baselineWPM: baselineWPM).speedSample {
                wpmWords += sample.words
                wpmSec += sample.seconds
            }
        }

        // Week-over-week compares the 7 complete days ending yesterday
        // against the 7 before them, so a partial today never skews the
        // comparison.
        let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        var last7Words = 0
        var prior7Words = 0
        for offset in 0..<14 {
            let date = calendar.date(byAdding: .day, value: -offset, to: yesterday) ?? yesterday
            let words = byDay[StatsCalendar.dayKey(for: date, calendar: calendar)]?.words ?? 0
            if offset < 7 {
                last7Words += words
            } else {
                prior7Words += words
            }
        }

        let contributing = events.filter {
            StatsPolicy.contribution(of: $0.run, baselineWPM: baselineWPM).countsAsDictation
        }
        let activeDays = allDailies.filter { $0.dictations > 0 }.count
        let totalDictations = allDailies.reduce(0) { $0 + $1.dictations }
        let breakdown = usageBreakdown(
            contributing: contributing,
            baselineWPM: baselineWPM,
            categoryOverrides: categoryOverrides
        )

        return StatsSnapshot(
            baselineWPM: baselineWPM,
            totalWords: allDailies.reduce(0) { $0 + $1.words },
            totalDictations: totalDictations,
            totalAttempts: events.count,
            totalSpeakingSec: allDailies.reduce(0) { $0 + $1.speakingSec },
            totalTimeSavedSec: allDailies.reduce(0) { $0 + $1.timeSavedSec },
            overallAvgWPM: wpmSec > 0 ? Double(wpmWords) / wpmSec * 60 : nil,
            currentStreakDays: currentStreak,
            longestStreakDays: longestStreak,
            bestDay: bestDay,
            today: byDay[todayKey] ?? DailyStat(
                dayKey: todayKey,
                date: startOfToday,
                words: 0,
                dictations: 0,
                attempts: 0,
                speakingSec: 0,
                timeSavedSec: 0,
                avgWPM: nil
            ),
            last14: last14,
            heatmapDays: heatmapDays,
            streakDayKeys: streakDayKeys,
            avgDictationsPerDay: activeDays > 0 ? Double(totalDictations) / Double(activeDays) : 0,
            weekOverWeekPct: prior7Words > 0
                ? Double(last7Words - prior7Words) / Double(prior7Words) * 100
                : nil,
            mostActiveHour: mostFrequent(contributing.map(\.day.hour)),
            mostActiveWeekday: mostFrequent(contributing.map(\.day.weekday)),
            categoryBreakdown: breakdown.categories,
            appBreakdown: breakdown.apps,
            allAppBreakdown: breakdown.allApps,
            attributedDictations: breakdown.attributedDictations,
            unattributedDictations: breakdown.unattributedDictations,
            totalAppsUsed: breakdown.totalAppsUsed
        )
    }

    /// All-time usage breakdowns over contributing runs. Only runs carrying
    /// app identity (bundle ID and/or app name) feed the breakdowns; shares
    /// are computed over those attributed runs so pre-tracking history never
    /// dilutes percentages. Pre-tracking runs surface as
    /// `unattributedDictations` for the footnote.
    private static func usageBreakdown(
        contributing: [DictationStatEvent],
        baselineWPM: Int,
        categoryOverrides: [String: UsageCategory]
    ) -> (
        categories: [UsageBreakdownEntry],
        apps: [UsageBreakdownEntry],
        allApps: [UsageBreakdownEntry],
        attributedDictations: Int,
        unattributedDictations: Int,
        totalAppsUsed: Int
    ) {
        struct Accumulator {
            var dictations = 0
            var words = 0
            var displayName: String
            var bundleID: String?
        }

        var attributedDictations = 0
        var attributedWords = 0
        var unattributedDictations = 0
        var categoryAcc: [UsageCategory: Accumulator] = [:]
        var appAcc: [String: Accumulator] = [:]
        var bundleIDs = Set<String>()

        for event in contributing {
            let words = StatsPolicy.contribution(of: event.run, baselineWPM: baselineWPM).words
            guard event.bundleID != nil || event.appName != nil else {
                unattributedDictations += 1
                continue
            }
            attributedDictations += 1
            attributedWords += words

            let category = UsageCategoryMapper.category(
                forBundleID: event.bundleID,
                overrides: categoryOverrides
            )
            var catEntry = categoryAcc[category] ?? Accumulator(
                displayName: category.title,
                bundleID: nil
            )
            catEntry.dictations += 1
            catEntry.words += words
            categoryAcc[category] = catEntry

            if let bundleID = event.bundleID {
                bundleIDs.insert(bundleID)
            }
            let appKey = event.bundleID ?? "name:\(event.appName ?? "Unknown")"
            let trimmedName = event.appName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName: String
            if let trimmedName, !trimmedName.isEmpty {
                displayName = trimmedName
            } else {
                displayName = event.bundleID ?? "Unknown"
            }
            var appEntry = appAcc[appKey] ?? Accumulator(
                displayName: displayName,
                bundleID: event.bundleID
            )
            appEntry.dictations += 1
            appEntry.words += words
            // Prefer the most recently seen non-empty app name.
            if let trimmedName, !trimmedName.isEmpty {
                appEntry.displayName = trimmedName
            }
            appAcc[appKey] = appEntry
        }

        func shareOfDictations(_ dictations: Int) -> Double {
            attributedDictations > 0 ? Double(dictations) / Double(attributedDictations) : 0
        }

        func shareOfWords(_ words: Int) -> Double {
            attributedWords > 0 ? Double(words) / Double(attributedWords) : 0
        }

        let categories = categoryAcc
            .map { (category, acc) in
                UsageBreakdownEntry(
                    key: category.rawValue,
                    displayName: acc.displayName,
                    icon: category.iconSystemName,
                    dictations: acc.dictations,
                    words: acc.words,
                    shareOfDictations: shareOfDictations(acc.dictations),
                    shareOfWords: shareOfWords(acc.words)
                )
            }
            .sorted {
                if $0.dictations != $1.dictations {
                    return $0.dictations > $1.dictations
                }
                let lhsOrder = UsageCategory(rawValue: $0.key)?.sortOrder ?? Int.max
                let rhsOrder = UsageCategory(rawValue: $1.key)?.sortOrder ?? Int.max
                return lhsOrder < rhsOrder
            }

        let sortedApps = appAcc
            .map { (key, acc) in
                UsageBreakdownEntry(
                    key: key,
                    displayName: acc.displayName,
                    icon: UsageCategoryMapper.category(
                        forBundleID: acc.bundleID,
                        overrides: categoryOverrides
                    ).iconSystemName,
                    dictations: acc.dictations,
                    words: acc.words,
                    shareOfDictations: shareOfDictations(acc.dictations),
                    shareOfWords: shareOfWords(acc.words),
                    bundleID: acc.bundleID
                )
            }
            .sorted {
                if $0.dictations != $1.dictations {
                    return $0.dictations > $1.dictations
                }
                if $0.words != $1.words {
                    return $0.words > $1.words
                }
                return $0.displayName < $1.displayName
            }
        let apps: [UsageBreakdownEntry]
        if sortedApps.count > UsageCategoryMapper.maxAppRows {
            let head = Array(sortedApps.prefix(UsageCategoryMapper.maxAppRows))
            let tail = sortedApps.dropFirst(UsageCategoryMapper.maxAppRows)
            let otherDictations = tail.reduce(0) { $0 + $1.dictations }
            let otherWords = tail.reduce(0) { $0 + $1.words }
            apps = head + [UsageBreakdownEntry(
                key: "other",
                displayName: "Other",
                icon: UsageCategory.otherTasks.iconSystemName,
                dictations: otherDictations,
                words: otherWords,
                shareOfDictations: shareOfDictations(otherDictations),
                shareOfWords: shareOfWords(otherWords)
            )]
        } else {
            apps = sortedApps
        }

        return (
            categories,
            apps,
            sortedApps,
            attributedDictations,
            unattributedDictations,
            bundleIDs.count
        )
    }

    /// One-line per-run summary for Run Log entries. Nil for runs that
    /// produced no output, which already surface through the run status.
    static func summaryLine(for event: DictationStatEvent, baselineWPM: Int) -> String? {
        let contribution = StatsPolicy.contribution(of: event.run, baselineWPM: baselineWPM)
        guard contribution.countsAsDictation, contribution.words > 0 else { return nil }
        guard let duration = event.run.audioDurationSec, duration > 0 else {
            return "\(contribution.words)w · —"
        }
        var parts = ["\(contribution.words)w", formatClock(duration)]
        switch event.run.kind {
        case .dictation:
            guard let sample = contribution.speedSample else {
                parts.append("too short for WPM")
                return parts.joined(separator: " · ")
            }
            parts.append(formatWPM(StatsPolicy.wpm(wordCount: sample.words, durationSec: sample.seconds)))
            if let saved = StatsPolicy.timeSavedSec(
                wordCount: contribution.words,
                durationSec: duration,
                baselineWPM: baselineWPM
            ) {
                parts.append(formatSavedShort(saved))
            }
        case .edit, .macro:
            break
        }
        return parts.joined(separator: " · ")
    }

    static func formatClock(_ totalSec: Double) -> String {
        let total = max(0, Int(totalSec.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return "\(hours):\(twoDigits(minutes)):\(twoDigits(seconds))"
        }
        return "\(minutes):\(twoDigits(seconds))"
    }

    static func formatSavedShort(_ totalSec: Double) -> String {
        let total = max(0, Int(totalSec.rounded()))
        if total < 60 {
            return "+\(total)s"
        }
        if total < 3600 {
            let minutes = total / 60
            let seconds = total % 60
            return seconds == 0 ? "+\(minutes)m" : "+\(minutes)m \(seconds)s"
        }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return minutes == 0 ? "+\(hours)h" : "+\(hours)h \(minutes)m"
    }

    static func formatTotalTime(_ totalSec: Double) -> String {
        if totalSec < 60 {
            return "\(Int(totalSec.rounded()))s"
        }
        if totalSec < 3600 {
            return "\(Int((totalSec / 60).rounded()))m"
        }
        return "\(format1(totalSec / 3600)) hrs"
    }

    static func formatWPM(_ wpm: Double?) -> String {
        guard let wpm else { return "—" }
        return "\(Int(wpm.rounded())) WPM"
    }

    static func format1(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        var text = String(rounded)
        if !text.contains(".") {
            text += ".0"
        }
        return text
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }

    private static func longestStreak(qualifyingDayKeys: Set<String>, calendar: Calendar) -> Int {
        let dates = qualifyingDayKeys.compactMap { StatsCalendar.date(fromDayKey: $0, calendar: calendar) }.sorted()
        var longest = 0
        var run = 0
        var previous: Date?
        for date in dates {
            if let prior = previous,
                let next = calendar.date(byAdding: .day, value: 1, to: prior),
                calendar.isDate(next, inSameDayAs: date)
            {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = date
        }
        return longest
    }

    private static func mostFrequent(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        var counts: [Int: Int] = [:]
        for value in values {
            counts[value, default: 0] += 1
        }
        return counts.sorted {
            if $0.value != $1.value {
                return $0.value > $1.value
            }
            return $0.key < $1.key
        }.first?.key
    }
}
