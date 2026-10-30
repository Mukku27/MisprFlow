import Foundation
import CoreData

/// Shared Core Data stack bootstrap for the app's SQLite stores.
///
/// The rolling pipeline-history store and the append-only stats store share
/// the same load/recovery/in-memory-fallback flow; only the recovery policy
/// differs. History recreates a corrupt store, while stats quarantines the
/// old files aside so long-lived data is never deleted automatically.
enum CoreDataStoreBootstrap {
    /// What to do with existing store files when the persistent store fails to load.
    enum RecoveryPolicy {
        /// Delete the store files and start fresh. Suitable for caches and
        /// rolling windows whose contents are expendable.
        case recreate
        /// Move the store files aside under a timestamped name and start
        /// fresh, preserving the old bytes for inspection or recovery.
        /// Suitable for append-only data that must never be deleted silently.
        case quarantine
    }

    /// How the stack ended up loading.
    enum State: Equatable {
        /// A file-backed store loaded successfully.
        case persistent
        /// Running on an in-memory store. Data is lost on relaunch.
        case inMemory(reason: String)
        /// Even the in-memory fallback failed; the store is unusable.
        case unavailable(reason: String)

        var isUsable: Bool {
            switch self {
            case .persistent, .inMemory:
                return true
            case .unavailable:
                return false
            }
        }

        var isPersistent: Bool {
            if case .persistent = self {
                return true
            }
            return false
        }
    }

    struct Configuration {
        /// SQLite file name, e.g. "PipelineHistory.sqlite".
        /// Nil means intentionally in-memory (used by tests).
        var storeFileName: String?
        var policy: RecoveryPolicy
        /// Directory holding the store file. Nil resolves to
        /// Application Support/<app name>. Tests inject a temporary
        /// directory so they never touch real user data.
        var storeDirectoryURL: URL?

        static var pipelineHistory: Configuration {
            Configuration(storeFileName: "PipelineHistory.sqlite", policy: .recreate, storeDirectoryURL: nil)
        }

        static var stats: Configuration {
            Configuration(storeFileName: "DictationStats.sqlite", policy: .quarantine, storeDirectoryURL: nil)
        }

        static var inMemory: Configuration {
            Configuration(storeFileName: nil, policy: .recreate, storeDirectoryURL: nil)
        }
    }

    struct LoadResult {
        let container: NSPersistentContainer
        let state: State
        /// File URL of the live store when file-backed, nil otherwise.
        let storeURL: URL?
        /// Base file name of the quarantined store when recovery moved
        /// files aside, nil otherwise.
        let quarantinedFileName: String?
    }

    static func load(
        containerName: String,
        model: NSManagedObjectModel,
        configuration: Configuration
    ) -> LoadResult {
        let container = NSPersistentContainer(name: containerName, managedObjectModel: model)

        guard configuration.storeFileName != nil else {
            return loadInMemory(
                container: container,
                reason: "configured without a store file",
                quarantinedFileName: nil
            )
        }

        guard let storeURL = resolvedStoreURL(configuration: configuration) else {
            return loadInMemory(
                container: container,
                reason: "store directory unavailable",
                quarantinedFileName: nil
            )
        }

        container.persistentStoreDescriptions = [sqliteDescription(url: storeURL)]
        if let loadError = loadPersistentStoresSynchronously(container: container) {
            let details = loadError as NSError
            print("[CoreDataStoreBootstrap] \(containerName): failed to load persistent store (\(details.domain) \(details.code)). Attempting recovery.")
        } else {
            return LoadResult(
                container: container,
                state: .persistent,
                storeURL: storeURL,
                quarantinedFileName: nil
            )
        }

        var quarantinedFileName: String?
        switch configuration.policy {
        case .recreate:
            removeSQLiteStoreFiles(at: storeURL)
        case .quarantine:
            quarantinedFileName = quarantineSQLiteStoreFiles(at: storeURL)
        }

        // Clear any partially loaded stores and reset descriptions before retrying.
        removeAllStores(from: container)
        container.persistentStoreDescriptions = [sqliteDescription(url: storeURL)]
        if loadPersistentStoresSynchronously(container: container) == nil {
            return LoadResult(
                container: container,
                state: .persistent,
                storeURL: storeURL,
                quarantinedFileName: quarantinedFileName
            )
        }

        print("[CoreDataStoreBootstrap] \(containerName): failed to recover persistent store. Falling back to in-memory store.")
        return loadInMemory(
            container: container,
            reason: "persistent store failed to load",
            quarantinedFileName: quarantinedFileName
        )
    }

