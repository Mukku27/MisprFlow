import Foundation
import CoreData

/// Append-only store for dictation stats. Numbers plus the originating
/// app's identity (bundle ID + app name) only: run facts, durations,
/// timestamps, and which app was dictated into. Transcript text stays in the
/// rolling PipelineHistoryStore; clearing or trimming history never touches
/// stats. Window titles, selections, screenshots, and transcripts are never
/// persisted here.
///
/// The API takes ``StatsRunRecord`` values, never transcript strings, so no
/// future change can accidentally persist user text here.
final class StatsStore {
    private let container: NSPersistentContainer
    let state: CoreDataStoreBootstrap.State
    let quarantinedFileName: String?

    var isPersistent: Bool { state.isPersistent }
    private var isUsable: Bool { state.isUsable }

    init(configuration: CoreDataStoreBootstrap.Configuration = .stats) {
        let result = CoreDataStoreBootstrap.load(
            containerName: "DictationStats",
            model: Self.makeModel(),
            configuration: configuration
        )
        container = result.container
        state = result.state
        quarantinedFileName = result.quarantinedFileName
    }

    /// Launch-time load, newest first. Callers maintain the in-memory copy
    /// incrementally afterwards; this is never called on the paste path.
    func loadAll() -> [DictationStatEvent] {
        guard isUsable else { return [] }
        var result: [DictationStatEvent] = []
        container.viewContext.performAndWait {
            let request = statsRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
            guard let entities = try? container.viewContext.fetch(request) else { return }
            result = entities.map(Self.makeEvent(from:))
        }
        return result
    }

