import SwiftUI
import Charts
import Combine

struct DayCount: Identifiable, Hashable {
    let date: Date
    let count: Int
    var id: Date { date }
}

struct HourCount: Identifiable, Hashable {
    let hour: Int
    let count: Int
    var id: Int { hour }
}

struct Bucket: Identifiable, Hashable {
    let label: String
    let count: Int
    var id: String { label }
}

struct Analytics {
    let total: Int
    let daily: [DayCount]
    let hours: [HourCount]
    let weekdays: [Bucket]
    let artists: [Bucket]
    let streak: Int
    let busiest: DayCount?
    let peakHour: Int?

    init(tracks: [LFItem], days: Int) {
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        guard let cutoffDate = cal.date(byAdding: .day, value: -(days - 1), to: today) else {
            total = 0; daily = []; hours = []; weekdays = []; artists = []; streak = 0; busiest = nil; peakHour = nil
            return
        }

        // Filter tracks strictly within current window
        let playedTracks = tracks.filter { track in
            guard let d = track.playedAt else { return false }
            return d >= cutoffDate && d <= now
        }

        var byDay: [Date: Int] = [:]
        var h = [Int](repeating: 0, count: 24)
        var w = [Int](repeating: 0, count: 7)
        var artistCounts: [String: Int] = [:]

        for track in playedTracks {
            if let d = track.playedAt {
                let dayStart = cal.startOfDay(for: d)
                byDay[dayStart, default: 0] += 1
                h[cal.component(.hour, from: d)] += 1
                let weekdayIndex = cal.component(.weekday, from: d) - 1
                if weekdayIndex >= 0 && weekdayIndex < 7 {
                    w[weekdayIndex] += 1
                }
                artistCounts[track.artistName, default: 0] += 1
            }
        }

        let dailyList = (0..<days).reversed()
            .compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
            .map { DayCount(date: $0, count: byDay[$0] ?? 0) }

        let hourList = h.enumerated().map { HourCount(hour: $0.offset, count: $0.element) }
        let names = cal.shortWeekdaySymbols

        // Streak calculation
        var streakCount = 0
        var cursor = today
        if (byDay[cursor] ?? 0) == 0 {
            if let yesterday = cal.date(byAdding: .day, value: -1, to: today) {
                cursor = yesterday
            }
        }
        while (byDay[cursor] ?? 0) > 0 {
            streakCount += 1
            if let prev = cal.date(byAdding: .day, value: -1, to: cursor) {
                cursor = prev
            } else {
                break
            }
        }

        total = playedTracks.count
        daily = dailyList
        hours = hourList
        weekdays = w.enumerated().map { Bucket(label: names[$0.offset], count: $0.element) }
        artists = artistCounts.sorted { $0.value > $1.value }.prefix(8).map { Bucket(label: $0.key, count: $0.value) }
        streak = streakCount
        busiest = dailyList.max { $0.count < $1.count }.flatMap { $0.count > 0 ? $0 : nil }
        peakHour = hourList.max { $0.count < $1.count }.flatMap { $0.count > 0 ? $0.hour : nil }
    }
}

@MainActor
final class HistoryModel: ObservableObject {
    @Published var tracks: [LFItem] = []
    @Published var loading = false
    @Published var error: String?

    func load(user: String, days: Int) async {
        guard !user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        loading = true
        error = nil
        let from = Int(Date().addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970)
        var all: [LFItem] = []
        let maxPages = days > 30 ? 10 : 5

        do {
            for page in 1...maxPages {
                let batch = try await LastFM.shared.history(user, from: from, page: page)
                all += batch.filter { !$0.isNowPlaying }
                if batch.count < 199 { break }
            }
            tracks = all
        } catch {
            if !(error is CancellationError) { self.error = error.localizedDescription }
        }
        loading = false
    }
}

private func hourLabel(_ h: Int) -> String {
    "\(h % 12 == 0 ? 12 : h % 12) \(h < 12 ? "AM" : "PM")"
}

struct ChartCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title, subtitle)
            content
        }
        .padding(18)
        .glass(26)
    }
}

struct HistoryView: View {
    @EnvironmentObject var app: AppModel
    @StateObject private var model = HistoryModel()
    @State private var days = 30
    @State private var mode = 0
    @State private var query = ""
    @State private var selectedDate: Date?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Picker("View", selection: $mode) {
                        Text("Charts").tag(0)
                        Text("Timeline").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) { _ in Haptics.selection() }

                    Picker("Range", selection: $days) {
                        Text("7D").tag(7)
                        Text("30D").tag(30)
                        Text("90D").tag(90)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: days) { _ in Haptics.selection() }

                    if let e = model.error { ErrorCard(text: e) }

                    if model.loading && model.tracks.isEmpty {
                        ProgressView().padding(.top, 40)
                    } else if model.tracks.isEmpty && model.error == nil {
                        Text("No scrobbles in this range.").foregroundStyle(.secondary).padding(.top, 40)
                    } else if mode == 0 {
                        charts(Analytics(tracks: model.tracks, days: days))
                    } else {
                        timeline
                    }

                    if model.tracks.count >= 1000 {
                        Text("Showing your latest scrobbles in this range.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(Backdrop())
            .navigationTitle("History")
            .refreshable { await model.load(user: app.username, days: days) }
            .task(id: "\(app.username)|\(days)") { await model.load(user: app.username, days: days) }
            .tonalDestinations()
        }
    }

