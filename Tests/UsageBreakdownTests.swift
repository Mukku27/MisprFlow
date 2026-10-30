import CoreData
import Foundation

/// Regression tests for the usage breakdown graphs. All bundle IDs are
/// either well-known public app identifiers used as mapping fixtures or
/// invented `com.example.*` values; no test uses real user metadata.
enum UsageBreakdownTests {
    static func run() {
        testDefaultMapHits()
        testUnknownBundlesFallThroughToOther()
        testOverridesWinOverDefaultMap()
        testStoredOverridesRoundTrip()
        testBreakdownAggregationAndShares()
        testFailedRunsNeverEnterBreakdowns()
        testAppBreakdownCapsAtTop6PlusOther()
        testStoreRoundTripPreservesAppIdentity()
        testRetryUpdatePreservesAppAttribution()
        testFillAppAttribution()
        testV1StoreMigratesWithNilAppFields()
    }

    // MARK: - Mapper

    private static func testDefaultMapHits() {
        TestSupport.expectEqual(
            UsageCategoryMapper.category(forBundleID: "com.openai.chat", overrides: [:]),
            .aiTools
        )
        TestSupport.expectEqual(
            UsageCategoryMapper.category(forBundleID: "com.microsoft.VSCode", overrides: [:]),
            .aiTools
        )
        TestSupport.expectEqual(
            UsageCategoryMapper.category(forBundleID: "com.apple.iChat", overrides: [:]),
            .personalMessages
        )
        TestSupport.expectEqual(
            UsageCategoryMapper.category(forBundleID: "com.tinyspeck.slackmacgap", overrides: [:]),
            .workMessages
        )
        TestSupport.expectEqual(
            UsageCategoryMapper.category(forBundleID: "com.apple.mail", overrides: [:]),
            .emails
        )
        TestSupport.expectEqual(
            UsageCategoryMapper.category(forBundleID: "md.obsidian", overrides: [:]),
            .documents
        )
        TestSupport.expectEqual(
            UsageCategoryMapper.category(forBundleID: "com.stablyai.orca", overrides: [:]),
            .aiTools
        )
    }

    private static func testUnknownBundlesFallThroughToOther() {
        TestSupport.expectEqual(
            UsageCategoryMapper.category(forBundleID: "com.example.mystery-app", overrides: [:]),
            .otherTasks
        )
        TestSupport.expectEqual(
            UsageCategoryMapper.category(forBundleID: nil, overrides: [:]),
            .otherTasks
        )
        TestSupport.expectEqual(
            UsageCategoryMapper.category(forBundleID: "", overrides: [:]),
            .otherTasks
        )
        // Browsers are deliberately unmapped: no window-title sniffing.
        TestSupport.expectEqual(
            UsageCategoryMapper.category(forBundleID: "com.apple.Safari", overrides: [:]),
            .otherTasks
        )
    }

    private static func testOverridesWinOverDefaultMap() {
        let custom: [String: UsageCategory] = ["com.example.custom-app": .emails]
        TestSupport.expectEqual(
            UsageCategoryMapper.category(forBundleID: "com.example.custom-app", overrides: custom),
            .emails
        )
        let beatsDefault: [String: UsageCategory] = ["com.apple.mail": .documents]
        TestSupport.expectEqual(
            UsageCategoryMapper.category(forBundleID: "com.apple.mail", overrides: beatsDefault),
            .documents
        )
    }

