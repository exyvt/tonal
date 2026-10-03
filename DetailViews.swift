import SwiftUI

struct ArtistView: View {
    let name: String
    @EnvironmentObject var app: AppModel
    @State private var detail: ArtistDetail?
    @State private var albums: [LFItem] = []
    @State private var tracks: [LFItem] = []
    @State private var expanded = false

    private var listeners: Int { detail?.stats?.listeners?.int ?? 0 }
    private var plays: Int { detail?.stats?.playcount?.int ?? 0 }
    private var mine: Int { detail?.stats?.userplaycount?.int ?? 0 }
    private var ratio: String { listeners > 0 ? String(format: "%.1f", Double(plays) / Double(listeners)) : "—" }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                hero
                VStack(spacing: 28) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                        StatTile(icon: "person.2.fill", label: "Listeners", value: listeners.compact)
                        StatTile(icon: "play.fill", label: "Global scrobbles", value: plays.compact)
                        StatTile(icon: "heart.fill", label: "Your scrobbles", value: mine.full)
                        StatTile(icon: "repeat", label: "Plays per listener", value: ratio)
                    }
                    if let bio = detail?.bio?.summary?.plainText, !bio.isEmpty { bioCard(bio) }
                    if !tracks.isEmpty { topTracks }
                    if !albums.isEmpty { albumStrip }
                    if let sim = detail?.similar?.items, !sim.isEmpty {
                        VStack(spacing: 14) {
                            SectionTitle("Fans also like")
                            ArtistStrip(items: sim) { _ in "" }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 40)
        }
        .background(Backdrop())
        .ignoresSafeArea(edges: .top)
        .task(id: name + app.username) { await load() }
    }

    private var hero: some View {
        Color.clear
            .frame(height: 440)
            .overlay { ArtistArtwork(name: name) }
            .overlay(LinearGradient(colors: [.clear, Theme.bg.opacity(0.6), Theme.bg], startPoint: .center, endPoint: .bottom))
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(detail?.name ?? name)
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .minimumScaleFactor(0.5)
                    if let t = detail?.tags?.items, !t.isEmpty { TagRow(tags: t) }
                }
                .padding(20)
            }
            .clipped()
    }

    private func bioCard(_ bio: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(bio).font(.callout).lineLimit(expanded ? nil : 5).foregroundStyle(.primary.opacity(0.85))
            Button(expanded ? "Show less" : "Read more") { withAnimation { expanded.toggle() } }
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.accent2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glass(22)
    }

    private var topTracks: some View {
        let maxPlays = Double(tracks.map(\.plays).max() ?? 1)
        return VStack(spacing: 14) {
            SectionTitle("Top Tracks", "By global scrobbles")
            VStack(spacing: 6) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { i, t in
                    BarRow(rank: i + 1, title: t.name, subtitle: "\(t.listenerCount.compact) listeners", value: t.plays.compact, fraction: Double(t.plays) / maxPlays)
                }
            }
            .padding(8)
            .glass(24)
        }
    }

    private var albumStrip: some View {
        VStack(spacing: 14) {
            SectionTitle("Albums")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(albums) { a in
                        NavigationLink(value: AlbumRoute(artist: name, name: a.name)) {
                            AlbumCard(item: a, subtitle: "\(a.plays.compact) plays").frame(width: 150)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func load() async {
        async let d = LastFM.shared.artistInfo(name, user: app.username)
        async let a = LastFM.shared.artistAlbums(name)
        async let t = LastFM.shared.artistTracks(name)
        detail = try? await d
        albums = (try? await a) ?? []
        tracks = (try? await t) ?? []
    }
}

struct AlbumView: View {
    let artist: String
    let name: String
    @EnvironmentObject var app: AppModel
    @State private var detail: AlbumDetail?
    @State private var showScrobble = false

    private var tracks: [LFItem] { detail?.tracks?.items ?? [] }
    private var runtime: Int { tracks.reduce(0) { $0 + $1.seconds } }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Artwork(url: detail?.image?.best)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: Theme.accent.opacity(0.35), radius: 40, y: 20)
                    .padding(.horizontal, 40)
                    .padding(.top, 8)

                VStack(spacing: 6) {
                    Text(detail?.name ?? name)
                        .font(.system(.largeTitle, design: .rounded, weight: .black))
                        .multilineTextAlignment(.center)
                    NavigationLink(value: ArtistRoute(name: artist)) {
                        Text(artist).font(.title3.weight(.semibold)).foregroundStyle(Theme.gradient)
                    }
                }

                PrimaryButton(title: "Scrobble this album", icon: "plus.circle.fill") { showScrobble = true }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                    StatTile(icon: "person.2.fill", label: "Listeners", value: (detail?.listeners?.int ?? 0).compact)
                    StatTile(icon: "play.fill", label: "Global scrobbles", value: (detail?.playcount?.int ?? 0).compact)
                    StatTile(icon: "heart.fill", label: "Your scrobbles", value: (detail?.userplaycount?.int ?? 0).full)
                    StatTile(icon: "clock.fill", label: "Runtime", value: runtime > 0 ? "\(runtime / 60) min" : "—")
                }

                if let t = detail?.tags?.items, !t.isEmpty { TagRow(tags: t) }

                if !tracks.isEmpty {
                    VStack(spacing: 14) {
                        SectionTitle("Tracklist", "\(tracks.count) tracks")
                        VStack(spacing: 0) {
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { i, t in
                                HStack(spacing: 14) {
                                    Text("\(t.rank ?? i + 1)")
                                        .font(.system(.subheadline, design: .rounded, weight: .heavy))
                                        .foregroundStyle(Theme.gradient)
                                        .frame(width: 26)
                                    Text(t.name).font(.subheadline.weight(.medium)).lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(t.seconds > 0 ? t.seconds.clock : "").font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                if i < tracks.count - 1 { Divider().overlay(Color.primary.opacity(0.08)) }
                            }
                        }
                        .glass(24)
                    }
                }

                if let wiki = detail?.wiki?.summary?.plainText, !wiki.isEmpty {
                    Text(wiki)
                        .font(.callout)
                        .foregroundStyle(.primary.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .glass(22)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(Backdrop())
        .sheet(isPresented: $showScrobble) {
            NavigationStack {
                ScrollView {
                    AlbumScrobbleForm(artist: artist, album: name).padding(20)
                }
                .background(Backdrop())
                .navigationTitle("Scrobble album")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showScrobble = false } } }
            }
            .preferredColorScheme(app.appearanceMode.colorScheme)
        }
        .task(id: name + artist + app.username) {
            detail = try? await LastFM.shared.albumInfo(artist: artist, album: name, user: app.username)
        }
    }
}
