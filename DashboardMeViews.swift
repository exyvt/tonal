import Foundation
import SwiftUI
import Combine
import Charts

// MARK: - Dashboard Data Models

struct DashboardModel {
    struct StatsPeriod {
        var scrobbles: Int
        var dailyAverage: Double
        var longestStreak: Int
        var busiestDayName: String?
        var busiestHour: Int?
        var totalHours: Int
    }

    struct TopItem: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let subtitle: String?
        let playcount: Int
        let imageURL: URL?
        let globalListeners: Int?

        init(name: String, subtitle: String? = nil, playcount: Int, imageURL: URL? = nil, globalListeners: Int? = nil) {
            self.name = name
            self.subtitle = subtitle
            self.playcount = playcount
            self.imageURL = imageURL
            self.globalListeners = globalListeners
        }
    }

    struct GenreStats: Identifiable, Hashable {
        let id = UUID()
        let genre: String
        let count: Int
        let percentage: Double
    }

    struct Personality: Hashable {
        let title: String
        let icon: String
        let description: String
    }

    struct CoolFact: Identifiable, Hashable {
        let id = UUID()
        let icon: String
        let title: String
        let subtitle: String
        let category: String
    }

    struct Milestone: Hashable {
        let target: Int
        let current: Int
        var percentage: Double { min(max((Double(current) / Double(target)) * 100.0, 0), 100) }
        var remaining: Int { max(target - current, 0) }
    }

    struct TimeOfDaySpectrum: Hashable {
        var morning: Double = 0   // 6 AM - 12 PM
        var afternoon: Double = 0 // 12 PM - 6 PM
        var evening: Double = 0   // 6 PM - 12 AM
        var night: Double = 0     // 12 AM - 6 AM
    }

    struct DayTypeSplit: Hashable {
        var weekdayPct: Double = 0
        var weekendPct: Double = 0
    }

    var username: String = ""
    var country: String?
    var memberSince: Date?
    var totalScrobbles: Int = 0
    var avatarURL: URL?

    var lifetimeStats = StatsPeriod(scrobbles: 0, dailyAverage: 0, longestStreak: 0, busiestDayName: nil, busiestHour: nil, totalHours: 0)
    var last30DaysStats = StatsPeriod(scrobbles: 0, dailyAverage: 0, longestStreak: 0, busiestDayName: nil, busiestHour: nil, totalHours: 0)

    var topArtistsLifetime: [TopItem] = []
    var topAlbumsLifetime: [TopItem] = []
    var topTracksLifetime: [TopItem] = []

    var topArtists30Days: [TopItem] = []
    var topAlbums30Days: [TopItem] = []
    var topTracks30Days: [TopItem] = []

    var genreStats: [GenreStats] = []
    var personality: Personality?
    var coolFacts: [CoolFact] = []
    var milestone: Milestone?
    var timeOfDaySpectrum = TimeOfDaySpectrum()
    var dayTypeSplit = DayTypeSplit()
}