    private static func testStoredOverridesRoundTrip() {
        let suiteName = "MisprFlowTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            TestSupport.expect(false, "Test UserDefaults suite should create")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        TestSupport.expectEqual(UsageCategoryMapper.storedOverrides(defaults: defaults), [:])
        UsageCategoryMapper.setOverride(
            bundleID: "com.example.custom-app",
            category: .documents,
            defaults: defaults
        )
        TestSupport.expectEqual(
            UsageCategoryMapper.storedOverrides(defaults: defaults),
            ["com.example.custom-app": .documents]
        )
        // Unknown raw values are ignored instead of crashing parsing.
        defaults.set(["com.example.bad": "not-a-category"], forKey: UsageCategoryMapper.overridesStorageKey)
        TestSupport.expectEqual(UsageCategoryMapper.storedOverrides(defaults: defaults), [:])
        // The retired AI Prompts value migrates to AI Tools.
        defaults.set(["com.example.legacy": "aiPrompts"], forKey: UsageCategoryMapper.overridesStorageKey)
        TestSupport.expectEqual(
            UsageCategoryMapper.storedOverrides(defaults: defaults),
            ["com.example.legacy": .aiTools]
        )
        defaults.removeObject(forKey: UsageCategoryMapper.overridesStorageKey)
        UsageCategoryMapper.setOverride(
            bundleID: "com.example.custom-app",
            category: .documents,
            defaults: defaults
        )
        UsageCategoryMapper.removeOverride(bundleID: "com.example.custom-app", defaults: defaults)
        TestSupport.expectEqual(UsageCategoryMapper.storedOverrides(defaults: defaults), [:])
    }

    // MARK: - Aggregation

    private static func testBreakdownAggregationAndShares() {
        let calendar = StatsTestSupport.gmtCalendar()
        let today = StatsTestSupport.date(2026, 9, 11, 18)
        let overrides: [String: UsageCategory] = [
            "com.example.ai-chat": .aiTools,
            "com.example.mailer": .emails,
        ]
        let events = [
            StatsTestSupport.dictationEvent(
                timestamp: StatsTestSupport.date(2026, 9, 10, 9),
                words: 100,
                bundleID: "com.example.ai-chat",
                appName: "Example Chat"
            ),
            StatsTestSupport.dictationEvent(
                timestamp: StatsTestSupport.date(2026, 9, 10, 10),
                words: 50,
                bundleID: "com.example.ai-chat",
                appName: "Example Chat"
            ),
            StatsTestSupport.dictationEvent(
                timestamp: StatsTestSupport.date(2026, 9, 11, 9),
                words: 30,
                bundleID: "com.example.mailer",
                appName: "Example Mail"
            ),
            // Pre-tracking row: no app identity.
            StatsTestSupport.dictationEvent(timestamp: StatsTestSupport.date(2026, 9, 11, 10), words: 20),
        ]
        let snapshot = StatsCalculator.snapshot(
            events: events,
            baselineWPM: 40,
            calendar: calendar,
            today: today,
            categoryOverrides: overrides
        )
        TestSupport.expectEqual(snapshot.totalDictations, 4)
        TestSupport.expectEqual(snapshot.attributedDictations, 3)
        TestSupport.expectEqual(snapshot.unattributedDictations, 1)
        TestSupport.expectEqual(snapshot.totalAppsUsed, 2)

        TestSupport.expectEqual(snapshot.categoryBreakdown.count, 2)
        let tools = snapshot.categoryBreakdown[0]
        TestSupport.expectEqual(tools.key, UsageCategory.aiTools.rawValue)
        TestSupport.expectEqual(tools.displayName, "AI Tools")
        TestSupport.expectEqual(tools.dictations, 2)
        TestSupport.expectEqual(tools.words, 150)
        TestSupport.expectApproximatelyEqual(tools.shareOfDictations, 2.0 / 3.0)
        TestSupport.expectApproximatelyEqual(tools.shareOfWords, 150.0 / 180.0)
        let emails = snapshot.categoryBreakdown[1]
        TestSupport.expectEqual(emails.key, UsageCategory.emails.rawValue)
        TestSupport.expectEqual(emails.dictations, 1)
        TestSupport.expectEqual(emails.words, 30)
        TestSupport.expectApproximatelyEqual(emails.shareOfDictations, 1.0 / 3.0)
        TestSupport.expectApproximatelyEqual(emails.shareOfWords, 30.0 / 180.0)

        TestSupport.expectEqual(snapshot.appBreakdown.count, 2)
        let chat = snapshot.appBreakdown[0]
        TestSupport.expectEqual(chat.key, "com.example.ai-chat")
        TestSupport.expectEqual(chat.displayName, "Example Chat")
        TestSupport.expectEqual(chat.icon, UsageCategory.aiTools.iconSystemName)
        TestSupport.expectEqual(chat.dictations, 2)
        TestSupport.expectEqual(chat.words, 150)
        TestSupport.expectEqual(chat.bundleID, "com.example.ai-chat")
    }

