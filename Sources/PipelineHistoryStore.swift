import Foundation
import CoreData

final class PipelineHistoryStore {
    private let container: NSPersistentContainer
    private let isStoreLoaded: Bool

    init(configuration: CoreDataStoreBootstrap.Configuration = .pipelineHistory) {
        let result = CoreDataStoreBootstrap.load(
            containerName: "PipelineHistory",
            model: Self.makeModel(),
            configuration: configuration
        )
        container = result.container
        isStoreLoaded = result.state.isUsable
    }

    func loadAllHistory() -> [PipelineHistoryItem] {
        guard isStoreLoaded else { return [] }
        var result: [PipelineHistoryItem] = []
        container.viewContext.performAndWait {
            let request = pipelineHistoryRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
            guard let entities = try? container.viewContext.fetch(request) else { return }
            result = entities.compactMap(Self.makeHistoryItem(from:))
        }
        return result
    }

    func append(_ item: PipelineHistoryItem, maxCount: Int) throws -> [String] {
        guard isStoreLoaded else { return [] }
        try insert(item)
        return try trim(to: maxCount)
    }

    func update(_ item: PipelineHistoryItem) throws {
        guard isStoreLoaded else { return }

        var thrownError: Error?
        container.viewContext.performAndWait {
            do {
                let request = pipelineHistoryRequest()
                request.predicate = NSPredicate(format: "id == %@", item.id as CVarArg)
                guard let entity = try container.viewContext.fetch(request).first else { return }
                entity.intent = item.intent.rawValue
                entity.selectedText = item.selectedText
                entity.capturedSelection = item.capturedSelection
                entity.rawTranscript = item.rawTranscript
                entity.postProcessedTranscript = item.postProcessedTranscript
                entity.postProcessingPrompt = item.postProcessingPrompt
                entity.systemPrompt = item.systemPrompt
                entity.contextSystemPrompt = item.contextSystemPrompt
                entity.postProcessingStatus = item.postProcessingStatus
                entity.debugStatus = item.debugStatus
                entity.contextAppName = item.contextAppName
                entity.contextBundleIdentifier = item.contextBundleIdentifier
                entity.contextWindowTitle = item.contextWindowTitle
                try saveContext()
            } catch {
                thrownError = error
            }
        }
        if let thrownError { throw thrownError }
    }

    func delete(id: UUID) throws -> String? {
        guard isStoreLoaded else { return nil }

        var deletedAudioFileName: String?
        var thrownError: Error?
        container.viewContext.performAndWait {
            do {
                let request = pipelineHistoryRequest()
                request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                guard let entity = try container.viewContext.fetch(request).first else { return }
                deletedAudioFileName = entity.audioFileName
                container.viewContext.delete(entity)
                try saveContext()
            } catch {
                thrownError = error
            }
        }
        if let thrownError { throw thrownError }
        return deletedAudioFileName
    }

    func clearAll() throws -> [String] {
        guard isStoreLoaded else { return [] }

        var audioFileNames: [String] = []
        var thrownError: Error?
        container.viewContext.performAndWait {
            do {
                let request = pipelineHistoryRequest()
                request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
                guard let entities = try? container.viewContext.fetch(request) else { return }
                audioFileNames = entities.compactMap(\.audioFileName)
                for entity in entities {
                    container.viewContext.delete(entity)
                }
                try saveContext()
            } catch {
                thrownError = error
            }
        }
        if let thrownError { throw thrownError }
        return audioFileNames
    }

    func trim(to maxCount: Int) throws -> [String] {
        guard isStoreLoaded else { return [] }
        guard maxCount > 0 else {
            let audioFileNames = try clearAll()
            return audioFileNames
        }

        var audioFileNames: [String] = []
        var thrownError: Error?
        container.viewContext.performAndWait {
            do {
                let request = pipelineHistoryRequest()
                request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
                guard let entities = try? container.viewContext.fetch(request), entities.count > maxCount else { return }
                let dropped = entities[maxCount...]
                audioFileNames = dropped.compactMap(\.audioFileName)
                for entity in dropped {
                    container.viewContext.delete(entity)
                }
                try saveContext()
            } catch {
                thrownError = error
            }
        }
        if let thrownError { throw thrownError }
        return audioFileNames
    }

