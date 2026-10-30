import Foundation

enum StatsPolicyTests {
    static func run() {
        testWordCount()
        testWPM()
        testTimeSaved()
        testShortRunFlag()
        testDictationContribution()
        testDictationSpeedUsesSpokenWords()
        testFailedRunContributesNothing()
        testEmptyOutputContributesNothing()
        testEditRunCountsSpokenWordsOnly()
        testFailedEditRunContributesNothing()
        testMacroRunCountsSpokenWordsOnly()
    }

    private static func testWordCount() {
        TestSupport.expectEqual(StatsPolicy.wordCount(""), 0)
        TestSupport.expectEqual(StatsPolicy.wordCount("   \n\t  "), 0)
        TestSupport.expectEqual(StatsPolicy.wordCount("hello"), 1)
        TestSupport.expectEqual(StatsPolicy.wordCount("hello world"), 2)
        TestSupport.expectEqual(StatsPolicy.wordCount("  padded   words\nacross\tlines  "), 4)
    }

    private static func testWPM() {
        TestSupport.expectEqual(StatsPolicy.wpm(wordCount: 120, durationSec: 60), 120)
        TestSupport.expectEqual(StatsPolicy.wpm(wordCount: 0, durationSec: 60), nil)
        TestSupport.expectEqual(StatsPolicy.wpm(wordCount: 120, durationSec: nil), nil)
        TestSupport.expectEqual(StatsPolicy.wpm(wordCount: 120, durationSec: 0), nil)
        TestSupport.expectApproximatelyEqual(
            StatsPolicy.wpm(wordCount: 90, durationSec: 45) ?? 0,
            120
        )
        // Sub-second audio clamps to one second so WPM stays finite.
        TestSupport.expectApproximatelyEqual(
            StatsPolicy.wpm(wordCount: 10, durationSec: 0.2) ?? 0,
            600
        )
    }

    private static func testTimeSaved() {
        // 120 words at 40 WPM takes 180s to type; 60s spoken saves 120s.
        TestSupport.expectApproximatelyEqual(
            StatsPolicy.timeSavedSec(wordCount: 120, durationSec: 60, baselineWPM: 40) ?? -1,
            120
        )
        // Slower than typing never reports negative savings.
        TestSupport.expectEqual(
            StatsPolicy.timeSavedSec(wordCount: 5, durationSec: 120, baselineWPM: 40),
            0
        )
        TestSupport.expectEqual(
            StatsPolicy.timeSavedSec(wordCount: 120, durationSec: nil, baselineWPM: 40),
            nil
        )
        TestSupport.expectEqual(
            StatsPolicy.timeSavedSec(wordCount: 120, durationSec: 60, baselineWPM: 0),
            nil
        )
        // Faster typists save less from the same dictation.
        let slowBaseline = StatsPolicy.timeSavedSec(wordCount: 120, durationSec: 60, baselineWPM: 30) ?? 0
        let fastBaseline = StatsPolicy.timeSavedSec(wordCount: 120, durationSec: 60, baselineWPM: 80) ?? 0
        TestSupport.expect(slowBaseline > fastBaseline, "30 WPM baseline should save more than 80 WPM")
    }

    private static func testShortRunFlag() {
        TestSupport.expectEqual(StatsPolicy.isShortRun(wordCount: 2, durationSec: 60), true)
        TestSupport.expectEqual(StatsPolicy.isShortRun(wordCount: 50, durationSec: 1.5), true)
        TestSupport.expectEqual(StatsPolicy.isShortRun(wordCount: 50, durationSec: 60), false)
        TestSupport.expectEqual(StatsPolicy.isShortRun(wordCount: 50, durationSec: nil), false)
    }

    private static func testDictationContribution() {
        let run = StatsRunRecord(
            kind: .dictation,
            producedOutput: true,
            spokenWordCount: 142,
            outputWordCount: 142,
            audioDurationSec: 48
        )
        let contribution = StatsPolicy.contribution(of: run, baselineWPM: 40)
        TestSupport.expectEqual(contribution.countsAsDictation, true)
        TestSupport.expectEqual(contribution.words, 142)
        TestSupport.expectEqual(contribution.speedSample, StatsPolicy.SpeedSample(words: 142, seconds: 48))
        TestSupport.expectApproximatelyEqual(contribution.timeSavedSec, 165)

        // Unknown durations still count toward words and streaks, never speed.
        let unknown = StatsRunRecord(
            kind: .dictation,
            producedOutput: true,
            spokenWordCount: 80,
            outputWordCount: 80,
            audioDurationSec: nil
        )
        let unknownContribution = StatsPolicy.contribution(of: unknown, baselineWPM: 40)
        TestSupport.expectEqual(unknownContribution.countsAsDictation, true)
        TestSupport.expectEqual(unknownContribution.words, 80)
        TestSupport.expectEqual(unknownContribution.speedSample, nil)
        TestSupport.expectApproximatelyEqual(unknownContribution.timeSavedSec, 0)

        // Short runs accrue time saved but no speed sample.
        let short = StatsRunRecord(
            kind: .dictation,
            producedOutput: true,
            spokenWordCount: 2,
            outputWordCount: 2,
            audioDurationSec: 1
        )
        let shortContribution = StatsPolicy.contribution(of: short, baselineWPM: 40)
        TestSupport.expectEqual(shortContribution.countsAsDictation, true)
        TestSupport.expectEqual(shortContribution.speedSample, nil)
        TestSupport.expectApproximatelyEqual(shortContribution.timeSavedSec, 2)
    }