    private static func testFailedRunsNeverEnterBreakdowns() {
        let events = [
            StatsTestSupport.dictationEvent(
                timestamp: StatsTestSupport.date(2026, 9, 11, 9),
                words: 0,
                producedOutput: false,
                bundleID: "com.example.ai-chat",
                appName: "Example Chat"
            )
        ]
        let snapshot = StatsCalculator.snapshot(
            events: events,
            baselineWPM: 40,
            calendar: StatsTestSupport.gmtCalendar(),
            today: StatsTestSupport.date(2026, 9, 11, 18)
        )
        TestSupport.expectEqual(snapshot.attributedDictations, 0)
        TestSupport.expectEqual(snapshot.unattributedDictations, 0)
        TestSupport.expectEqual(snapshot.categoryBreakdown.count, 0)
        TestSupport.expectEqual(snapshot.appBreakdown.count, 0)
        TestSupport.expectEqual(snapshot.totalAppsUsed, 0)
    }

    private static func testAppBreakdownCapsAtTop6PlusOther() {
        // Dictation counts: app0 ×4, app1 ×3, app2…app7 ×1. Words rise with
        // the index so the 1-count tie-break (words desc) is deterministic.
        var events: [DictationStatEvent] = []
        let counts = [4, 3, 1, 1, 1, 1, 1, 1]
        for (index, count) in counts.enumerated() {
            for _ in 0..<count {
                events.append(StatsTestSupport.dictationEvent(
                    timestamp: StatsTestSupport.date(2026, 9, 11, 9),
                    words: 10 * (index + 1),
                    bundleID: "com.example.app\(index)",
                    appName: "Example App \(index)"
                ))
            }
        }
        let snapshot = StatsCalculator.snapshot(
            events: events,
            baselineWPM: 40,
            calendar: StatsTestSupport.gmtCalendar(),
            today: StatsTestSupport.date(2026, 9, 11, 18)
        )
        TestSupport.expectEqual(snapshot.totalAppsUsed, 8)
        TestSupport.expectEqual(snapshot.appBreakdown.count, 7)
        TestSupport.expectEqual(snapshot.appBreakdown[0].key, "com.example.app0")
        TestSupport.expectEqual(snapshot.appBreakdown[0].dictations, 4)
        TestSupport.expectEqual(snapshot.appBreakdown[1].key, "com.example.app1")
        // Tie-break by words desc picks app7…app4 for the remaining head rows.
        TestSupport.expectEqual(snapshot.appBreakdown[2].key, "com.example.app7")
        // The tail (app2 + app3) rolls into a single "Other" row.
        guard let other = snapshot.appBreakdown.last else {
            TestSupport.expect(false, "App breakdown should end with an Other rollup")
            return
        }
        TestSupport.expectEqual(other.key, "other")
        TestSupport.expectEqual(other.displayName, "Other")
        TestSupport.expectEqual(other.dictations, 2)
        TestSupport.expectEqual(other.words, 70)
        TestSupport.expectEqual(other.bundleID, nil)
        // The manager list stays uncapped so rolled-up apps remain remappable.
        TestSupport.expectEqual(snapshot.allAppBreakdown.count, 8)
        TestSupport.expectEqual(snapshot.allAppBreakdown[0].key, "com.example.app0")
        TestSupport.expect(
            snapshot.allAppBreakdown.contains { $0.key == "com.example.app2" },
            "allAppBreakdown should include apps rolled into Other"
        )
        TestSupport.expect(
            snapshot.allAppBreakdown.contains { $0.key == "com.example.app3" },
            "allAppBreakdown should include apps rolled into Other"
        )
    }

    // MARK: - Store