    func count() -> Int {
        guard isUsable else { return 0 }
        var count = 0
        container.viewContext.performAndWait {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: "DictationStatEntry")
            count = (try? container.viewContext.count(for: request)) ?? 0
        }
        return count
    }

    /// Stats for the given history entries, keyed by history ID. Used to
    /// populate the Run Log index without loading the whole store.
    func events(forHistoryIDs historyIDs: Set<UUID>) -> [UUID: DictationStatEvent] {
        guard isUsable, !historyIDs.isEmpty else { return [:] }
        var result: [UUID: DictationStatEvent] = [:]
        container.viewContext.performAndWait {
            let request = statsRequest()
            request.predicate = NSPredicate(format: "historyID IN %@", Array(historyIDs))
            guard let entities = try? container.viewContext.fetch(request) else { return }
            for entity in entities {
                if let historyID = entity.historyID {
                    result[historyID] = Self.makeEvent(from: entity)
                }
            }
        }
        return result
    }

    func record(_ event: DictationStatEvent) throws {
        guard isUsable else { return }

        var thrownError: Error?
        container.viewContext.performAndWait {
            do {
                let entity = DictationStatEntry(context: container.viewContext)
                Self.populate(entity, from: event)
                try saveContext()
            } catch {
                thrownError = error
            }
        }
        if let thrownError { throw thrownError }
    }

    /// Replaces the run facts of the row linked to a history entry after a
    /// retry, keeping the original id, timestamp, day, and app attribution
    /// so streaks and trends stay stable. Update-only: returns nil when no
    /// row exists for the history entry, so retries never resurrect cleared
    /// stats.
    @discardableResult
    func update(forHistoryID historyID: UUID, run: StatsRunRecord) throws -> DictationStatEvent? {
        guard isUsable else { return nil }

        var updated: DictationStatEvent?
        var thrownError: Error?
        container.viewContext.performAndWait {
            do {
                let request = statsRequest()
                request.predicate = NSPredicate(format: "historyID == %@", historyID as CVarArg)
                guard let entity = try container.viewContext.fetch(request).first else { return }
                entity.runKind = run.kind.rawValue
                entity.producedOutput = run.producedOutput
                entity.spokenWordCount = Int64(run.spokenWordCount)
                entity.outputWordCount = Int64(run.outputWordCount)
                entity.audioDurationSec = run.audioDurationSec.map { NSNumber(value: $0) }
                try saveContext()
                updated = Self.makeEvent(from: entity)
            } catch {
                thrownError = error
            }
        }
        if let thrownError { throw thrownError }
        return updated
    }

    /// One-shot backfill of app attribution: fills bundle ID / app name on
    /// rows that predate app tracking by joining to still-present pipeline
    /// history. Only fills fields that are currently nil, so recorded
    /// attribution is never overwritten. Returns nil when no row exists for
    /// the history entry.
    @discardableResult
    func fillAppAttribution(
        forHistoryID historyID: UUID,
        bundleID: String?,
        appName: String?
    ) throws -> DictationStatEvent? {
        guard isUsable else { return nil }
        guard bundleID != nil || appName != nil else { return nil }

        var updated: DictationStatEvent?
        var thrownError: Error?
        container.viewContext.performAndWait {
            do {
                let request = statsRequest()
                request.predicate = NSPredicate(format: "historyID == %@", historyID as CVarArg)
                guard let entity = try container.viewContext.fetch(request).first else { return }
                var changed = false
                if entity.bundleID == nil, let bundleID {
                    entity.bundleID = bundleID
                    changed = true
                }
                if entity.appName == nil, let appName {
                    entity.appName = appName
                    changed = true
                }
                if changed {
                    try saveContext()
                }
                updated = Self.makeEvent(from: entity)
            } catch {
                thrownError = error
            }
        }
        if let thrownError { throw thrownError }
        return updated
    }

    func clearAll() throws {
        guard isUsable else { return }

        var thrownError: Error?
        container.viewContext.performAndWait {
            do {
                let request = statsRequest()
                guard let entities = try? container.viewContext.fetch(request) else { return }
                for entity in entities {
                    container.viewContext.delete(entity)
                }
                try saveContext()
            } catch {
                thrownError = error
            }
        }
        if let thrownError { throw thrownError }
    }

    private func saveContext() throws {
        guard container.viewContext.hasChanges else { return }
        do {
            try container.viewContext.save()
        } catch {
            container.viewContext.rollback()
            throw error
        }
    }

    private func statsRequest() -> NSFetchRequest<DictationStatEntry> {
        NSFetchRequest<DictationStatEntry>(entityName: "DictationStatEntry")
    }

    private static func makeEvent(from entity: DictationStatEntry) -> DictationStatEvent {
        DictationStatEvent(
            id: entity.id,
            historyID: entity.historyID,
            timestamp: entity.timestamp ?? Date(),
            day: StatsDay(
                key: entity.dayKey ?? "",
                hour: Int(entity.localHour),
                weekday: Int(entity.localWeekday)
            ),
            run: StatsRunRecord(
                kind: StatsRunKind(rawValue: entity.runKind ?? "") ?? .dictation,
                producedOutput: entity.producedOutput,
                spokenWordCount: Int(entity.spokenWordCount),
                outputWordCount: Int(entity.outputWordCount),
                audioDurationSec: entity.audioDurationSec?.doubleValue
            ),
            bundleID: entity.bundleID,
            appName: entity.appName
        )
    }

    private static func populate(_ entity: DictationStatEntry, from event: DictationStatEvent) {
        entity.id = event.id
        entity.historyID = event.historyID
        entity.timestamp = event.timestamp
        entity.dayKey = event.day.key
        entity.localHour = Int16(event.day.hour)
        entity.localWeekday = Int16(event.day.weekday)
        entity.runKind = event.run.kind.rawValue
        entity.producedOutput = event.run.producedOutput
        entity.spokenWordCount = Int64(event.run.spokenWordCount)
        entity.outputWordCount = Int64(event.run.outputWordCount)
        entity.audioDurationSec = event.run.audioDurationSec.map { NSNumber(value: $0) }
        entity.bundleID = event.bundleID
        entity.appName = event.appName
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        // Only lightweight-migratable changes are allowed from here on:
        // the store is append-only and must survive upgrades. stats-v2 adds
        // optional bundleID/appName columns; v1 rows read back with nil app
        // fields.
        model.versionIdentifiers = ["stats-v2"]

        let entity = NSEntityDescription()
        entity.name = "DictationStatEntry"
        entity.managedObjectClassName = NSStringFromClass(DictationStatEntry.self)

        let historyIDAttribute = CoreDataStoreBootstrap.makeAttribute(name: "historyID", type: .UUIDAttributeType, isOptional: true)
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
            CoreDataStoreBootstrap.makeAttribute(name: "bundleID", type: .stringAttributeType, isOptional: true),
            CoreDataStoreBootstrap.makeAttribute(name: "appName", type: .stringAttributeType, isOptional: true)
        ]

        let historyIndex = NSFetchIndexDescription(
            name: "byHistoryID",
            elements: [NSFetchIndexElementDescription(property: historyIDAttribute, collationType: .binary)]
        )
        entity.indexes = [historyIndex]

        model.entities = [entity]
        return model
    }
}

@objc(DictationStatEntry)
final class DictationStatEntry: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var historyID: UUID?
    @NSManaged var timestamp: Date?
    @NSManaged var dayKey: String?
    @NSManaged var localHour: Int16
    @NSManaged var localWeekday: Int16
    @NSManaged var runKind: String?
    @NSManaged var producedOutput: Bool
    @NSManaged var spokenWordCount: Int64
    @NSManaged var outputWordCount: Int64
    @NSManaged var audioDurationSec: NSNumber?
    @NSManaged var bundleID: String?
    @NSManaged var appName: String?
}
