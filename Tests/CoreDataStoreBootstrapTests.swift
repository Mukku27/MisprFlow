import Foundation
import CoreData

enum CoreDataStoreBootstrapTests {
    static func run() {
        testFileBackedLoadSucceeds()
        testQuarantinePreservesCorruptStore()
        testRecreateDeletesCorruptStore()
        testInMemoryConfigurationLoads()
        testMakeAttribute()
        testPipelineHistoryStoreRoundTrip()
    }

    private static func testModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "TestEntry"
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = [
            CoreDataStoreBootstrap.makeAttribute(name: "id", type: .UUIDAttributeType, isOptional: false),
            CoreDataStoreBootstrap.makeAttribute(name: "note", type: .stringAttributeType, isOptional: true)
        ]
        model.entities = [entity]
        return model
    }

    private static func tempDirectory() -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MisprFlowTests-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        } catch {
            TestSupport.expect(false, "Failed to create temp directory: \(error.localizedDescription)")
        }
        return base
    }

    private static func testFileBackedLoadSucceeds() {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = CoreDataStoreBootstrap.Configuration(
            storeFileName: "Test.sqlite",
            policy: .quarantine,
            storeDirectoryURL: directory
        )
        let result = CoreDataStoreBootstrap.load(
            containerName: "Test",
            model: testModel(),
            configuration: configuration
        )
        TestSupport.expectEqual(result.state, .persistent)
        TestSupport.expect(
            FileManager.default.fileExists(atPath: directory.appendingPathComponent("Test.sqlite").path),
            "Store file should exist after a successful load"
        )
        TestSupport.expectEqual(result.quarantinedFileName, nil)
    }

    private static func testQuarantinePreservesCorruptStore() {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Test.sqlite")
        let corruptBytes = Data("not a database".utf8)
        do {
            try corruptBytes.write(to: storeURL)
        } catch {
            TestSupport.expect(false, "Failed to write corrupt store: \(error.localizedDescription)")
        }
        let configuration = CoreDataStoreBootstrap.Configuration(
            storeFileName: "Test.sqlite",
            policy: .quarantine,
            storeDirectoryURL: directory
        )
        let result = CoreDataStoreBootstrap.load(
            containerName: "Test",
            model: testModel(),
            configuration: configuration
        )
        TestSupport.expectEqual(result.state, .persistent)
        guard let quarantinedFileName = result.quarantinedFileName else {
            TestSupport.expect(false, "Quarantine should record the moved file name")
            return
        }
        let quarantinedURL = directory.appendingPathComponent(quarantinedFileName)
        let preserved: Data
        do {
            preserved = try Data(contentsOf: quarantinedURL)
        } catch {
            TestSupport.expect(false, "Quarantined file should be readable: \(error.localizedDescription)")
            return
        }
        TestSupport.expectEqual(preserved, corruptBytes)
        TestSupport.expect(
            FileManager.default.fileExists(atPath: storeURL.path),
            "A fresh store should exist after quarantine recovery"
        )
        TestSupport.expectEqual(entityCount(in: result.container), 0)
    }

    private static func testRecreateDeletesCorruptStore() {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Test.sqlite")
        do {
            try Data("not a database".utf8).write(to: storeURL)
        } catch {
            TestSupport.expect(false, "Failed to write corrupt store: \(error.localizedDescription)")
        }
        let configuration = CoreDataStoreBootstrap.Configuration(
            storeFileName: "Test.sqlite",
            policy: .recreate,
            storeDirectoryURL: directory
        )
        let result = CoreDataStoreBootstrap.load(
            containerName: "Test",
            model: testModel(),
            configuration: configuration
        )
        TestSupport.expectEqual(result.state, .persistent)
        TestSupport.expectEqual(result.quarantinedFileName, nil)
        TestSupport.expectEqual(entityCount(in: result.container), 0)
    }

    private static func testInMemoryConfigurationLoads() {
        let result = CoreDataStoreBootstrap.load(
            containerName: "Test",
            model: testModel(),
            configuration: .inMemory
        )
        guard case .inMemory = result.state else {
            TestSupport.expect(false, "Expected an in-memory state, got \(result.state)")
            return
        }
        TestSupport.expect(result.state.isUsable, "In-memory state should be usable")
        TestSupport.expect(!result.state.isPersistent, "In-memory state should not be persistent")
        TestSupport.expectEqual(entityCount(in: result.container), 0)
    }

    private static func testMakeAttribute() {
        let attribute = CoreDataStoreBootstrap.makeAttribute(
            name: "wordCount",
            type: .integer64AttributeType,
            isOptional: false,
            defaultValue: 0
        )
        TestSupport.expectEqual(attribute.name, "wordCount")
        TestSupport.expectEqual(attribute.attributeType.rawValue, NSAttributeType.integer64AttributeType.rawValue)
        TestSupport.expectEqual(attribute.isOptional, false)
    }

    private static func testPipelineHistoryStoreRoundTrip() {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PipelineHistoryStore(configuration: CoreDataStoreBootstrap.Configuration(
            storeFileName: "PipelineHistory.sqlite",
            policy: .recreate,
            storeDirectoryURL: directory
        ))
        let item = PipelineHistoryItem(
            timestamp: Date(timeIntervalSince1970: 1_787_534_400),
            rawTranscript: "synthetic raw words",
            postProcessedTranscript: "synthetic polished words",
            postProcessingPrompt: nil,
            contextSummary: "synthetic summary",
            contextScreenshotDataURL: nil,
            contextScreenshotStatus: "synthetic status",
            postProcessingStatus: "synthetic ok",
            debugStatus: "synthetic debug",
            customVocabulary: ""
        )
        do {
            let removed = try store.append(item, maxCount: 20)
            TestSupport.expectEqual(removed, [])
        } catch {
            TestSupport.expect(false, "Append should succeed: \(error.localizedDescription)")
        }
        let loaded = store.loadAllHistory()
        TestSupport.expectEqual(loaded.count, 1)
        TestSupport.expectEqual(loaded.first?.rawTranscript, "synthetic raw words")
        TestSupport.expectEqual(loaded.first?.postProcessedTranscript, "synthetic polished words")
    }

    private static func entityCount(in container: NSPersistentContainer) -> Int {
        var count = -1
        container.viewContext.performAndWait {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: "TestEntry")
            count = (try? container.viewContext.count(for: request)) ?? -1
        }
        return count
    }
}