    private static func testStoreRoundTripPreservesAppIdentity() {
        let store = StatsStore(configuration: .inMemory)
        let event = StatsTestSupport.dictationEvent(
            timestamp: StatsTestSupport.date(2026, 9, 11, 9),
            words: 42,
            bundleID: "com.example.ai-chat",
            appName: "Example Chat"
        )
        do {
            try store.record(event)
        } catch {
            TestSupport.expect(false, "Record should succeed: \(error.localizedDescription)")
            return
        }
        let loaded = store.loadAll()
        TestSupport.expectEqual(loaded.count, 1)
        TestSupport.expectEqual(loaded[0].bundleID, "com.example.ai-chat")
        TestSupport.expectEqual(loaded[0].appName, "Example Chat")
    }

    private static func testRetryUpdatePreservesAppAttribution() {
        let store = StatsStore(configuration: .inMemory)
        let historyID = UUID()
        let original = StatsTestSupport.dictationEvent(
            timestamp: StatsTestSupport.date(2026, 9, 10, 9),
            words: 10,
            bundleID: "com.example.mailer",
            appName: "Example Mail"
        )
        let originalWithHistory = DictationStatEvent(
            historyID: historyID,
            timestamp: original.timestamp,
            day: original.day,
            run: original.run,
            bundleID: original.bundleID,
            appName: original.appName
        )
        do {
            try store.record(originalWithHistory)
            let updated = try store.update(
                forHistoryID: historyID,
                run: StatsRunRecord(
                    kind: .dictation,
                    producedOutput: true,
                    spokenWordCount: 42,
                    outputWordCount: 40,
                    audioDurationSec: 30
                )
            )
            guard let updated else {
                TestSupport.expect(false, "Update should return the updated event")
                return
            }
            TestSupport.expectEqual(updated.run.outputWordCount, 40)
            TestSupport.expectEqual(updated.bundleID, "com.example.mailer")
            TestSupport.expectEqual(updated.appName, "Example Mail")
        } catch {
            TestSupport.expect(false, "Update should succeed: \(error.localizedDescription)")
        }
    }

    private static func testFillAppAttribution() {
        let store = StatsStore(configuration: .inMemory)
        let historyID = UUID()
        let unattributed = DictationStatEvent(
            historyID: historyID,
            timestamp: StatsTestSupport.date(2026, 9, 10, 9),
            day: StatsDay(date: StatsTestSupport.date(2026, 9, 10, 9), calendar: StatsTestSupport.gmtCalendar()),
            run: StatsRunRecord(kind: .dictation, producedOutput: true, spokenWordCount: 10, outputWordCount: 10)
        )
        do {
            try store.record(unattributed)
            let filled = try store.fillAppAttribution(
                forHistoryID: historyID,
                bundleID: "com.example.mailer",
                appName: "Example Mail"
            )
            TestSupport.expectEqual(filled?.bundleID, "com.example.mailer")
            TestSupport.expectEqual(filled?.appName, "Example Mail")
            // A second fill must not overwrite recorded attribution.
            let refilled = try store.fillAppAttribution(
                forHistoryID: historyID,
                bundleID: "com.example.other",
                appName: "Other App"
            )
            TestSupport.expectEqual(refilled?.bundleID, "com.example.mailer")
            TestSupport.expectEqual(refilled?.appName, "Example Mail")
            // Nothing to fill, and no matching row, both return nil.
            let nilFill = try store.fillAppAttribution(forHistoryID: historyID, bundleID: nil, appName: nil)
            TestSupport.expectEqual(nilFill, nil)
            let missingRow = try store.fillAppAttribution(
                forHistoryID: UUID(),
                bundleID: "com.example.x",
                appName: nil
            )
            TestSupport.expectEqual(missingRow, nil)
        } catch {
            TestSupport.expect(false, "Fill should succeed: \(error.localizedDescription)")
        }
    }

    // MARK: - Migration

