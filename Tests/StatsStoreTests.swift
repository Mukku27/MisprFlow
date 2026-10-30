import Foundation

enum StatsStoreTests {
    static func run() {
        testRecordAndLoadAllOrdering()
        testCount()
        testUpdatePreservesIdentityAndDay()
        testUpdateIsUpdateOnly()
        testEventsForHistoryIDs()
        testClearAll()
        testPersistenceState()
    }

    private static func event(
        timestamp: Date,
        historyID: UUID? = nil,
        kind: StatsRunKind = .dictation,
        producedOutput: Bool = true,
        spokenWords: Int = 10,
        outputWords: Int = 10,
        durationSec: Double? = 60
    ) -> DictationStatEvent {
        DictationStatEvent(
            historyID: historyID,
            timestamp: timestamp,
            day: StatsDay(date: timestamp, calendar: StatsTestSupport.gmtCalendar()),
            run: StatsRunRecord(
                kind: kind,
                producedOutput: producedOutput,
                spokenWordCount: spokenWords,
                outputWordCount: outputWords,
                audioDurationSec: durationSec
            )
        )
    }

    private static func record(_ store: StatsStore, _ event: DictationStatEvent) {
        do {
            try store.record(event)
        } catch {
            TestSupport.expect(false, "Record should succeed: \(error.localizedDescription)")
        }
    }

    private static func testRecordAndLoadAllOrdering() {
        let store = StatsStore(configuration: .inMemory)
        let older = event(timestamp: StatsTestSupport.date(2026, 9, 10, 9))
        let newer = event(
            timestamp: StatsTestSupport.date(2026, 9, 11, 14),
            kind: .edit,
            spokenWords: 12,
            outputWords: 300,
            durationSec: 3
        )
        record(store, older)
        record(store, newer)

        let loaded = store.loadAll()
        TestSupport.expectEqual(loaded.count, 2)
        TestSupport.expectEqual(loaded[0].id, newer.id)
        TestSupport.expectEqual(loaded[1].id, older.id)
        TestSupport.expectEqual(loaded[0].day.key, "2026-09-11")
        TestSupport.expectEqual(loaded[0].day.hour, 14)
        TestSupport.expectEqual(loaded[0].run.kind, .edit)
        TestSupport.expectEqual(loaded[0].run.spokenWordCount, 12)
        TestSupport.expectEqual(loaded[0].run.outputWordCount, 300)
        TestSupport.expectEqual(loaded[0].run.audioDurationSec, 3)
    }

    private static func testCount() {
        let store = StatsStore(configuration: .inMemory)
        TestSupport.expectEqual(store.count(), 0)
        record(store, event(timestamp: StatsTestSupport.date(2026, 9, 11, 9)))
        record(store, event(timestamp: StatsTestSupport.date(2026, 9, 11, 10)))
        TestSupport.expectEqual(store.count(), 2)
    }

    private static func testUpdatePreservesIdentityAndDay() {
        let store = StatsStore(configuration: .inMemory)
        let historyID = UUID()
        let original = event(timestamp: StatsTestSupport.date(2026, 9, 10, 9), historyID: historyID)
        record(store, original)

        let retryRun = StatsRunRecord(
            kind: .dictation,
            producedOutput: true,
            spokenWordCount: 42,
            outputWordCount: 40,
            audioDurationSec: 30
        )
        let updated: DictationStatEvent?
        do {
            updated = try store.update(forHistoryID: historyID, run: retryRun)
        } catch {
            TestSupport.expect(false, "Update should succeed: \(error.localizedDescription)")
            return
        }
        guard let updated else {
            TestSupport.expect(false, "Update should return the updated event")
            return
        }
        TestSupport.expectEqual(updated.id, original.id)
        TestSupport.expectEqual(updated.timestamp, original.timestamp)
        TestSupport.expectEqual(updated.day, original.day)
        TestSupport.expectEqual(updated.run.spokenWordCount, 42)
        TestSupport.expectEqual(updated.run.outputWordCount, 40)
        TestSupport.expectEqual(store.count(), 1)
    }

    private static func testUpdateIsUpdateOnly() {
        // Retries must never resurrect cleared stats: no row, no insert.
        let store = StatsStore(configuration: .inMemory)
        let updated: DictationStatEvent?
        do {
            updated = try store.update(
                forHistoryID: UUID(),
                run: StatsRunRecord(kind: .dictation, producedOutput: true, spokenWordCount: 5, outputWordCount: 5)
            )
        } catch {
            TestSupport.expect(false, "Update should succeed: \(error.localizedDescription)")
            return
        }
        TestSupport.expectEqual(updated, nil)
        TestSupport.expectEqual(store.count(), 0)
    }

    private static func testEventsForHistoryIDs() {
        let store = StatsStore(configuration: .inMemory)
        let firstID = UUID()
        let secondID = UUID()
        record(store, event(timestamp: StatsTestSupport.date(2026, 9, 11, 9), historyID: firstID))
        record(store, event(timestamp: StatsTestSupport.date(2026, 9, 11, 10), historyID: secondID))
        record(store, event(timestamp: StatsTestSupport.date(2026, 9, 11, 11)))

        let indexed = store.events(forHistoryIDs: [firstID, secondID, UUID()])
        TestSupport.expectEqual(indexed.count, 2)
        TestSupport.expectEqual(indexed[firstID]?.run.spokenWordCount, 10)
        TestSupport.expectEqual(indexed[secondID]?.run.spokenWordCount, 10)
        TestSupport.expectEqual(store.events(forHistoryIDs: []).count, 0)
    }

    private static func testClearAll() {
        let store = StatsStore(configuration: .inMemory)
        record(store, event(timestamp: StatsTestSupport.date(2026, 9, 11, 9)))
        record(store, event(timestamp: StatsTestSupport.date(2026, 9, 11, 10)))
        do {
            try store.clearAll()
        } catch {
            TestSupport.expect(false, "Clear should succeed: \(error.localizedDescription)")
        }
        TestSupport.expectEqual(store.count(), 0)
        TestSupport.expectEqual(store.loadAll().count, 0)
    }

    private static func testPersistenceState() {
        let memory = StatsStore(configuration: .inMemory)
        TestSupport.expect(!memory.isPersistent, "In-memory store should not report persistent")
        TestSupport.expectEqual(memory.quarantinedFileName, nil)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MisprFlowTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileBacked = StatsStore(configuration: CoreDataStoreBootstrap.Configuration(
            storeFileName: "DictationStats.sqlite",
            policy: .quarantine,
            storeDirectoryURL: directory
        ))
        TestSupport.expect(fileBacked.isPersistent, "File-backed store should report persistent")
    }
}
