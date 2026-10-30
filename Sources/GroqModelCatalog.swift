import Foundation

/// Live-model catalog for the configured OpenAI-compatible provider.
///
/// Liveness comes from `GET {baseURL}/models`; capability (vision vs text
/// vs audio) stays hardcoded in `ModelConfiguration` because the `/models`
/// payload carries no capability flags. All selection logic here is pure so
/// tests pin it without network access.
enum GroqModelCatalog {
    static let groqHost = "api.groq.com"

    /// Parses an OpenAI-compatible `GET /models` body into sorted unique
    /// model IDs. Returns `[]` for any malformed payload.
    static func parseModelsResponse(_ data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["data"] as? [[String: Any]] else {
            return []
        }
        let ids = entries.compactMap { entry -> String? in
            guard let id = entry["id"] as? String else { return nil }
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return Array(Set(ids)).sorted()
    }

    /// Dropdown options for one task.
    /// - No live data (offline / never fetched): hardcoded `known`.
    /// - Non-Groq host: the full live list (the Groq capability map does
    ///   not apply to other providers).
    /// - Groq: `known ∩ live` in `known` order (strict per-task filtering);
    ///   unknown live IDs stay reachable via "Custom...". Falls back to
    ///   `known` when the intersection is empty so the picker never empties.
    static func dropdownModels(known: [String], live: [String]?, isGroqHost: Bool) -> [String] {
        guard let live, !live.isEmpty else { return known }
        if !isGroqHost { return live }
        let liveSet = Set(live.map { $0.lowercased() })
        let matches = known.filter { liveSet.contains($0.lowercased()) }
        return matches.isEmpty ? known : matches
    }

    /// True when the stored selection is absent from the live list. False
    /// without live data (never warn from a failed fetch).
    static func isDeprecatedSelection(_ stored: String, live: [String]?) -> Bool {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let live, !live.isEmpty else { return false }
        return !live.map { $0.lowercased() }.contains(trimmed.lowercased())
    }

    /// One-shot migration for dead stored IDs. `migrations` maps a dead ID
    /// to its replacement; anything unmapped passes through trimmed.
    static func migratedStoredModel(stored: String?, migrations: [String: String], default defaultModel: String) -> String {
        guard let stored else { return defaultModel }
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultModel }
        let lowered = trimmed.lowercased()
        for (dead, replacement) in migrations where lowered == dead.lowercased() {
            return replacement
        }
        return trimmed
    }
}

/// Fetches `GET {baseURL}/models` over the shared ephemeral transport.
/// Returns nil on any failure (network, auth, non-200, unparseable, empty)
/// so callers keep their cached/hardcoded lists.
final class GroqModelCatalogFetcher {
    func fetchLiveModels(apiKey: String, baseURL: String) async -> [String]? {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        guard !trimmedKey.isEmpty, let url = URL(string: trimmedBase + "/models") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await LLMAPITransport.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let ids = GroqModelCatalog.parseModelsResponse(data)
            return ids.isEmpty ? nil : ids
        } catch {
            return nil
        }
    }
}