    private static func testV1StoreMigratesWithNilAppFields() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MisprFlowTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            TestSupport.expect(false, "Test directory should create")
            return
        }
        seedV1Store(in: directory)

        let store = StatsStore(configuration: CoreDataStoreBootstrap.Configuration(
            storeFileName: "DictationStats.sqlite",
            policy: .quarantine,
            storeDirectoryURL: directory
        ))
        TestSupport.expect(store.isPersistent, "Migrated store should report persistent")
        let loaded = store.loadAll()
        TestSupport.expectEqual(loaded.count, 1)
        TestSupport.expectEqual(loaded[0].run.spokenWordCount, 10)
        TestSupport.expectEqual(loaded[0].run.outputWordCount, 12)
        TestSupport.expectEqual(loaded[0].bundleID, nil)
        TestSupport.expectEqual(loaded[0].appName, nil)
    }

    /// Writes one row with the pre-feature stats-v1 model so the migration
    /// test can verify lightweight migration to stats-v2.
    private static func seedV1Store(in directory: URL) {
        let model = NSManagedObjectModel()
        model.versionIdentifiers = ["stats-v1"]
        let entity = NSEntityDescription()
        entity.name = "DictationStatEntry"
        entity.managedObjectClassName = NSStringFromClass(DictationStatEntry.self)
        let historyIDAttribute = CoreDataStoreBootstrap.makeAttribute(
            name: "historyID",
            type: .UUIDAttributeType,
            isOptional: true
        )
        entity.properties = [
            CoreDataStoreBootstrap.makeAttribute(name: "id", type: .UUIDAttributeType, isOptional: false),
            historyIDAttribute,
            CoreDataStoreBootstrap.makeAttribute(name: "timestamp", type: .dateAttributeType, isOptional: false),
            CoreDataStoreBootstrap.makeAttribute(name: "dayKey", type: .stringAttributeType, isOptional: false),
            CoreDataStoreBootstrap.makeAttribute(name: "localHour", type: .integer16AttributeType, isOptional: false, defaultValue: 0),
            CoreDataStoreBootstrap.makeAttribute(name: "localWeekday", type: .integer16AttributeType, isOptional: false, defaultValue: 1),
            CoreDataStoreBootstrap.makeAttribute(name: "runKind", type: .stringAttributeType, isOptional: false, defaultValue: "dictation"),
            CoreDataStoreBootstrap.makeAttribute(name: "producedOutput", type: .booleanAttributeType, isOptional: false, defaultValue: true),
            CoreDataStoreBootstrap.makeAttribute(name: "spokenWordCount", type: .integer64AttributeType, isOptional: false, defaultValue: 0),
            CoreDataStoreBootstrap.makeAttribute(name: "outputWordCount", type: .integer64AttributeType, isOptional: false, defaultValue: 0),
            CoreDataStoreBootstrap.makeAttribute(name: "audioDurationSec", type: .doubleAttributeType, isOptional: true),
        ]
        entity.indexes = [NSFetchIndexDescription(
            name: "byHistoryID",
            elements: [NSFetchIndexElementDescription(property: historyIDAttribute, collationType: .binary)]
        )]
        model.entities = [entity]

        let container = NSPersistentContainer(name: "DictationStats", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: directory.appendingPathComponent("DictationStats.sqlite"))
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]
        let semaphore = DispatchSemaphore(value: 0)
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
            semaphore.signal()
        }
        semaphore.wait()
        TestSupport.expect(loadError == nil, "v1 seed store should load")
        container.viewContext.performAndWait {
            guard let object = NSEntityDescription.insertNewObject(
                forEntityName: "DictationStatEntry",
                into: container.viewContext
            ) as? DictationStatEntry else {
                TestSupport.expect(false, "v1 seed insert should produce an entry")
                return
            }
            object.id = UUID()
            object.timestamp = StatsTestSupport.date(2026, 9, 10, 9)
            object.dayKey = "2026-09-10"
            object.localHour = 9
            object.localWeekday = 4
            object.runKind = "dictation"
            object.producedOutput = true
            object.spokenWordCount = 10
            object.outputWordCount = 12
            do {
                try container.viewContext.save()
            } catch {
                TestSupport.expect(false, "v1 seed save should succeed")
            }
        }
    }
}
