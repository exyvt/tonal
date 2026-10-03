import SwiftUI
import Combine

struct Rec: Identifiable, Hashable {
    let source: String
    let items: [LFItem]
    var id: String { source }
}

@MainActor
final class DiscoverModel: ObservableObject {
    @Published var recs: [Rec] = []
    @Published var artists: [LFItem] = []
    @Published var tracks: [LFItem] = []
    @Published var tags: [LFItem] = []
    @Published var tagArtists: [LFItem] = []
    @Published var selectedTag: String?
    @Published var loading = false

    func load(user: String) async {
        loading = true
        async let a = LastFM.shared.chartArtists()
        async let t = LastFM.shared.chartTracks()
        async let g = LastFM.shared.topTags()
        artists = (try? await a) ?? []
        tracks = (try? await t) ?? []
        tags = (try? await g) ?? []
        if selectedTag == nil, let first = tags.first { await selectTag(first.name) }

        if !user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let mine = (try? await LastFM.shared.topArtists(user, period: "6month", limit: 30)) ?? []
            let known = Set(mine.map(\.name))
            var out: [Rec] = []
            for a in mine.prefix(4) {
                if let sims = try? await LastFM.shared.similar(a.name) {
                    let fresh = sims.filter { !known.contains($0.name) }
                    if !fresh.isEmpty { out.append(Rec(source: a.name, items: Array(fresh.prefix(10)))) }
                }
            }
            recs = out
        }
        loading = false
    }

    func selectTag(_ tag: String) async {
        selectedTag = tag
        tagArtists = (try? await LastFM.shared.tagArtists(tag)) ?? []
    }
}

struct DiscoverContent: View {
    @EnvironmentObject var app: AppModel
    @StateObject private var model = DiscoverModel()
    @State private var exploreTab = 0 // 0: For You, 1: Global Trends, 2: Genres

    var body: some View {
        VStack(spacing: 22) {
            // Category Selector Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    categoryPill("✨ For You", tag: 0)
                    categoryPill("🌍 Global Trends", tag: 1)
                    categoryPill("🏷️ Genres & Tags", tag: 2)
                }
            }

            if model.loading && model.artists.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading global trends & recommendations...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else if exploreTab == 0 {
                forYouSection
            } else if exploreTab == 1 {
                globalTrendsSection
            } else {
                genresSection
            }
        }
        .task(id: app.username) { await model.load(user: app.username) }
    }

    @ViewBuilder
    private func categoryPill(_ title: String, tag: Int) -> some View {
        Button {
            Haptics.selection()
            withAnimation(.easeInOut(duration: 0.2)) {
                exploreTab = tag
            }
        } label: {
            Chip(text: title, selected: exploreTab == tag)
        }
        .buttonStyle(.plain)
    }

    // MARK: - For You

    @ViewBuilder
    private var forYouSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            if model.recs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 44))
                        .foregroundStyle(Theme.gradient)
                    Text("Explore Recommendations")
                        .font(.headline)
                    Text("Scrobble more tracks to unlock smart recommendations based on your listening taste.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .glass(22)
            } else {
                ForEach(model.recs) { rec in
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle("Because you love \(rec.source)")
                        ArtistStrip(items: rec.items) { _ in "" }
                    }
                }
            }
        }
    }

    // MARK: - Global Trends

    @ViewBuilder
    private var globalTrendsSection: some View {
        let maxPlays = Double(model.tracks.map(\.plays).max() ?? 1)

        VStack(alignment: .leading, spacing: 24) {
            // Hero Card for #1 Global Artist
            if let topArtist = model.artists.first {
                NavigationLink(value: ArtistRoute(name: topArtist.name)) {
                    ZStack(alignment: .bottomLeading) {
                        ArtistArtwork(name: topArtist.name, fallback: topArtist.artworkURL)
                            .frame(height: 180)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(
                                LinearGradient(
                                    colors: [.clear, .black.opacity(0.8)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("#1 Global Trending")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Theme.gradient, in: Capsule())
                                    .foregroundColor(.white)
                                Spacer()
                            }

                            Text(topArtist.name)
                                .font(.title2.weight(.bold))
                                .foregroundColor(.white)

                            Text("\(topArtist.listenerCount.compact) listeners worldwide")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(16)
                    }
                }
                .buttonStyle(.plain)
            }

            // Global Chart Artists Strip
            if !model.artists.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle("Chart Top Artists", "Most popular artists globally")
                    ArtistStrip(items: Array(model.artists.prefix(12))) { "\($0.listenerCount.compact) listeners" }
                }
            }

            // Global Chart Top Tracks
            if !model.tracks.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle("Global Pulse Tracks", "Most scrobbled songs worldwide")

                    VStack(spacing: 8) {
                        ForEach(Array(model.tracks.enumerated()), id: \.element.id) { i, t in
                            NavigationLink(value: ArtistRoute(name: t.artistName)) {
                                BarRow(
                                    rank: i + 1,
                                    title: t.name,
                                    subtitle: t.artistName,
                                    value: t.plays.compact,
                                    fraction: Double(t.plays) / maxPlays
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .glass(22)
                }
            }
        }
    }

    // MARK: - Genres & Tags

    @ViewBuilder
    private var genresSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle("Genre Explorer", "Tap a tag to see its biggest artists")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.tags) { tag in
                        Button {
                            Haptics.selection()
                            Task { await model.selectTag(tag.name) }
                        } label: {
                            Chip(text: tag.name.capitalized, selected: model.selectedTag == tag.name)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !model.tagArtists.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Top \((model.selectedTag ?? "Genre").capitalized) Artists")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.accent)

                    ArtistStrip(items: model.tagArtists) { _ in "" }
                }
            }
        }
    }
}