    private static func testDictationSpeedUsesSpokenWords() {
        // 100 spoken words in 60s, compressed to 80 pasted: WPM is speaking
        // rate. Word totals and time saved still use what was pasted.
        let compressed = StatsRunRecord(
            kind: .dictation,
            producedOutput: true,
            spokenWordCount: 100,
            outputWordCount: 80,
            audioDurationSec: 60
        )
        let contribution = StatsPolicy.contribution(of: compressed, baselineWPM: 40)
        TestSupport.expectEqual(contribution.countsAsDictation, true)
        TestSupport.expectEqual(contribution.words, 80)
        TestSupport.expectEqual(contribution.speedSample, StatsPolicy.SpeedSample(words: 100, seconds: 60))
        TestSupport.expectApproximatelyEqual(contribution.timeSavedSec, 60)

        // Enhancement shrinking below 3 pasted words must not drop a long
        // utterance from the WPM average.
        let heavilyCompressed = StatsRunRecord(
            kind: .dictation,
            producedOutput: true,
            spokenWordCount: 100,
            outputWordCount: 2,
            audioDurationSec: 60
        )
        let heavy = StatsPolicy.contribution(of: heavilyCompressed, baselineWPM: 40)
        TestSupport.expectEqual(heavy.words, 2)
        TestSupport.expectEqual(heavy.speedSample, StatsPolicy.SpeedSample(words: 100, seconds: 60))

        // Two spoken words in a minute stay too short for WPM even if
        // enhancement expands the paste.
        let expanded = StatsRunRecord(
            kind: .dictation,
            producedOutput: true,
            spokenWordCount: 2,
            outputWordCount: 80,
            audioDurationSec: 60
        )
        let expandedContribution = StatsPolicy.contribution(of: expanded, baselineWPM: 40)
        TestSupport.expectEqual(expandedContribution.words, 80)
        TestSupport.expectEqual(expandedContribution.speedSample, nil)
    }

    private static func testFailedRunContributesNothing() {
        let run = StatsRunRecord(
            kind: .dictation,
            producedOutput: false,
            spokenWordCount: 0,
            outputWordCount: 0,
            audioDurationSec: 60
        )
        TestSupport.expectEqual(
            StatsPolicy.contribution(of: run, baselineWPM: 40),
            StatsPolicy.Contribution(countsAsDictation: false, words: 0, speedSample: nil, timeSavedSec: 0)
        )
    }

    private static func testEmptyOutputContributesNothing() {
        // A dictation that pasted nothing is an attempt, not a dictation.
        let run = StatsRunRecord(
            kind: .dictation,
            producedOutput: true,
            spokenWordCount: 0,
            outputWordCount: 0,
            audioDurationSec: 60
        )
        let contribution = StatsPolicy.contribution(of: run, baselineWPM: 40)
        TestSupport.expectEqual(contribution.countsAsDictation, false)
        TestSupport.expectEqual(contribution.words, 0)
    }

    private static func testEditRunCountsSpokenWordsOnly() {
        // A 300-word selection rewritten from a 12-word voice command in 3s
        // of audio counts 12 spoken words. It must not produce a 6,000 WPM
        // speed sample or phantom time saved.
        let run = StatsRunRecord(
            kind: .edit,
            producedOutput: true,
            spokenWordCount: 12,
            outputWordCount: 300,
            audioDurationSec: 3
        )
        let contribution = StatsPolicy.contribution(of: run, baselineWPM: 40)
        TestSupport.expectEqual(contribution.countsAsDictation, true)
        TestSupport.expectEqual(contribution.words, 12)
        TestSupport.expectEqual(contribution.speedSample, nil)
        TestSupport.expectApproximatelyEqual(contribution.timeSavedSec, 0)
    }

    private static func testFailedEditRunContributesNothing() {
        // A failed edit falls back to the untouched selection: an attempt
        // only, even though output text exists.
        let run = StatsRunRecord(
            kind: .edit,
            producedOutput: false,
            spokenWordCount: 0,
            outputWordCount: 0,
            audioDurationSec: 3
        )
        let contribution = StatsPolicy.contribution(of: run, baselineWPM: 40)
        TestSupport.expectEqual(contribution.countsAsDictation, false)
        TestSupport.expectEqual(contribution.words, 0)
        TestSupport.expectEqual(contribution.speedSample, nil)
    }

    private static func testMacroRunCountsSpokenWordsOnly() {
        // A 2-word command expanding to a 60-word signature counts 2 words.
        let run = StatsRunRecord(
            kind: .macro,
            producedOutput: true,
            spokenWordCount: 2,
            outputWordCount: 60,
            audioDurationSec: 1.5
        )
        let contribution = StatsPolicy.contribution(of: run, baselineWPM: 40)
        TestSupport.expectEqual(contribution.countsAsDictation, true)
        TestSupport.expectEqual(contribution.words, 2)
        TestSupport.expectEqual(contribution.speedSample, nil)
        TestSupport.expectApproximatelyEqual(contribution.timeSavedSec, 0)
    }
}
