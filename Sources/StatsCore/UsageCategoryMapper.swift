import Foundation

/// Usage category taxonomy for the stats usage breakdown.
///
/// Categories resolve from bundle ID at aggregation time (never stored per
/// row), so map improvements and user overrides apply retroactively to all
/// attributed rows. Unknown bundles — including browsers — deliberately fall
/// through to `otherTasks`: classification must never sniff window titles,
/// selections, or transcripts, which are sensitive and must never enter
/// stats.
enum UsageCategory: String, CaseIterable, Codable, Equatable, Sendable {
    case aiTools
    case personalMessages
    case workMessages
    case emails
    case documents
    case otherTasks

    var title: String {
        switch self {
        case .aiTools: "AI Tools"
        case .personalMessages: "Personal Messages"
        case .workMessages: "Work Messages"
        case .emails: "Emails"
        case .documents: "Documents"
        case .otherTasks: "Other Tasks"
        }
    }

    var iconSystemName: String {
        switch self {
        case .aiTools: "cpu"
        case .personalMessages: "message.fill"
        case .workMessages: "briefcase.fill"
        case .emails: "envelope.fill"
        case .documents: "doc.text.fill"
        case .otherTasks: "ellipsis.circle"
        }
    }

    /// Stable display order used as a tie-break when counts are equal.
    var sortOrder: Int {
        switch self {
        case .aiTools: 0
        case .personalMessages: 1
        case .workMessages: 2
        case .emails: 3
        case .documents: 4
        case .otherTasks: 5
        }
    }
}

/// Pure bundle-ID → category mapping with per-app user overrides.
///
/// The default map is best-effort and curated: well-known AI chat/coding
/// tools, mail clients, team chat, personal messengers, and document apps.
/// Anything unmapped (browsers, unknown apps, nil/empty IDs) resolves to
/// `otherTasks`, which users can correct per app via overrides.
enum UsageCategoryMapper {
    static let overridesStorageKey = "stats_usage_category_overrides"

    /// Maximum per-app rows in the snapshot breakdown before the remainder
    /// rolls up into a single "Other" entry.
    static let maxAppRows = 6

    /// Raw value of the retired AI Prompts category, kept so overrides
    /// stored before the merge into AI Tools keep working.
    private static let retiredAIPromptsRawValue = "aiPrompts"

    private static let defaultMap: [String: UsageCategory] = [
        // AI chat / prompt surfaces.
        "com.openai.chat": .aiTools,
        "ai.perplexity.mac": .aiTools,
        "com.anthropic.claudefordesktop": .aiTools,
        // Editors, IDEs, and terminals where AI-assisted work happens.
        "com.microsoft.VSCode": .aiTools,
        "com.microsoft.VSCodeInsiders": .aiTools,
        "com.vscodium": .aiTools,
        "com.todesktop.230313mzl4w4u92": .aiTools,
        "dev.zed.Zed": .aiTools,
        "com.apple.dt.Xcode": .aiTools,
        "com.jetbrains.intellij": .aiTools,
        "com.jetbrains.pycharm": .aiTools,
        "com.jetbrains.webstorm": .aiTools,
        "com.jetbrains.goland": .aiTools,
        "com.jetbrains.rustrover": .aiTools,
        "com.jetbrains.phpstorm": .aiTools,
        "com.jetbrains.rider": .aiTools,
        "com.jetbrains.clion": .aiTools,
        "com.sublimetext.4": .aiTools,
        "com.apple.Terminal": .aiTools,
        "com.googlecode.iterm2": .aiTools,
        "dev.warp.Warp": .aiTools,
        "com.stablyai.orca": .aiTools,
        // Personal messengers.
        "com.apple.iChat": .personalMessages,
        "net.whatsapp.WhatsApp": .personalMessages,
        "ru.keepcoder.Telegram": .personalMessages,
        "com.tdesktop.Telegram": .personalMessages,
        "org.whispersystems.signal-desktop": .personalMessages,
        "com.hnc.Discord": .personalMessages,
        // Team chat / meetings.
        "com.tinyspeck.slackmacgap": .workMessages,
        "com.microsoft.teams": .workMessages,
        "com.microsoft.teams2": .workMessages,
        "us.zoom.xos": .workMessages,
        "com.cisco.WebexTeams": .workMessages,
        "com.mattermost.Desktop": .workMessages,
        // Mail clients.
        "com.apple.mail": .emails,
        "com.microsoft.Outlook": .emails,
        "com.readdle.smartemail-Mac": .emails,
        "com.mimestream.Mimestream": .emails,
        "com.superhuman.mac": .emails,
        // Documents, notes, and office apps.
        "com.microsoft.Word": .documents,
        "com.microsoft.Excel": .documents,
        "com.microsoft.Powerpoint": .documents,
        "com.apple.Pages": .documents,
        "com.apple.Numbers": .documents,
        "com.apple.Keynote": .documents,
        "com.apple.TextEdit": .documents,
        "com.apple.Notes": .documents,
        "md.obsidian": .documents,
        "notion.id": .documents,
        "net.shinyfrog.bear": .documents,
        "com.ulyssesapp.mac": .documents,
        "com.evernote.Evernote": .documents,
    ]

    /// Pure resolution used by aggregation and tests. `overrides` wins over
    /// the default map.
    static func category(
        forBundleID bundleID: String?,
        overrides: [String: UsageCategory]
    ) -> UsageCategory {
        guard let bundleID, !bundleID.isEmpty else { return .otherTasks }
        if let override = overrides[bundleID] {
            return override
        }
        return defaultMap[bundleID] ?? .otherTasks
    }

    /// Production convenience: resolves with the user's persisted overrides.
    static func category(forBundleID bundleID: String?) -> UsageCategory {
        category(forBundleID: bundleID, overrides: storedOverrides())
    }

    static func storedOverrides(defaults: UserDefaults = .standard) -> [String: UsageCategory] {
        guard let raw = defaults.dictionary(forKey: overridesStorageKey) else { return [:] }
        var result: [String: UsageCategory] = [:]
        for (bundleID, value) in raw {
            guard let rawValue = value as? String else { continue }
            if rawValue == retiredAIPromptsRawValue {
                // The AI Prompts category was merged into AI Tools; early
                // overrides pointing at it follow the merge instead of
                // silently dropping back to the default map.
                result[bundleID] = .aiTools
            } else if let category = UsageCategory(rawValue: rawValue) {
                result[bundleID] = category
            }
        }
        return result
    }

    static func setOverride(
        bundleID: String,
        category: UsageCategory,
        defaults: UserDefaults = .standard
    ) {
        var raw = defaults.dictionary(forKey: overridesStorageKey) ?? [:]
        raw[bundleID] = category.rawValue
        defaults.set(raw, forKey: overridesStorageKey)
    }

    static func removeOverride(bundleID: String, defaults: UserDefaults = .standard) {
        guard var raw = defaults.dictionary(forKey: overridesStorageKey) else { return }
        raw.removeValue(forKey: bundleID)
        defaults.set(raw, forKey: overridesStorageKey)
    }
}