    static func makeAttribute(
        name: String,
        type: NSAttributeType,
        isOptional: Bool,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = isOptional
        attribute.defaultValue = defaultValue
        return attribute
    }

    private static func loadInMemory(
        container: NSPersistentContainer,
        reason: String,
        quarantinedFileName: String?
    ) -> LoadResult {
        removeAllStores(from: container)
        container.persistentStoreDescriptions = [inMemoryDescription()]
        if loadPersistentStoresSynchronously(container: container) == nil {
            return LoadResult(
                container: container,
                state: .inMemory(reason: reason),
                storeURL: nil,
                quarantinedFileName: quarantinedFileName
            )
        }
        return LoadResult(
            container: container,
            state: .unavailable(reason: reason),
            storeURL: nil,
            quarantinedFileName: quarantinedFileName
        )
    }

    private static func resolvedStoreURL(configuration: Configuration) -> URL? {
        guard let fileName = configuration.storeFileName else { return nil }
        if let directory = configuration.storeDirectoryURL {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appendingPathComponent(fileName)
        }
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let baseURL = appSupport.appendingPathComponent(AppName.displayName, isDirectory: true)
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return baseURL.appendingPathComponent(fileName)
    }

    private static func sqliteDescription(url: URL) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        return description
    }

    private static func inMemoryDescription() -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        return description
    }

    private static func removeAllStores(from container: NSPersistentContainer) {
        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            try? coordinator.remove(store)
        }
    }

    private static func sqliteFilePaths(at storeURL: URL) -> [String] {
        let basePath = storeURL.path
        return [basePath, basePath + "-wal", basePath + "-shm"]
    }

    private static func removeSQLiteStoreFiles(at storeURL: URL) {
        for path in sqliteFilePaths(at: storeURL) {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    /// Moves the store files aside under timestamped names so the original
    /// bytes survive recovery. Returns the quarantined base file name, or nil
    /// when there was no base file to preserve.
    private static func quarantineSQLiteStoreFiles(at storeURL: URL) -> String? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "'quarantined-'yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let fileManager = FileManager.default
        let directory = storeURL.deletingLastPathComponent()
        let baseName = storeURL.lastPathComponent
        var quarantinedBaseName: String?
        for path in sqliteFilePaths(at: storeURL) {
            guard fileManager.fileExists(atPath: path) else { continue }
            let suffix = String(path.dropFirst(storeURL.path.count))
            var candidate = "\(baseName).\(stamp)\(suffix)"
            var counter = 2
            while fileManager.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
                candidate = "\(baseName).\(stamp)-\(counter)\(suffix)"
                counter += 1
            }
            do {
                try fileManager.moveItem(atPath: path, toPath: directory.appendingPathComponent(candidate).path)
                if suffix.isEmpty {
                    quarantinedBaseName = candidate
                }
            } catch {
                // Best effort: a fresh store is still created below, and any
                // file that could not be moved is overwritten by it.
                continue
            }
        }
        return quarantinedBaseName
    }

    // loadPersistentStores invokes its completion synchronously when
    // shouldAddStoreAsynchronously is false (the default), so the semaphore
    // is signalled before wait() is reached. The lock guards the counters
    // shared with the completion handler.
    private static func loadPersistentStoresSynchronously(container: NSPersistentContainer) -> Error? {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var capturedError: Error?
        var remainingCompletions = max(1, container.persistentStoreDescriptions.count)

        container.loadPersistentStores { _, error in
            lock.lock()
            if capturedError == nil, let error {
                capturedError = error
            }
            remainingCompletions -= 1
            let shouldSignal = remainingCompletions <= 0
            lock.unlock()

            if shouldSignal {
                semaphore.signal()
            }
        }

        semaphore.wait()
        return capturedError
    }
}