    private func insert(_ item: PipelineHistoryItem) throws {
        guard isStoreLoaded else { return }

        var thrownError: Error?
        container.viewContext.performAndWait {
            do {
                let context = container.viewContext
                let entity = PipelineHistoryEntry(context: context)
                entity.id = item.id
                entity.intent = item.intent.rawValue
                entity.selectedText = item.selectedText
                entity.capturedSelection = item.capturedSelection
                entity.timestamp = item.timestamp
                entity.rawTranscript = item.rawTranscript
                entity.postProcessedTranscript = item.postProcessedTranscript
                entity.postProcessingPrompt = item.postProcessingPrompt
                entity.systemPrompt = item.systemPrompt
                entity.contextSummary = item.contextSummary
                entity.contextSystemPrompt = item.contextSystemPrompt
                entity.contextPrompt = item.contextPrompt
                entity.contextScreenshotDataURL = item.contextScreenshotDataURL
                entity.contextScreenshotStatus = item.contextScreenshotStatus
                entity.postProcessingStatus = item.postProcessingStatus
                entity.debugStatus = item.debugStatus
                entity.customVocabulary = item.customVocabulary
                entity.audioFileName = item.audioFileName
                entity.contextAppName = item.contextAppName
                entity.contextBundleIdentifier = item.contextBundleIdentifier
                entity.contextWindowTitle = item.contextWindowTitle
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

    private func pipelineHistoryRequest() -> NSFetchRequest<PipelineHistoryEntry> {
        NSFetchRequest<PipelineHistoryEntry>(entityName: "PipelineHistoryEntry")
    }

    private static func makeHistoryItem(from entity: PipelineHistoryEntry) -> PipelineHistoryItem {
        PipelineHistoryItem(
            intent: PipelineHistoryItemIntent(rawValue: entity.intent ?? "") ?? .dictation,
            selectedText: entity.selectedText,
            capturedSelection: entity.capturedSelection,
            id: entity.id,
            timestamp: entity.timestamp ?? Date(),
            rawTranscript: entity.rawTranscript ?? "",
            postProcessedTranscript: entity.postProcessedTranscript ?? "",
            postProcessingPrompt: entity.postProcessingPrompt,
            systemPrompt: entity.systemPrompt,
            contextSummary: entity.contextSummary ?? "",
            contextSystemPrompt: entity.contextSystemPrompt,
            contextPrompt: entity.contextPrompt,
            contextScreenshotDataURL: entity.contextScreenshotDataURL,
            contextScreenshotStatus: entity.contextScreenshotStatus ?? "available (image)",
            postProcessingStatus: entity.postProcessingStatus ?? "",
            debugStatus: entity.debugStatus ?? "",
            customVocabulary: entity.customVocabulary ?? "",
            audioFileName: entity.audioFileName,
            contextAppName: entity.contextAppName,
            contextBundleIdentifier: entity.contextBundleIdentifier,
            contextWindowTitle: entity.contextWindowTitle
        )
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let entity = NSEntityDescription()
        entity.name = "PipelineHistoryEntry"
        entity.managedObjectClassName = NSStringFromClass(PipelineHistoryEntry.self)

        entity.properties = [
            CoreDataStoreBootstrap.makeAttribute(name: "intent", type: .stringAttributeType, isOptional: true, defaultValue: "dictation"),
            CoreDataStoreBootstrap.makeAttribute(name: "selectedText", type: .stringAttributeType, isOptional: true),
            CoreDataStoreBootstrap.makeAttribute(name: "capturedSelection", type: .stringAttributeType, isOptional: true),
            CoreDataStoreBootstrap.makeAttribute(name: "id", type: .UUIDAttributeType, isOptional: false),
            CoreDataStoreBootstrap.makeAttribute(name: "timestamp", type: .dateAttributeType, isOptional: false),
            CoreDataStoreBootstrap.makeAttribute(name: "rawTranscript", type: .stringAttributeType, isOptional: false),
            CoreDataStoreBootstrap.makeAttribute(name: "postProcessedTranscript", type: .stringAttributeType, isOptional: false),
            CoreDataStoreBootstrap.makeAttribute(name: "postProcessingPrompt", type: .stringAttributeType, isOptional: true),
            CoreDataStoreBootstrap.makeAttribute(name: "systemPrompt", type: .stringAttributeType, isOptional: true),
            CoreDataStoreBootstrap.makeAttribute(name: "contextSummary", type: .stringAttributeType, isOptional: false),
            CoreDataStoreBootstrap.makeAttribute(name: "contextSystemPrompt", type: .stringAttributeType, isOptional: true),
            CoreDataStoreBootstrap.makeAttribute(name: "contextPrompt", type: .stringAttributeType, isOptional: true),
            CoreDataStoreBootstrap.makeAttribute(name: "contextScreenshotDataURL", type: .stringAttributeType, isOptional: true),
            CoreDataStoreBootstrap.makeAttribute(name: "contextScreenshotStatus", type: .stringAttributeType, isOptional: false),
            CoreDataStoreBootstrap.makeAttribute(name: "postProcessingStatus", type: .stringAttributeType, isOptional: false),
            CoreDataStoreBootstrap.makeAttribute(name: "debugStatus", type: .stringAttributeType, isOptional: false),
            CoreDataStoreBootstrap.makeAttribute(name: "customVocabulary", type: .stringAttributeType, isOptional: false),
            CoreDataStoreBootstrap.makeAttribute(name: "audioFileName", type: .stringAttributeType, isOptional: true),
            CoreDataStoreBootstrap.makeAttribute(name: "contextAppName", type: .stringAttributeType, isOptional: true),
            CoreDataStoreBootstrap.makeAttribute(name: "contextBundleIdentifier", type: .stringAttributeType, isOptional: true),
            CoreDataStoreBootstrap.makeAttribute(name: "contextWindowTitle", type: .stringAttributeType, isOptional: true)
        ]

        model.entities = [entity]
        return model
    }
}

@objc(PipelineHistoryEntry)
final class PipelineHistoryEntry: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var intent: String?
    @NSManaged var selectedText: String?
    @NSManaged var capturedSelection: String?
    @NSManaged var timestamp: Date?
    @NSManaged var rawTranscript: String?
    @NSManaged var postProcessedTranscript: String?
    @NSManaged var postProcessingPrompt: String?
    @NSManaged var systemPrompt: String?
    @NSManaged var contextSummary: String?
    @NSManaged var contextSystemPrompt: String?
    @NSManaged var contextPrompt: String?
    @NSManaged var contextScreenshotDataURL: String?
    @NSManaged var contextScreenshotStatus: String?
    @NSManaged var postProcessingStatus: String?
    @NSManaged var debugStatus: String?
    @NSManaged var customVocabulary: String?
    @NSManaged var audioFileName: String?
    @NSManaged var contextAppName: String?
    @NSManaged var contextBundleIdentifier: String?
    @NSManaged var contextWindowTitle: String?
}
