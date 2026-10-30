import SwiftUI

/// GitHub-style contribution grid for words (spec §3–4). Hovering a cell
/// shows a fixed card with the date, total words, and average speed.
/// `nil` cells are blank spacers (week alignment / future days), never data.
struct WordsHeatmapView: View {
    let days: [DailyStat]
    let streakKeys: Set<String>

    @State private var hovered: DailyStat?
    private let cellSize: CGFloat = 12
    private let calendar = StatsCalendar.make()

    private var columns: [[DailyStat?]] {
        StatsHeatmapCore.columns(days: days, calendar: calendar)
    }

    private var maxWords: Int {
        days.map(\.words).max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Words · last 36 weeks")
                .font(.headline)
            ZStack(alignment: .topTrailing) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 6) {
                        weekdayLabels
                        HStack(alignment: .top, spacing: 3) {
                            ForEach(0..<columns.count, id: \.self) { column in
                                VStack(spacing: 3) {
                                    ForEach(0..<7, id: \.self) { row in
                                        cell(columns[column][row])
                                    }
                                }
                            }
                        }
                    }
                }
                if let hovered {
                    hoverCard(hovered)
                }
            }
            legend
        }
    }

    private var weekdayLabels: some View {
        VStack(spacing: 3) {
            ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) { label in
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(height: cellSize, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func cell(_ day: DailyStat?) -> some View {
        if let day {
            let level = StatsHeatmapCore.bucket(words: day.words, maxWords: maxWords)
            RoundedRectangle(cornerRadius: 2)
                .fill(StatsColors.heat[level])
                .frame(width: cellSize, height: cellSize)
                .overlay {
                    if streakKeys.contains(day.dayKey) {
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(StatsColors.streakStroke, lineWidth: 1.5)
                    }
                }
                .onHover { hovering in
                    if hovering {
                        hovered = day
                    } else if hovered == day {
                        hovered = nil
                    }
                }
        } else {
            Color.clear.frame(width: cellSize, height: cellSize)
        }
    }

    private func hoverCard(_ day: DailyStat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(day.date.formatted(date: .long, time: .omitted))
                .font(.caption.bold())
            if day.words == 0 {
                Text("No dictations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("Total words")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(StatsHeatmapCore.wordsLine(day.words))
                }
                .font(.caption)
                HStack {
                    Text("Average speed")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(StatsHeatmapCore.speedLine(words: day.words, avgWPM: day.avgWPM))
                }
                .font(.caption)
            }
        }
        .padding(10)
        .frame(width: 200)
        // ponytail: fixed-position card avoids per-cell popover positioning
        // math; upgrade path is an anchored popover if a window ever gets
        // narrower than card+grid.
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(radius: 4)
        )
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("More")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            ForEach([4, 3, 2, 1], id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(StatsColors.heat[level])
                    .frame(width: cellSize, height: cellSize)
            }
            Text("Less")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            RoundedRectangle(cornerRadius: 2)
                .stroke(StatsColors.streakStroke, lineWidth: 1.5)
                .frame(width: cellSize, height: cellSize)
            Text("Current streak")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
