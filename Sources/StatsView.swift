import Charts
import SwiftUI

// MARK: - Stats

struct StatsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingClearConfirm = false
    @State private var breakdownMetric: UsageBreakdownMetric = .dictations
    @State private var showingCategoryManager = false

    var body: some View {
        VStack(spacing: 0) {
            header

            if let notice = appState.statsNotice {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(notice.message)
                        .font(.caption)
                    Spacer()
                    if notice.isDismissable {
                        Button("Dismiss") {
                            appState.dismissStatsNotice()
                        }
                        .font(.caption)
                    }
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            }

            Divider()

            if let snapshot = appState.statsSnapshot, snapshot.totalAttempts > 0 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        cards(snapshot)
                        WordsHeatmapView(days: snapshot.heatmapDays, streakKeys: snapshot.streakDayKeys)
                        wpmChart(snapshot)
                        usageBreakdownRow(snapshot)
                        activityRow(snapshot)
                        footnote
                    }
                    .padding(20)
                }
            } else {
                VStack {
                    Spacer()
                    Text("No dictations yet. Use dictation to populate stats.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .confirmationDialog(
            "Clear all stats?",
            isPresented: $showingClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear Stats", role: .destructive) {
                appState.clearStats()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes words, streaks, and trends forever. Your run transcripts are kept.")
        }
        .onAppear {
            appState.requestStatsSnapshotRefresh()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Stats")
                    .font(.title.bold())
                Text("Local only · Numbers, never transcripts.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Typing speed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Typing speed", selection: $appState.typingBaselineWPM) {
                        ForEach(AppState.typingBaselineWPMOptions, id: \.self) { option in
                            Text("\(option) WPM").tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                .help("Your typing speed, used to estimate time saved")
                Spacer()
                Button {
                    StatsExportController.exportWithSavePanel(
                        csv: appState.csvForExport(),
                        fileName: appState.statsExportFileName()
                    )
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
                .disabled((appState.statsSnapshot?.totalAttempts ?? 0) == 0)
                Button {
                    showingClearConfirm = true
                } label: {
                    Label("Clear Stats", systemImage: "trash")
                }
                .disabled((appState.statsSnapshot?.totalAttempts ?? 0) == 0)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private func cards(_ snapshot: StatsSnapshot) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 170), spacing: 12)],
            spacing: 12
        ) {
            StatCard(
                title: "Current streak",
                value: dayLabel(snapshot.currentStreakDays),
                detail: "Longest \(dayLabel(snapshot.longestStreakDays))"
            )
            StatCard(
                title: "Words dictated",
                value: snapshot.totalWords.formatted(),
                detail: "\(snapshot.today.words.formatted()) today"
            )
            StatCard(
                title: "Dictations",
                value: snapshot.totalDictations.formatted(),
                detail: "\(snapshot.today.dictations.formatted()) today"
            )
            StatCard(
                title: "Speaking time",
                value: StatsCalculator.formatTotalTime(snapshot.totalSpeakingSec),
                detail: "\(StatsCalculator.formatTotalTime(snapshot.today.speakingSec)) today"
            )
            StatCard(
                title: "Time saved",
                value: StatsCalculator.formatTotalTime(snapshot.totalTimeSavedSec),
                detail: "vs \(snapshot.baselineWPM) WPM typing · \(StatsCalculator.formatTotalTime(snapshot.today.timeSavedSec)) today"
            )
            StatCard(
                title: "Average speed",
                value: StatsCalculator.formatWPM(snapshot.overallAvgWPM),
                detail: "\(StatsCalculator.formatWPM(snapshot.today.avgWPM)) today"
            )
            if let best = snapshot.bestDay {
                StatCard(
                    title: "Best day",
                    value: "\(best.words.formatted()) words",
                    detail: best.date.formatted(date: .abbreviated, time: .omitted)
                )
            } else {
                StatCard(title: "Best day", value: "—", detail: "No qualifying days yet")
            }
            StatCard(
                title: "Pace",
                value: StatsCalculator.format1(snapshot.avgDictationsPerDay),
                detail: weekOverWeekText(snapshot.weekOverWeekPct)
            )
        }
    }

    private func wpmChart(_ snapshot: StatsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily speed · last 14 days")
                .font(.headline)
            let segments = wpmSegments(snapshot.last14)
            if segments.isEmpty {
                Text("No speed data yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(segments) { segment in
                        ForEach(segment.days) { day in
                            LineMark(
                                x: .value("Day", day.date, unit: .day),
                                y: .value("WPM", day.avgWPM ?? 0),
                                series: .value("Segment", segment.index)
                            )
                            .foregroundStyle(StatsColors.speedLine)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            PointMark(
                                x: .value("Day", day.date, unit: .day),
                                y: .value("WPM", day.avgWPM ?? 0)
                            )
                            .foregroundStyle(StatsColors.speedLine)
                            .symbolSize(30)
                        }
                    }
                    if let average = snapshot.overallAvgWPM {
                        RuleMark(y: .value("Average", average))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    }
                }
                .frame(height: 160)
            }
        }
    }

    /// Groups consecutive days with speed data so the line breaks across
    /// missing days instead of bridging the gap.
    private func wpmSegments(_ days: [DailyStat]) -> [WPMSegment] {
        var segments: [WPMSegment] = []
        var current: [DailyStat] = []
        for day in days {
            guard day.avgWPM != nil else {
                if !current.isEmpty {
                    segments.append(WPMSegment(index: segments.count, days: current))
                    current = []
                }
                continue
            }
            current.append(day)
        }
        if !current.isEmpty {
            segments.append(WPMSegment(index: segments.count, days: current))
        }
        return segments
    }

    private func usageBreakdownRow(_ snapshot: StatsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text("Usage breakdown")
                    .font(.headline)
                Spacer()
                Text("TOTAL APPS USED | \(snapshot.totalAppsUsed)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $breakdownMetric) {
                    ForEach(UsageBreakdownMetric.allCases, id: \.self) { metric in
                        Text(metric.title).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Switch the breakdown between dictation counts and word counts")
                .frame(width: 190)
                Button("Manage") {
                    showingCategoryManager = true
                }
                .help("View and change which category each app belongs to")
            }
            .sheet(isPresented: $showingCategoryManager) {
                UsageCategoryManagerView()
            }
            if snapshot.attributedDictations == 0 {
                Text("App breakdowns appear for new dictations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
            } else {
                HStack(alignment: .top, spacing: 12) {
                    breakdownPanel(
                        title: "BY CATEGORY",
                        entries: displayedBreakdownEntries(snapshot.categoryBreakdown),
                        maxValue: breakdownMaxValue(snapshot.categoryBreakdown)
                    )
                    breakdownPanel(
                        title: "BY APP",
                        entries: displayedAppEntries(snapshot.appBreakdown),
                        maxValue: breakdownMaxValue(snapshot.appBreakdown),
                        showsOverrideMenu: true
                    )
                }
            }
            if snapshot.unattributedDictations > 0 {
                Text(unattributedFootnote(snapshot.unattributedDictations))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func breakdownPanel(
        title: String,
        entries: [UsageBreakdownEntry],
        maxValue: Int,
        showsOverrideMenu: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(entries, id: \.key) { entry in
                breakdownRow(entry, maxValue: maxValue, showsOverrideMenu: showsOverrideMenu)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    @ViewBuilder
    private func breakdownRow(
        _ entry: UsageBreakdownEntry,
        maxValue: Int,
        showsOverrideMenu: Bool
    ) -> some View {
        let row = UsageBreakdownBarRow(
            entry: entry,
            value: breakdownValue(entry),
            share: breakdownShare(entry),
            maxValue: maxValue,
            unitLabel: breakdownMetric == .dictations ? "DICTATIONS" : "WORDS"
        )
        if showsOverrideMenu, let bundleID = entry.bundleID {
            row.contextMenu {
                Menu("Move to category") {
                    ForEach(UsageCategory.allCases, id: \.self) { category in
                        Button(category.title) {
                            UsageCategoryMapper.setOverride(bundleID: bundleID, category: category)
                            appState.requestStatsSnapshotRefresh()
                        }
                    }
                }
            }
        } else {
            row
        }
    }

    private func breakdownValue(_ entry: UsageBreakdownEntry) -> Int {
        breakdownMetric == .dictations ? entry.dictations : entry.words
    }

    private func breakdownShare(_ entry: UsageBreakdownEntry) -> Double {
        breakdownMetric == .dictations ? entry.shareOfDictations : entry.shareOfWords
    }

    private func breakdownMaxValue(_ entries: [UsageBreakdownEntry]) -> Int {
        entries.map(breakdownValue).max() ?? 0
    }

    /// Snapshot rows arrive sorted by dictations; re-sort under the Words
    /// toggle so bars rank by the visible metric.
    private func displayedBreakdownEntries(_ entries: [UsageBreakdownEntry]) -> [UsageBreakdownEntry] {
        guard breakdownMetric == .words else { return entries }
        return entries.sorted {
            if $0.words != $1.words { return $0.words > $1.words }
            if $0.dictations != $1.dictations { return $0.dictations > $1.dictations }
            return $0.displayName < $1.displayName
        }
    }

    /// Same as above, but the "Other" rollup stays pinned last.
    private func displayedAppEntries(_ entries: [UsageBreakdownEntry]) -> [UsageBreakdownEntry] {
        let rollup = entries.filter { $0.key == "other" }
        let rest = entries.filter { $0.key != "other" }
        return displayedBreakdownEntries(rest) + rollup
    }

    private func unattributedFootnote(_ count: Int) -> String {
        count == 1
            ? "1 earlier run predates app tracking."
            : "\(count.formatted()) earlier runs predate app tracking."
    }

    private func activityRow(_ snapshot: StatsSnapshot) -> some View {
        HStack(spacing: 12) {
            StatCard(
                title: "Most active hour",
                value: snapshot.mostActiveHour.map(hourLabel) ?? "—",
                detail: "Local time",
                icon: "clock"
            )
            StatCard(
                title: "Most active day",
                value: snapshot.mostActiveWeekday.map(weekdayLabel) ?? "—",
                detail: "By dictation count",
                icon: "calendar"
            )
        }
    }

    private var footnote: some View {
        Text("Speed and time saved measure free-form dictation. Edit Mode and voice-macro runs count toward dictations and streaks. Short runs under 2s or 3 words are excluded from speed averages. Runs recorded before stats show — for speed.")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }

    private func dayLabel(_ days: Int) -> String {
        days == 1 ? "1 day" : "\(days) days"
    }

    private func weekOverWeekText(_ pct: Double?) -> String {
        guard let pct else { return "Not enough history yet" }
        let rounded = Int(pct.rounded())
        let sign = rounded >= 0 ? "+" : ""
        return "\(sign)\(rounded)% vs previous 7 days"
    }

    private func hourLabel(_ hour: Int) -> String {
        let normalized = ((hour % 24) + 24) % 24
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("j")
        var components = DateComponents()
        components.hour = normalized
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date)
    }

    private func weekdayLabel(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        guard weekday >= 1, weekday <= symbols.count else { return "—" }
        return symbols[weekday - 1]
    }
}

private struct WPMSegment: Identifiable {
    let index: Int
    var id: Int { index }
    let days: [DailyStat]
}

private enum UsageBreakdownMetric: String, CaseIterable {
    case dictations
    case words

    var title: String {
        switch self {
        case .dictations: "Dictations"
        case .words: "Words"
        }
    }
}

/// Category manager sheet: every attributed app with its current category
/// and a per-row picker to remap it. Overrides apply retroactively and a
/// reset returns the app to the built-in default map.
private struct UsageCategoryManagerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("App categories")
                        .font(.title3.bold())
                    Text("Decide which category each app counts toward.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            Divider()
            if let snapshot = appState.statsSnapshot, !snapshot.allAppBreakdown.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(snapshot.allAppBreakdown, id: \.key) { entry in
                            appRow(entry)
                            Divider()
                        }
                    }
                }
            } else {
                Text("No attributed dictations yet. Dictate in an app and it will appear here for classification.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text("New and unmapped apps land in Other Tasks. Your choices apply retroactively to all past dictations.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 320)
    }

    private func appRow(_ entry: UsageBreakdownEntry) -> some View {
        let overrides = UsageCategoryMapper.storedOverrides()
        let current = UsageCategoryMapper.category(forBundleID: entry.bundleID, overrides: overrides)
        let isCustom = entry.bundleID.flatMap { overrides[$0] } != nil
        return HStack(spacing: 10) {
            Image(systemName: entry.icon)
                .foregroundStyle(StatsColors.speedLine)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(entry.displayName)
                        .font(.callout)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if isCustom {
                        Text("CUSTOM")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(nsColor: .quaternaryLabelColor))
                            )
                    }
                }
                Text("\(entry.dictations.formatted()) dictations · \(entry.words.formatted()) words")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if let bundleID = entry.bundleID {
                Menu {
                    ForEach(UsageCategory.allCases, id: \.self) { category in
                        Button {
                            UsageCategoryMapper.setOverride(bundleID: bundleID, category: category)
                            appState.requestStatsSnapshotRefresh()
                        } label: {
                            if category == current {
                                Label(category.title, systemImage: "checkmark")
                            } else {
                                Text(category.title)
                            }
                        }
                    }
                    if isCustom {
                        Divider()
                        Button("Reset to default") {
                            UsageCategoryMapper.removeOverride(bundleID: bundleID)
                            appState.requestStatsSnapshotRefresh()
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(current.title)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                }
                .fixedSize()
                .help("Change which category \(entry.displayName) counts toward")
            } else {
                Text(current.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .help("Runs without a bundle ID cannot be remapped")
            }
        }
        .padding(.vertical, 6)
    }
}

private struct UsageBreakdownBarRow: View {    let entry: UsageBreakdownEntry
    let value: Int
    /// 0…1 share of the attributed total for the visible metric.
    let share: Double
    let maxValue: Int
    /// Trailing unit caption, e.g. "DICTATIONS" or "WORDS".
    let unitLabel: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.icon)
                .foregroundStyle(StatsColors.speedLine)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(nsColor: .quaternaryLabelColor))
                        if fraction > 0 {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(StatsColors.speedLine)
                                .frame(width: max(30, geometry.size.width * fraction))
                        }
                        Text("\(Int((share * 100).rounded()))%")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.leading, 6)
                            .lineLimit(1)
                    }
                }
                .frame(height: 18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(value.formatted()) \(unitLabel)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var fraction: Double {
        maxValue > 0 ? Double(value) / Double(maxValue) : 0
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let detail: String
    var icon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .foregroundStyle(StatsColors.speedLine)
                }
                Text(title)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            Text(value)
                .font(.title.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}