// MARK: - Dashboard ViewModel

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var dashboard = DashboardModel()
    @Published var loading = false
    @Published var error: String?

    func loadAll(username: String, bypassCache: Bool = false) async {
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        loading = true
        error = nil

        do {
            async let userInfoTask = LastFM.shared.userInfo(cleanUsername, bypassCache: bypassCache)
            async let topArtistsLifetimeTask = LastFM.shared.topArtists(cleanUsername, period: "overall", limit: 50, bypassCache: bypassCache)
            async let topAlbumsLifetimeTask = LastFM.shared.topAlbums(cleanUsername, period: "overall", limit: 50, bypassCache: bypassCache)
            async let topTracksLifetimeTask = LastFM.shared.topTracks(cleanUsername, period: "overall", limit: 50, bypassCache: bypassCache)
            async let topArtists30DaysTask = LastFM.shared.topArtists(cleanUsername, period: "1month", limit: 50, bypassCache: bypassCache)
            async let topAlbums30DaysTask = LastFM.shared.topAlbums(cleanUsername, period: "1month", limit: 50, bypassCache: bypassCache)
            async let topTracks30DaysTask = LastFM.shared.topTracks(cleanUsername, period: "1month", limit: 50, bypassCache: bypassCache)
            async let userTagsTask = (try? await LastFM.shared.userTopTags(cleanUsername, limit: 30, bypassCache: bypassCache)) ?? []
            async let recentTracksTask = (try? await LastFM.shared.recent(cleanUsername, limit: 200, bypassCache: bypassCache)) ?? []

            let userInfo = try await userInfoTask
            let topArtistsLifetimeRaw = try await topArtistsLifetimeTask
            let topAlbumsLifetimeRaw = try await topAlbumsLifetimeTask
            let topTracksLifetimeRaw = try await topTracksLifetimeTask
            let topArtists30DaysRaw = try await topArtists30DaysTask
            let topAlbums30DaysRaw = try await topAlbums30DaysTask
            let topTracks30DaysRaw = try await topTracks30DaysTask
            let userTags = await userTagsTask
            let recentTracks = await recentTracksTask

            // Parallel artist mapping
            let topArtistsLifetime = await mapArtists(topArtistsLifetimeRaw)
            let topAlbumsLifetime = topAlbumsLifetimeRaw.map {
                DashboardModel.TopItem(name: $0.name, subtitle: $0.artistName, playcount: $0.plays, imageURL: $0.artworkURL)
            }
            let topTracksLifetime = topTracksLifetimeRaw.map {
                DashboardModel.TopItem(name: $0.name, subtitle: $0.artistName, playcount: $0.plays, imageURL: $0.artworkURL)
            }

            let topArtists30Days = await mapArtists(topArtists30DaysRaw)
            let topAlbums30Days = topAlbums30DaysRaw.map {
                DashboardModel.TopItem(name: $0.name, subtitle: $0.artistName, playcount: $0.plays, imageURL: $0.artworkURL)
            }
            let topTracks30Days = topTracks30DaysRaw.map {
                DashboardModel.TopItem(name: $0.name, subtitle: $0.artistName, playcount: $0.plays, imageURL: $0.artworkURL)
            }

            // Calculate scrobble & time stats
            let totalScrobbles = userInfo.playcount.int
            let registeredDate = userInfo.since
            let daysSinceRegistered = max(1, Calendar.current.dateComponents([.day], from: registeredDate, to: Date()).day ?? 1)
            let lifetimeDailyAverage = Double(totalScrobbles) / Double(daysSinceRegistered)
            let lifetimeHours = (totalScrobbles * 210) / 3600

            // 30 Days stats calculation
            let scrobbles30Days = topTracks30Days.reduce(0) { $0 + $1.playcount }
            let scrobbles30DaysAdjusted = max(scrobbles30Days, topArtists30Days.reduce(0) { $0 + $1.playcount })
            let dailyAverage30Days = Double(scrobbles30DaysAdjusted) / 30.0
            let hours30Days = (scrobbles30DaysAdjusted * 210) / 3600

            // Activity timings from recent tracks
            let (longestStreak, busiestHour, busiestDayName, timeSpectrum, daySplit) = analyzeRecentTracksDetailed(recentTracks)

            let lifetimeStats = DashboardModel.StatsPeriod(
                scrobbles: totalScrobbles,
                dailyAverage: lifetimeDailyAverage,
                longestStreak: longestStreak,
                busiestDayName: busiestDayName,
                busiestHour: busiestHour,
                totalHours: lifetimeHours
            )

            let last30DaysStats = DashboardModel.StatsPeriod(
                scrobbles: scrobbles30DaysAdjusted,
                dailyAverage: dailyAverage30Days,
                longestStreak: min(longestStreak, 30),
                busiestDayName: busiestDayName,
                busiestHour: busiestHour,
                totalHours: hours30Days
            )

            // Milestone calculation
            let nextMilestoneTarget = computeNextMilestone(totalScrobbles)
            let milestone = DashboardModel.Milestone(target: nextMilestoneTarget, current: totalScrobbles)

            // Compute genres & personality
            let genres = await computeGenres(userTags: userTags, topArtists: topArtistsLifetimeRaw)
            let personality = computePersonality(busiestHour: busiestHour, topArtists: topArtistsLifetime, topTracks: topTracks30Days)

            // Compute Expanded Facts & Trivia
            let coolFacts = computeExpandedFacts(
                userInfo: userInfo,
                topArtistsLifetime: topArtistsLifetime,
                topAlbumsLifetime: topAlbumsLifetime,
                topTracksLifetime: topTracksLifetime,
                topArtists30Days: topArtists30Days,
                topAlbums30Days: topAlbums30Days,
                topTracks30Days: topTracks30Days,
                lifetimeStats: lifetimeStats,
                last30DaysStats: last30DaysStats,
                daysSinceRegistered: daysSinceRegistered,
                milestone: milestone,
                daySplit: daySplit
            )

            dashboard = DashboardModel(
                username: cleanUsername,
                country: userInfo.country,
                memberSince: registeredDate,
                totalScrobbles: totalScrobbles,
                avatarURL: userInfo.avatarURL,
                lifetimeStats: lifetimeStats,
                last30DaysStats: last30DaysStats,
                topArtistsLifetime: topArtistsLifetime,
                topAlbumsLifetime: topAlbumsLifetime,
                topTracksLifetime: topTracksLifetime,
                topArtists30Days: topArtists30Days,
                topAlbums30Days: topAlbums30Days,
                topTracks30Days: topTracks30Days,
                genreStats: genres,
                personality: personality,
                coolFacts: coolFacts,
                milestone: milestone,
                timeOfDaySpectrum: timeSpectrum,
                dayTypeSplit: daySplit
            )

        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func mapArtists(_ raw: [LFItem]) async -> [DashboardModel.TopItem] {
        await withTaskGroup(of: (Int, DashboardModel.TopItem).self) { group in
            for (index, item) in raw.enumerated() {
                group.addTask {
                    var url = item.artworkURL
                    if url == nil {
                        url = await LastFMArtworkResolver.shared.artistImage(item.name)
                    }
                    return (index, DashboardModel.TopItem(name: item.name, playcount: item.plays, imageURL: url, globalListeners: item.listenerCount))
                }
            }

            var results = [(Int, DashboardModel.TopItem)]()
            for await item in group {
                results.append(item)
            }
            return results.sorted(by: { $0.0 < $1.0 }).map(\.1)
        }
    }

    private func analyzeRecentTracksDetailed(_ tracks: [LFItem]) -> (streak: Int, peakHour: Int?, busiestDay: String?, spectrum: DashboardModel.TimeOfDaySpectrum, daySplit: DashboardModel.DayTypeSplit) {
        let calendar = Calendar.current
        var dayCounts: [String: Int] = [:]
        var hourCounts: [Int: Int] = [:]
        var datesSet = Set<Date>()

        var morningCount = 0
        var afternoonCount = 0
        var eveningCount = 0
        var nightCount = 0

        var weekdayCount = 0
        var weekendCount = 0

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE"

        for track in tracks {
            if let date = track.playedAt {
                let dayStart = calendar.startOfDay(for: date)
                datesSet.insert(dayStart)

                let hour = calendar.component(.hour, from: date)
                hourCounts[hour, default: 0] += 1

                let dayName = dayFormatter.string(from: date)
                dayCounts[dayName, default: 0] += 1

                switch hour {
                case 6..<12: morningCount += 1
                case 12..<18: afternoonCount += 1
                case 18..<24: eveningCount += 1
                default: nightCount += 1
                }

                let weekday = calendar.component(.weekday, from: date)
                if weekday == 1 || weekday == 7 {
                    weekendCount += 1
                } else {
                    weekdayCount += 1
                }
            }
        }

        let sortedDays = datesSet.sorted()
        var longestStreak = 0
        var currentStreak = 0
        var previousDate: Date?

        for day in sortedDays {
            if let prev = previousDate, calendar.date(byAdding: .day, value: 1, to: prev) == day {
                currentStreak += 1
            } else {
                currentStreak = 1
            }
            longestStreak = max(longestStreak, currentStreak)
            previousDate = day
        }

        let peakHour = hourCounts.max(by: { $0.value < $1.value })?.key
        let busiestDay = dayCounts.max(by: { $0.value < $1.value })?.key

        let totalTimeCount = Double(max(morningCount + afternoonCount + eveningCount + nightCount, 1))
        let spectrum = DashboardModel.TimeOfDaySpectrum(
            morning: (Double(morningCount) / totalTimeCount) * 100.0,
            afternoon: (Double(afternoonCount) / totalTimeCount) * 100.0,
            evening: (Double(eveningCount) / totalTimeCount) * 100.0,
            night: (Double(nightCount) / totalTimeCount) * 100.0
        )

        let totalDayCount = Double(max(weekdayCount + weekendCount, 1))
        let daySplit = DashboardModel.DayTypeSplit(
            weekdayPct: (Double(weekdayCount) / totalDayCount) * 100.0,
            weekendPct: (Double(weekendCount) / totalDayCount) * 100.0
        )

        return (longestStreak, peakHour, busiestDay, spectrum, daySplit)
    }

    private func computeNextMilestone(_ current: Int) -> Int {
        if current < 1_000 { return 1_000 }
        if current < 5_000 { return 5_000 }
        if current < 10_000 { return 10_000 }
        if current < 25_000 { return 25_000 }
        if current < 50_000 { return 50_000 }
        if current < 100_000 { return 100_000 }
        if current < 250_000 { return 250_000 }
        return ((current / 100_000) + 1) * 100_000
    }

    private func computeGenres(userTags: [Tag], topArtists: [LFItem]) async -> [DashboardModel.GenreStats] {
        var rawCounts: [String: Int] = [:]

        for tag in userTags {
            let name = cleanTag(tag.name)
            if isValidGenre(name) {
                rawCounts[name, default: 0] += max(tag.playCount, 10)
            }
        }

        let top5 = Array(topArtists.prefix(5))
        for artist in top5 {
            if let detail = try? await LastFM.shared.artistInfo(artist.name, user: "") {
                if let tags = detail.tags?.items {
                    for t in tags {
                        let name = cleanTag(t.name)
                        if isValidGenre(name) {
                            rawCounts[name, default: 0] += max(artist.plays / 2, 5)
                        }
                    }
                }
            }
        }

        let total = Double(max(rawCounts.values.reduce(0, +), 1))
        let sorted = rawCounts.sorted { $0.value > $1.value }.prefix(6)

        return sorted.map { (genre, count) in
            DashboardModel.GenreStats(
                genre: genre,
                count: count,
                percentage: (Double(count) / total) * 100.0
            )
        }
    }

    private func cleanTag(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isValidGenre(_ tag: String) -> Bool {
        let ignored: Set<String> = ["seen live", "favorites", "favourites", "awesome", "loved", "my favorite", "spotify", "american", "british", "female vocalists", "male vocalists"]
        return !tag.isEmpty && tag.count > 2 && !ignored.contains(tag)
    }

    private func computePersonality(busiestHour: Int?, topArtists: [DashboardModel.TopItem], topTracks: [DashboardModel.TopItem]) -> DashboardModel.Personality {
        if let hour = busiestHour {
            if (22...23).contains(hour) || (0...4).contains(hour) {
                return DashboardModel.Personality(
                    title: "Night Owl Connoisseur",
                    icon: "moon.stars.fill",
                    description: "Your peak listening hours are late into the night. Music keeps you company when the rest of the world is asleep."
                )
            } else if (5...9).contains(hour) {
                return DashboardModel.Personality(
                    title: "Early Bird Listener",
                    icon: "sun.max.fill",
                    description: "You jumpstart your mornings with music. Songs fuel your early hours and set the tone for your day."
                )
            } else if (10...16).contains(hour) {
                return DashboardModel.Personality(
                    title: "Midday Power Listener",
                    icon: "bolt.fill",
                    description: "Music powers your daily workflow and focus. You stream heavily throughout daytime hours."
                )
            }
        }

        if let topTrack = topTracks.first, topTrack.playcount > 30 {
            return DashboardModel.Personality(
                title: "Obsessive Repeater",
                icon: "repeat.circle.fill",
                description: "When a song hits, you put it on repeat until every note is etched into your soul."
            )
        }

        if topArtists.count >= 20 {
            return DashboardModel.Personality(
                title: "Eclectic Explorer",
                icon: "sparkles",
                description: "You have a broad, adventurous music palette, constantly discovering diverse artists and sounds."
            )
        }

        return DashboardModel.Personality(
            title: "Music Devotee",
            icon: "headphones",
            description: "A dedicated listener with deep appreciation for your favorite records and artists."
        )
    }

    private func computeExpandedFacts(
        userInfo: UserInfo,
        topArtistsLifetime: [DashboardModel.TopItem],
        topAlbumsLifetime: [DashboardModel.TopItem],
        topTracksLifetime: [DashboardModel.TopItem],
        topArtists30Days: [DashboardModel.TopItem],
        topAlbums30Days: [DashboardModel.TopItem],
        topTracks30Days: [DashboardModel.TopItem],
        lifetimeStats: DashboardModel.StatsPeriod,
        last30DaysStats: DashboardModel.StatsPeriod,
        daysSinceRegistered: Int,
        milestone: DashboardModel.Milestone,
        daySplit: DashboardModel.DayTypeSplit
    ) -> [DashboardModel.CoolFact] {
        var facts: [DashboardModel.CoolFact] = []

        facts.append(DashboardModel.CoolFact(
            icon: "flag.checkered.circle.fill",
            title: "Milestone Target",
            subtitle: "You are \(String(format: "%.1f", milestone.percentage))% of the way to \(milestone.target.full) scrobbles! Only \(milestone.remaining.full) more to go.",
            category: "Milestones"
        ))

        if let rarest = topArtistsLifetime.filter({ ($0.globalListeners ?? 0) > 0 }).min(by: { ($0.globalListeners ?? 0) < ($1.globalListeners ?? 0) }),
           let listeners = rarest.globalListeners {
            facts.append(DashboardModel.CoolFact(
                icon: "star.fill",
                title: "Hidden Gem Discovery",
                subtitle: "\(rarest.name) is your rarest top artist, with only \(listeners.compact) global listeners on Last.fm!",
                category: "Taste"
            ))
        }

        if let topArtist = topArtistsLifetime.first, lifetimeStats.scrobbles > 0 {
            let pct = (Double(topArtist.playcount) / Double(lifetimeStats.scrobbles)) * 100.0
            facts.append(DashboardModel.CoolFact(
                icon: "heart.fill",
                title: "Top Artist Loyalty",
                subtitle: "\(topArtist.name) accounts for \(String(format: "%.1f", pct))% of all your lifetime scrobbles (\(topArtist.playcount.full) plays).",
                category: "Taste"
            ))
        }

        if daySplit.weekdayPct > 0 || daySplit.weekendPct > 0 {
            let pref = daySplit.weekdayPct > daySplit.weekendPct ? "Monday–Friday" : "Weekends"
            facts.append(DashboardModel.CoolFact(
                icon: "calendar",
                title: "Weekly Listening Habits",
                subtitle: "You listen to music primarily on \(pref) (\(String(format: "%.0f", max(daySplit.weekdayPct, daySplit.weekendPct)))% of your scrobbles).",
                category: "Habits"
            ))
        }

        let daysMusic = lifetimeStats.totalHours / 24
        facts.append(DashboardModel.CoolFact(
            icon: "hourglass",
            title: "Music Marathon Milestone",
            subtitle: "You've listened to ~\(lifetimeStats.totalHours.full) hours of music. That's over \(daysMusic) full days of continuous sound!",
            category: "Milestones"
        ))

        if lifetimeStats.dailyAverage > 0 {
            let minutesPerTrack = (24.0 * 60.0) / lifetimeStats.dailyAverage
            facts.append(DashboardModel.CoolFact(
                icon: "speedometer",
                title: "Scrobble Pace",
                subtitle: "You scrobble an average of \(String(format: "%.1f", lifetimeStats.dailyAverage)) tracks per day — about 1 song every \(Int(minutesPerTrack)) minutes!",
                category: "Habits"
            ))
        }

        if let topAlbum = topAlbums30Days.first ?? topAlbumsLifetime.first, last30DaysStats.scrobbles > 0 {
            let pct = (Double(topAlbum.playcount) / Double(max(last30DaysStats.scrobbles, 1))) * 100.0
            facts.append(DashboardModel.CoolFact(
                icon: "opticaldisc.fill",
                title: "Album Focus",
                subtitle: "'\(topAlbum.name)' by \(topAlbum.subtitle ?? "Artist") represents \(String(format: "%.1f", pct))% of your recent album listens.",
                category: "Taste"
            ))
        }

        let uniqueArtistsCount = Set(topArtists30Days.map(\.name)).count
        if uniqueArtistsCount > 0 {
            facts.append(DashboardModel.CoolFact(
                icon: "music.quaver.fill",
                title: "30-Day Music Variety",
                subtitle: "You listened to \(uniqueArtistsCount) distinct top artists in the past month alone.",
                category: "Exploration"
            ))
        }

        if let peak = lifetimeStats.busiestHour {
            let ampm = peak < 12 ? "AM" : "PM"
            let h = peak % 12 == 0 ? 12 : peak % 12
            facts.append(DashboardModel.CoolFact(
                icon: "clock.badge.checkmark.fill",
                title: "Peak Vibe Hour",
                subtitle: "Your scrobble activity spikes around \(h):00 \(ampm). That's your primary soundtrack window.",
                category: "Habits"
            ))
        }

        let years = max(1, daysSinceRegistered / 365)
        let scrobblesPerYear = lifetimeStats.scrobbles / years
        facts.append(DashboardModel.CoolFact(
            icon: "sparkles.tv.fill",
            title: "Last.fm Legacy",
            subtitle: "You've been scrobbling for \(daysSinceRegistered) days (~\(years) year\(years == 1 ? "" : "s")), averaging \(scrobblesPerYear.full) scrobbles per year!",
            category: "Milestones"
        ))

        return facts
    }
}

// MARK: - DashboardView (Stats Tab)

struct DashboardView: View {
    @EnvironmentObject private var app: AppModel
    @StateObject private var vm = DashboardViewModel()
    @State private var periodSelection = 0 // 0: Lifetime, 1: Past 30 Days
    @State private var itemsPeriodSelection = 0 // 0: Past 30 Days, 1: Lifetime
    @State private var selectedFactCategory = "All"

    var body: some View {
        NavigationStack {
            ScrollView {
                if vm.loading && vm.dashboard.totalScrobbles == 0 {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.3)
                        Text("Gathering stats, facts, and Last.fm artwork...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                    .padding(.top, 60)
                } else if let error = vm.error, vm.dashboard.totalScrobbles == 0 {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.red)
                        Text("Failed to load dashboard")
                            .font(.title2.bold())
                        Text(error)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button("Retry") {
                            Task { await vm.loadAll(username: app.username, bypassCache: true) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(24)
                    .glass(22)
                    .padding(20)
                } else {
                    VStack(spacing: 24) {
                        profileHeaderSection()
                        if let milestone = vm.dashboard.milestone {
                            milestoneCard(milestone)
                        }
                        statsOverviewSection()
                        timeOfDaySpectrumSection()
                        if let personality = vm.dashboard.personality {
                            personalitySection(personality)
                        }
                        genreBreakdownSection()
                        topMusicSection()
                        coolFactsSection()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .background(Backdrop())
            .navigationTitle("Stats & Facts")
            .refreshable {
                await vm.loadAll(username: app.username, bypassCache: true)
            }
            .task(id: app.username) {
                await vm.loadAll(username: app.username)
            }
            .tonalDestinations()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func profileHeaderSection() -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                UserAvatarView(url: vm.dashboard.avatarURL, username: vm.dashboard.username, size: 72)

                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.dashboard.username)
                        .font(.title2.weight(.bold))

                    HStack(spacing: 8) {
                        if let country = vm.dashboard.country, !country.isEmpty {
                            Label(country, systemImage: "globe")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        if let memberSince = vm.dashboard.memberSince {
                            Text("• Joined \(memberSince.formatted(.dateTime.year().month(.abbreviated)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 12) {
                        Label("\(vm.dashboard.totalScrobbles.full) scrobbles", systemImage: "play.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.accent)

                        let hrs = vm.dashboard.lifetimeStats.totalHours
                        Label("~\(hrs.full) hrs", systemImage: "clock.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }

                Spacer()
            }
        }
        .padding(18)
        .glass(22)
    }

    @ViewBuilder
    private func milestoneCard(_ milestone: DashboardModel.Milestone) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Next Scrobble Milestone", systemImage: "flag.checkered.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.gradient)

                Spacer()

                Text("\(milestone.current.full) / \(milestone.target.full)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 10)
                    Capsule()
                        .fill(Theme.gradient)
                        .frame(width: max(0, proxy.size.width * CGFloat(milestone.percentage / 100.0)), height: 10)
                }
            }
            .frame(height: 10)

            HStack {
                Text("\(String(format: "%.1f", milestone.percentage))% complete")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.accent)
                Spacer()
                Text("\(milestone.remaining.full) scrobbles remaining")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .glass(20)
    }

    @ViewBuilder
    private func timeOfDaySpectrumSection() -> some View {
        let s = vm.dashboard.timeOfDaySpectrum
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Time of Day Energy Spectrum", "When your scrobbles happen")

            HStack(spacing: 12) {
                timeSegmentTile(icon: "sun.rise.fill", title: "Morning", pct: s.morning)
                timeSegmentTile(icon: "sun.max.fill", title: "Afternoon", pct: s.afternoon)
                timeSegmentTile(icon: "sunset.fill", title: "Evening", pct: s.evening)
                timeSegmentTile(icon: "moon.stars.fill", title: "Night", pct: s.night)
            }
        }
    }

    @ViewBuilder
    private func timeSegmentTile(icon: String, title: String, pct: Double) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(Theme.accent)

            Text("\(String(format: "%.0f", pct))%")
                .font(.subheadline.weight(.bold))

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glass(16)
    }

    @ViewBuilder
    private func statsOverviewSection() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionTitle("Activity Overview", "Lifetime vs Past Month")
                Spacer()
                Picker("Period", selection: $periodSelection) {
                    Text("Lifetime").tag(0)
                    Text("30 Days").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                .onChange(of: periodSelection) { _ in Haptics.selection() }
            }

            let stats = periodSelection == 0 ? vm.dashboard.lifetimeStats : vm.dashboard.last30DaysStats

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                StatTile(
                    icon: "music.note.list",
                    label: periodSelection == 0 ? "Total Scrobbles" : "30-Day Scrobbles",
                    value: stats.scrobbles.full
                )
                StatTile(
                    icon: "chart.line.uptrend.xyaxis",
                    label: "Daily Average",
                    value: String(format: "%.1f", stats.dailyAverage)
                )
                StatTile(
                    icon: "flame.fill",
                    label: "Longest Streak",
                    value: "\(stats.longestStreak) day\(stats.longestStreak == 1 ? "" : "s")"
                )
                StatTile(
                    icon: "clock.fill",
                    label: "Peak Hour",
                    value: stats.busiestHour.map(hourFormatted) ?? "—"
                )
                StatTile(
                    icon: "calendar.badge.clock",
                    label: "Busiest Day",
                    value: stats.busiestDayName ?? "—"
                )
                StatTile(
                    icon: "hourglass",
                    label: "Listening Time",
                    value: "~\(stats.totalHours) hrs"
                )
            }
        }
    }

    @ViewBuilder
    private func personalitySection(_ p: DashboardModel.Personality) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Listening Taste & Persona")

            HStack(spacing: 16) {
                Image(systemName: p.icon)
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.gradient)
                    .frame(width: 60, height: 60)
                    .background(Theme.gradient.opacity(0.15))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(p.title)
                        .font(.headline.weight(.bold))
                    Text(p.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .glass(22)
        }
    }

    @ViewBuilder
    private func genreBreakdownSection() -> some View {
        if !vm.dashboard.genreStats.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle("Top Music Genres", "Based on your top artists and tags")

                VStack(spacing: 12) {
                    ForEach(vm.dashboard.genreStats) { g in
                        VStack(spacing: 6) {
                            HStack {
                                Text(g.genre.capitalized)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(String(format: "%.1f", g.percentage))%")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }

                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.08))
                                        .frame(height: 8)
                                    Capsule()
                                        .fill(Theme.gradient)
                                        .frame(width: max(0, proxy.size.width * CGFloat(g.percentage / 100.0)), height: 8)
                                }
                            }
                            .frame(height: 8)
                        }
                    }
                }
                .padding(18)
                .glass(22)
            }
        }
    }

    @ViewBuilder
    private func topMusicSection() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionTitle("Top Music Showcase")
                Spacer()
                Picker("Timeframe", selection: $itemsPeriodSelection) {
                    Text("30 Days").tag(0)
                    Text("Lifetime").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                .onChange(of: itemsPeriodSelection) { _ in Haptics.selection() }
            }

            let artists = itemsPeriodSelection == 0 ? vm.dashboard.topArtists30Days : vm.dashboard.topArtistsLifetime
            let albums = itemsPeriodSelection == 0 ? vm.dashboard.topAlbums30Days : vm.dashboard.topAlbumsLifetime
            let tracks = itemsPeriodSelection == 0 ? vm.dashboard.topTracks30Days : vm.dashboard.topTracksLifetime

            if !artists.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Top Artists")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(Array(artists.prefix(12).enumerated()), id: \.element.id) { index, item in
                                NavigationLink(value: ArtistRoute(name: item.name)) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ZStack(alignment: .topLeading) {
                                            ArtistArtwork(name: item.name, fallback: item.imageURL)
                                                .frame(width: 100, height: 100)
                                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                                            Text("#\(index + 1)")
                                                .font(.caption2.weight(.bold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3)
                                                .background(.ultraThinMaterial, in: Capsule())
                                                .padding(6)
                                        }

                                        Text(item.name)
                                            .font(.footnote.weight(.semibold))
                                            .lineLimit(1)
                                        Text("\(item.playcount.full) plays")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(width: 100)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            if !albums.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Top Albums")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(Array(albums.prefix(12).enumerated()), id: \.element.id) { index, item in
                                NavigationLink(value: AlbumRoute(artist: item.subtitle ?? "", name: item.name)) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ZStack(alignment: .topLeading) {
                                            Artwork(url: item.imageURL)
                                                .frame(width: 100, height: 100)
                                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                                            Text("#\(index + 1)")
                                                .font(.caption2.weight(.bold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3)
                                                .background(.ultraThinMaterial, in: Capsule())
                                                .padding(6)
                                        }

                                        Text(item.name)
                                            .font(.footnote.weight(.semibold))
                                            .lineLimit(1)
                                        Text(item.subtitle ?? "")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .frame(width: 100)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            if !tracks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Top Tracks")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 6) {
                        ForEach(Array(tracks.prefix(6).enumerated()), id: \.element.id) { index, track in
                            NavigationLink(value: ArtistRoute(name: track.subtitle ?? "")) {
                                HStack(spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(Theme.accent)
                                        .frame(width: 20)

                                    Artwork(url: track.imageURL)
                                        .frame(width: 44, height: 44)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(track.name)
                                            .font(.subheadline.weight(.semibold))
                                            .lineLimit(1)
                                        Text(track.subtitle ?? "")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Text("\(track.playcount.full) plays")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                    .glass(20)
                }
            }
        }
    }

    @ViewBuilder
    private func coolFactsSection() -> some View {
        if !vm.dashboard.coolFacts.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle("Cool Facts & Music Trivia", "Deep insights from your Last.fm profile")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["All", "Milestones", "Habits", "Taste"], id: \.self) { category in
                            Button {
                                Haptics.selection()
                                selectedFactCategory = category
                            } label: {
                                Chip(text: category, selected: selectedFactCategory == category)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                let filteredFacts = vm.dashboard.coolFacts.filter {
                    selectedFactCategory == "All" || $0.category == selectedFactCategory
                }

                VStack(spacing: 12) {
                    ForEach(filteredFacts) { fact in
                        funFactTile(
                            icon: fact.icon,
                            title: fact.title,
                            subtitle: fact.subtitle,
                            category: fact.category
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func funFactTile(icon: String, title: String, subtitle: String, category: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Theme.gradient)
                .frame(width: 46, height: 46)
                .background(Theme.gradient.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    Text(category)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.gradient.opacity(0.12), in: Capsule())
                        .foregroundStyle(Theme.accent)
                }
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .glass(18)
    }

    private func hourFormatted(_ h: Int) -> String {
        let ampm = h < 12 ? "AM" : "PM"
        let displayHour = h % 12 == 0 ? 12 : h % 12
        return "\(displayHour):00 \(ampm)"
    }
}

// MARK: - MeView (Settings & Customization Hub)

struct MeView: View {
    @EnvironmentObject private var app: AppModel
    @StateObject private var profileLoader = UserProfileLoader()
    @State private var showingResetAlert = false
    @State private var showingCacheAlert = false
    @State private var showingDefaultsAlert = false

    var body: some View {
        NavigationStack {
            Form {
                profileSection()
                appearanceSection()
                accentColorSection()
                layoutSection()
                scrobbleSettingsSection()
                startupSection()
                performanceSection()
                aboutSection()
                dangerSection()
            }
            .navigationTitle("Me")
            .alert("Clear Cache?", isPresented: $showingCacheAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    Task {
                        await LastFM.shared.clearCache()
                        await LastFMArtworkResolver.shared.clearCache()
                        profileLoader.load(username: app.username)
                    }
                }
            } message: {
                Text("This will purge stored artwork and API responses, reloading fresh data from Last.fm.")
            }
            .alert("Reset All Settings?", isPresented: $showingDefaultsAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset to Defaults", role: .destructive) {
                    app.appearanceMode = .system
                    app.accentOption = .purple
                    app.fontStyle = .rounded
                    app.glassStyle = .vibrant
                    app.cornerRadiusStyle = .extraRounded
                    app.hapticsEnabled = true
                    app.dataSaverEnabled = false
                    app.autoTimestampScrobble = true
                    app.showGlobalListeners = true
                    Haptics.notification(.success)
                }
            } message: {
                Text("This will restore default font, theme, glass style, and performance settings.")
            }
            .alert("Reset Onboarding?", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    app.onboarded = false
                }
            } message: {
                Text("This will return you to the profile setup screen.")
            }
            .onAppear {
                profileLoader.load(username: app.username)
            }
        }
    }

    @ViewBuilder
    private func profileSection() -> some View {
        Section("Profile") {
            HStack(spacing: 14) {
                UserAvatarView(url: profileLoader.userInfo?.avatarURL, username: app.username, size: 54)

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.username)
                        .font(.headline)

                    if let info = profileLoader.userInfo {
                        Text("\(info.playcount.int.full) lifetime scrobbles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if profileLoader.loading {
                        Text("Loading profile stats...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)

            if let info = profileLoader.userInfo {
                if let country = info.country, !country.isEmpty {
                    LabeledContent("Country", value: country)
                }
                LabeledContent("Member Since", value: info.since.formatted(.dateTime.year().month().day()))
            }
        }
    }

    @ViewBuilder
    private func appearanceSection() -> some View {
        Section("Appearance & Typography") {
            Picker("Theme Mode", selection: $app.appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: app.appearanceMode) { _ in Haptics.trigger(.medium) }

            Picker("Glass & Card Style", selection: $app.glassStyle) {
                ForEach(GlassStyleOption.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: app.glassStyle) { _ in Haptics.trigger(.medium) }

            Picker("Font Design", selection: $app.fontStyle) {
                ForEach(FontStyleOption.allCases) { fontOption in
                    Text(fontOption.rawValue).tag(fontOption)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: app.fontStyle) { _ in Haptics.trigger(.medium) }

            Picker("Corner Radius Style", selection: $app.cornerRadiusStyle) {
                ForEach(CornerRadiusStyle.allCases) { cornerOption in
                    Text(cornerOption.rawValue).tag(cornerOption)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: app.cornerRadiusStyle) { _ in Haptics.trigger(.medium) }
        }
    }

    @ViewBuilder
    private func accentColorSection() -> some View {
        Section(header: Text("App Accent Color"), footer: Text("Choose your favorite accent color and gradient to customize all buttons, highlights, and charts across Tonal.")) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(AccentColorOption.allCases) { option in
                        Button {
                            Haptics.trigger(.medium)
                            withAnimation(.easeInOut(duration: 0.2)) {
                                app.accentOption = option
                            }
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    if option == .custom {
                                        Circle()
                                            .fill(AppModel.hexToColor(app.customHex))
                                            .frame(width: 44, height: 44)
                                    } else {
                                        Circle()
                                            .fill(option.gradient)
                                            .frame(width: 44, height: 44)
                                    }

                                    if app.accentOption == option {
                                        Image(systemName: "checkmark")
                                            .font(.headline.weight(.bold))
                                            .foregroundColor(.white)
                                    }
                                }
                                .overlay(
                                    Circle()
                                        .stroke(app.accentOption == option ? Color.primary : Color.clear, lineWidth: 2)
                                )

                                Text(option.rawValue)
                                    .font(.caption2.weight(app.accentOption == option ? .bold : .medium))
                                    .foregroundStyle(app.accentOption == option ? Color.primary : Color.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            }

            if app.accentOption == .custom {
                ColorPicker("Custom Accent Color", selection: Binding(
                    get: { AppModel.hexToColor(app.customHex) },
                    set: { newColor in
                        let hex = AppModel.colorToHex(newColor)
                        app.customHex = hex
                        Haptics.selection()
                    }
                ))
            }
        }
    }

    @ViewBuilder
    private func layoutSection() -> some View {
        Section("Display & UI Details") {
            Toggle("Show Global Listeners Count", isOn: $app.showGlobalListeners)
                .onChange(of: app.showGlobalListeners) { _ in Haptics.trigger(.light) }
        }
    }

    @ViewBuilder
    private func scrobbleSettingsSection() -> some View {
        Section("Scrobble Engine") {
            Toggle("Auto-Timestamp Current Time", isOn: $app.autoTimestampScrobble)
                .onChange(of: app.autoTimestampScrobble) { _ in Haptics.trigger(.light) }
        }
    }

    @ViewBuilder
    private func startupSection() -> some View {
        Section("Startup & Navigation") {
            Picker("Default Landing Tab", selection: $app.defaultTab) {
                ForEach(DefaultTabOption.allCases) { tabOption in
                    Text(tabOption.rawValue).tag(tabOption)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: app.defaultTab) { _ in Haptics.trigger(.medium) }
        }
    }

    @ViewBuilder
    private func performanceSection() -> some View {
        Section("Performance & Cache") {
            Toggle("Haptic Feedback", isOn: $app.hapticsEnabled)
                .onChange(of: app.hapticsEnabled) { enabled in
                    if enabled { Haptics.trigger(.light) }
                }

            Toggle("Data Saver (Optimized Imagery)", isOn: $app.dataSaverEnabled)
                .onChange(of: app.dataSaverEnabled) { _ in Haptics.trigger(.light) }

            Button("Clear Image & API Cache") {
                Haptics.notification(.warning)
                showingCacheAlert = true
            }

            Button("Restore Default Settings") {
                Haptics.trigger(.medium)
                showingDefaultsAlert = true
            }
        }
    }

    @ViewBuilder
    private func aboutSection() -> some View {
        Section("About Tonal") {
            LabeledContent("App Version", value: "1.0.0 (Top 1 Build)")
            Text("Designed & Built by Lilith 'exyvt' Tuczai")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func dangerSection() -> some View {
        Section {
            Button("Reset Onboarding Profile", role: .destructive) {
                Haptics.notification(.warning)
                showingResetAlert = true
            }
        }
    }
}

// MARK: - User Profile Loader

@MainActor
final class UserProfileLoader: ObservableObject {
    @Published var userInfo: UserInfo?
    @Published var loading = false
    @Published var error: String?

    func load(username: String) {
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let clean = username.trimmingCharacters(in: .whitespacesAndNewlines)
        loading = true
        error = nil
        Task {
            do {
                let info = try await LastFM.shared.userInfo(clean)
                self.userInfo = info
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }
}