// MARK: - SearchView

struct SearchView: View {
    @State private var query = ""
    @State private var kind = SearchKind.artists
    @State private var results: [LFItem] = []
    @State private var searching = false
    @State private var trendingIdeas: [String] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                        Picker("Kind", selection: $kind) {
                            ForEach(SearchKind.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: kind) { _ in Haptics.selection() }
                    }

                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        VStack(spacing: 24) {
                            // Recommendation bar under search bar updated with trending artists
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    let list = trendingIdeas.isEmpty ? ["Radiohead", "Tame Impala", "Kendrick Lamar", "Taylor Swift", "Daft Punk"] : trendingIdeas
                                    ForEach(list, id: \.self) { s in
                                        Button {
                                            Haptics.selection()
                                            query = s
                                        } label: {
                                            Chip(text: s)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            DiscoverContent()
                        }
                    } else if results.isEmpty && !searching {
                        Text("No results").foregroundStyle(.secondary).padding(.top, 60)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(results) { row($0) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(Backdrop())
            .navigationTitle("Explore")
            .searchable(text: $query, prompt: "Search artists, albums, tracks...")
            .task {
                if let chart = try? await LastFM.shared.chartArtists() {
                    trendingIdeas = Array(chart.prefix(10).map(\.name))
                }
            }
            .task(id: "\(query)|\(kind.rawValue)") { await run() }
            .tonalDestinations()
        }
    }

    @ViewBuilder
    private func row(_ item: LFItem) -> some View {
        switch kind {
        case .artists:
            NavigationLink(value: ArtistRoute(name: item.name)) {
                resultRow(
                    art: AnyView(ArtistArtwork(name: item.name, fallback: item.artworkURL).frame(width: 56, height: 56).clipShape(Circle())),
                    title: item.name,
                    sub: "\(item.listenerCount.compact) listeners"
                )
            }
            .buttonStyle(.plain)
        case .albums:
            NavigationLink(value: AlbumRoute(artist: item.artistName, name: item.name)) {
                resultRow(
                    art: AnyView(Artwork(url: item.artworkURL).frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))),
                    title: item.name,
                    sub: item.artistName
                )
            }
            .buttonStyle(.plain)
        case .tracks:
            NavigationLink(value: ArtistRoute(name: item.artistName)) {
                resultRow(
                    art: AnyView(Artwork(url: item.artworkURL).frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))),
                    title: item.name,
                    sub: "\(item.artistName) · \(item.listenerCount.compact) listeners"
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func resultRow(art: AnyView, title: String, sub: String) -> some View {
        HStack(spacing: 14) {
            art
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold)).lineLimit(1)
                Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Theme.accent)
        }
        .padding(12)
        .glass(20)
    }

    private func run() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            results = []
            return
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }
        searching = true
        results = (try? await LastFM.shared.search(kind, q)) ?? []
        searching = false
    }
}
