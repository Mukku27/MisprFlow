import Foundation

/// The one place that decides what a run contributes to stats.
///
/// Policy table:
///
/// - Dictation runs contribute pasted words and time saved. Speed samples use
///   spoken words so WPM is speaking rate, not post-enhancement length.
/// - Edit and voice-macro runs contribute spoken words toward dictations and
///   streaks only; their output length says nothing about speech, so they are
///   excluded from speed and time saved.
/// - Runs that produced no output contribute attempts only.
enum StatsPolicy {
    static let minDurationSecForWPM = 1.0
    static let shortRunMaxDurationSec = 2.0
    static let shortRunMinWords = 3

    struct SpeedSample: Equatable {
        let words: Int
        let seconds: Double
    }

    struct Contribution: Equatable {
        let countsAsDictation: Bool
        let words: Int
        /// Set when this run measures free-form dictation speed.
        let speedSample: SpeedSample?
        let timeSavedSec: Double
    }

    static func contribution(of run: StatsRunRecord, baselineWPM: Int) -> Contribution {
        guard run.producedOutput else {
            return Contribution(countsAsDictation: false, words: 0, speedSample: nil, timeSavedSec: 0)
        }
        switch run.kind {
        case .dictation:
            let words = run.outputWordCount
            guard words > 0 else {
                return Contribution(countsAsDictation: false, words: 0, speedSample: nil, timeSavedSec: 0)
            }
            var speedSample: SpeedSample?
            var timeSavedSec = 0.0
            if let duration = run.audioDurationSec, duration > 0 {
                timeSavedSec = Self.timeSavedSec(wordCount: words, durationSec: duration, baselineWPM: baselineWPM) ?? 0
                let spokenWords = run.spokenWordCount
                if !isShortRun(wordCount: spokenWords, durationSec: duration) {
                    speedSample = SpeedSample(words: spokenWords, seconds: duration)
                }
            }
            return Contribution(countsAsDictation: true, words: words, speedSample: speedSample, timeSavedSec: timeSavedSec)
        case .edit, .macro:
            let words = run.spokenWordCount
            guard words > 0 else {
                return Contribution(countsAsDictation: false, words: 0, speedSample: nil, timeSavedSec: 0)
            }
            return Contribution(countsAsDictation: true, words: words, speedSample: nil, timeSavedSec: 0)
        }
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    /// Speaking speed. Nil when duration is unknown or there are no words.
    /// Very short audio is clamped to one second so WPM stays finite; such
    /// runs are still excluded from averages via ``isShortRun``.
    static func wpm(wordCount: Int, durationSec: Double?) -> Double? {
        guard wordCount > 0, let durationSec, durationSec > 0 else { return nil }
        return Double(wordCount) / max(durationSec, minDurationSecForWPM) * 60
    }

    /// Seconds saved versus typing at `baselineWPM`. Never negative.
    /// Nil when duration is unknown or the baseline is invalid.
    static func timeSavedSec(wordCount: Int, durationSec: Double?, baselineWPM: Int) -> Double? {
        guard baselineWPM > 0, let durationSec, durationSec >= 0 else { return nil }
        guard wordCount > 0 else { return 0 }
        return max(0, Double(wordCount) / Double(baselineWPM) * 60 - durationSec)
    }

    /// Short runs count toward words, dictations, and streaks, but are
    /// excluded from WPM averages so greetings don't skew speed.
    static func isShortRun(wordCount: Int, durationSec: Double?) -> Bool {
        if wordCount < shortRunMinWords { return true }
        if let durationSec, durationSec < shortRunMaxDurationSec { return true }
        return false
    }
}
