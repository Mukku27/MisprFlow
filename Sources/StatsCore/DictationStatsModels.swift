import Foundation

/// What kind of pipeline run produced a stats row.
enum StatsRunKind: String, Equatable, Sendable {
    case dictation
    case edit
    case macro
}

/// The typed facts of one pipeline run. Rows persist facts; what "counts"
/// toward words, speed, and time saved is decided at read time by
/// ``StatsPolicy``, so semantics can change without a store migration.
struct StatsRunRecord: Equatable, Sendable {
    let kind: StatsRunKind
    /// False when transcription failed, the run produced no output, or an
    /// edit run fell back to the untouched selection.
    let producedOutput: Bool
    /// Words actually spoken, from the raw transcript.
    let spokenWordCount: Int
    /// Words pasted, from the post-processed transcript.
    let outputWordCount: Int
    let audioDurationSec: Double?

    init(
        kind: StatsRunKind = .dictation,
        producedOutput: Bool,
        spokenWordCount: Int,
        outputWordCount: Int,
        audioDurationSec: Double? = nil
    ) {
        self.kind = kind
        self.producedOutput = producedOutput
        self.spokenWordCount = spokenWordCount
        self.outputWordCount = outputWordCount
        self.audioDurationSec = audioDurationSec
    }
}

/// One stats row per pipeline run. Numbers plus the originating app's
/// identity (bundle ID + app name) only: never transcript text,
/// screenshots, selections, or window titles.
struct DictationStatEvent: Equatable, Identifiable, Sendable {
    let id: UUID
    let historyID: UUID?
    let timestamp: Date
    /// Day facts frozen at record time; never recomputed.
    let day: StatsDay
    /// Mutable so retry updates can replace the run facts in place.
    var run: StatsRunRecord
    /// Nil for rows recorded before app tracking shipped.
    let bundleID: String?
    /// Nil for rows recorded before app tracking shipped.
    let appName: String?

    init(
        id: UUID = UUID(),
        historyID: UUID? = nil,
        timestamp: Date,
        day: StatsDay,
        run: StatsRunRecord,
        bundleID: String? = nil,
        appName: String? = nil
    ) {
        self.id = id
        self.historyID = historyID
        self.timestamp = timestamp
        self.day = day
        self.run = run
        self.bundleID = bundleID
        self.appName = appName
    }
}

/// Aggregates for a single local calendar day.
struct DailyStat: Equatable, Identifiable, Sendable {
    var id: String { dayKey }
    let dayKey: String
    let date: Date
    let words: Int
    let dictations: Int
    let attempts: Int
    let speakingSec: Double
    let timeSavedSec: Double
    let avgWPM: Double?

    init(
        dayKey: String,
        date: Date,
        words: Int,
        dictations: Int,
        attempts: Int,
        speakingSec: Double,
        timeSavedSec: Double,
        avgWPM: Double?
    ) {
        self.dayKey = dayKey
        self.date = date
        self.words = words
        self.dictations = dictations
        self.attempts = attempts
        self.speakingSec = speakingSec
        self.timeSavedSec = timeSavedSec
        self.avgWPM = avgWPM
    }
}

/// One row of a usage breakdown (per category or per app), all-time.
/// Shares are computed over attributed runs only; pre-tracking runs are
/// counted separately on the snapshot and never folded into these rows.
struct UsageBreakdownEntry: Equatable, Sendable {
    /// Category raw value for category rows, bundle ID (or a
    /// `name:<appName>` fallback key) for app rows, `"other"` for the
    /// per-app rollup of apps outside the top list.
    let key: String
    let displayName: String
    /// SF Symbol name for the leading icon.
    let icon: String
    let dictations: Int
    let words: Int
    /// 0…1 share of attributed dictations.
    let shareOfDictations: Double
    /// 0…1 share of attributed words.
    let shareOfWords: Double
    /// Set for per-app rows backed by a real bundle ID so the UI can offer
    /// a per-app category override. Nil for category rows, name-keyed app
    /// rows, and the "Other" rollup.
    let bundleID: String?

    init(
        key: String,
        displayName: String,
        icon: String,
        dictations: Int,
        words: Int,
        shareOfDictations: Double,
        shareOfWords: Double,
        bundleID: String? = nil
    ) {
        self.key = key
        self.displayName = displayName
        self.icon = icon
        self.dictations = dictations
        self.words = words
        self.shareOfDictations = shareOfDictations
        self.shareOfWords = shareOfWords
        self.bundleID = bundleID
    }
}

/// Fully derived headline + trend snapshot. Recomputed in memory from
/// stored events whenever events or the typing baseline change.
struct StatsSnapshot: Equatable, Sendable {
    let baselineWPM: Int
    let totalWords: Int
    let totalDictations: Int
    let totalAttempts: Int
    let totalSpeakingSec: Double
    let totalTimeSavedSec: Double
    let overallAvgWPM: Double?
    let currentStreakDays: Int
    let longestStreakDays: Int
    let bestDay: DailyStat?
    let today: DailyStat
    let last14: [DailyStat]
    let heatmapDays: [DailyStat]
    let streakDayKeys: Set<String>
    let avgDictationsPerDay: Double
    let weekOverWeekPct: Double?
    let mostActiveHour: Int?
    let mostActiveWeekday: Int?
    /// All-time per-category aggregates over attributed contributing runs,
    /// sorted by dictations descending.
    let categoryBreakdown: [UsageBreakdownEntry]
    /// All-time per-app aggregates over attributed contributing runs: top 6
    /// by dictations plus an "Other" rollup when more apps exist.
    let appBreakdown: [UsageBreakdownEntry]
    /// Same per-app aggregates without the top-6 cap, backing the category
    /// manager so apps rolled into "Other" stay remappable.
    let allAppBreakdown: [UsageBreakdownEntry]
    /// Contributing runs carrying app identity (bundle ID and/or app name).
    let attributedDictations: Int
    /// Contributing runs recorded before app tracking shipped.
    let unattributedDictations: Int
    /// Distinct bundle IDs across contributing runs.
    let totalAppsUsed: Int
}