    @ViewBuilder
    private func charts(_ a: Analytics) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            StatTile(icon: "music.note", label: "Scrobbles", value: a.total.full)
            StatTile(icon: "calendar", label: "Daily average", value: String(format: "%.1f", Double(a.total) / Double(days)))
            StatTile(icon: "flame.fill", label: "Current streak", value: "\(a.streak) day\(a.streak == 1 ? "" : "s")")
            StatTile(icon: "clock.fill", label: "Peak hour", value: a.peakHour.map(hourLabel) ?? "—")
        }

        ChartCard(
            title: "Daily activity",
            subtitle: a.busiest.map { "Busiest: \($0.count) on \($0.date.formatted(.dateTime.month(.abbreviated).day()))" }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if let selected = selectedDate,
                   let match = a.daily.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selected) }) {
                    HStack {
                        Text(match.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(match.count) scrobbles")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.gradient.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Chart(a.daily) { d in
                    AreaMark(x: .value("Day", d.date, unit: .day), y: .value("Scrobbles", d.count))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Theme.accent.opacity(0.4), Theme.accent2.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    LineMark(x: .value("Day", d.date, unit: .day), y: .value("Scrobbles", d.count))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Theme.gradient)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))

                    if let selected = selectedDate, Calendar.current.isDate(d.date, inSameDayAs: selected) {
                        RuleMark(x: .value("Day", selected, unit: .day))
                            .foregroundStyle(Theme.accent.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                        PointMark(x: .value("Day", d.date, unit: .day), y: .value("Scrobbles", d.count))
                            .symbolSize(80)
                            .foregroundStyle(Theme.accent)
                    }
                }
                .chartXSelection(value: $selectedDate)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 200)
            }
        }

        ChartCard(title: "Time of day", subtitle: "When you listen most") {
            Chart(a.hours) { h in
                BarMark(x: .value("Hour", h.hour), y: .value("Scrobbles", h.count))
                    .foregroundStyle(Theme.gradient)
                    .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { v in
                    AxisValueLabel { if let i = v.as(Int.self) { Text(hourLabel(i)) } }
                }
            }
            .frame(height: 160)
        }

        ChartCard(title: "Day of week") {
            Chart(a.weekdays) { b in
                BarMark(x: .value("Day", b.label), y: .value("Scrobbles", b.count))
                    .foregroundStyle(Theme.gradient)
                    .cornerRadius(6)
            }
            .frame(height: 160)
        }

        if !a.artists.isEmpty {
            ChartCard(title: "Artist share", subtitle: "Most played in this range") {
                Chart(a.artists) { b in
                    BarMark(x: .value("Scrobbles", b.count), y: .value("Artist", b.label))
                        .foregroundStyle(Theme.gradient)
                        .cornerRadius(6)
                        .annotation(position: .trailing) {
                            Text("\(b.count)").font(.caption2.weight(.bold)).foregroundStyle(Theme.accent)
                        }
                }
                .frame(height: CGFloat(a.artists.count) * 34 + 20)
            }
        }
    }

    @ViewBuilder
    private var timeline: some View {
        FormField(icon: "magnifyingglass", placeholder: "Filter by track or artist", text: $query)
            .glass(16)
        let filtered = model.tracks.filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.artistName.localizedCaseInsensitiveContains(query)
        }
        let groups = Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.playedAt ?? .distantPast) }
        LazyVStack(spacing: 18) {
            ForEach(groups.keys.sorted(by: >), id: \.self) { day in
                VStack(spacing: 8) {
                    HStack {
                        Text(dayTitle(day)).font(.system(.headline, design: .rounded))
                        Spacer()
                        Text("\(groups[day]?.count ?? 0)").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                    }
                    VStack(spacing: 0) {
                        ForEach(groups[day] ?? []) { t in
                            NavigationLink(value: ArtistRoute(name: t.artistName)) { HistoryRow(item: t) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                    .glass(22)
                }
            }
        }
    }

    private func dayTitle(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

struct HistoryRow: View {
    let item: LFItem

    var body: some View {
        HStack(spacing: 12) {
            Artwork(url: item.artworkURL)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(item.artistName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let d = item.playedAt {
                Text(d.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

struct SectionTitle: View {
    let title: String
    let subtitle: String?

    init(_ title: String, _ subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline.weight(.semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ErrorCard: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct StatTile: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Theme.gradient)
            Text(value)
                .font(.title3.weight(.bold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glass(16)
    }
}

struct Artwork: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [Theme.accent.opacity(0.2), Theme.accent2.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }
}

extension View {
    func glass(_ cornerRadius: CGFloat) -> some View {
        let style = AppModel.sharedCurrent?.glassStyle ?? .vibrant
        let radius = AppModel.sharedCurrent?.cornerRadiusStyle.value ?? cornerRadius
        let fillStyle: AnyShapeStyle
        switch style {
        case .vibrant:
            fillStyle = AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.85))
        case .clean:
            fillStyle = AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground))
        case .minimal:
            fillStyle = AnyShapeStyle(Color.primary.opacity(0.04))
        }

        return background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fillStyle)
        )
        .shadow(color: style == .minimal ? Color.clear : Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    func tonalDestinations() -> some View {
        navigationDestination(for: ArtistRoute.self) { route in
            ArtistView(name: route.name)
        }
        .navigationDestination(for: AlbumRoute.self) { route in
            AlbumView(artist: route.artist, name: route.name)
        }
    }
}
