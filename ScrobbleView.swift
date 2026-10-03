import SwiftUI

struct FormField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var secure = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 22)
            if secure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy {
                    ProgressView().tint(.white)
                } else if let icon {
                    Image(systemName: icon)
                }
                Text(title)
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.gradient, in: Capsule())
            .foregroundStyle(.white)
        }
        .disabled(busy)
    }
}

struct StatusPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ScrobbleView: View {
    @EnvironmentObject var store: ScrobbleStore
    @State private var mode = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if store.signedIn {
                        HStack {
                            Label("Signed in as \(store.sessionUser ?? "")", systemImage: "checkmark.seal.fill")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button("Sign out") { store.signOut() }.font(.footnote)
                        }
                        .padding(14)
                        .glass(18)
                        if !store.pending.isEmpty { PendingCard() }
                        Picker("Mode", selection: $mode) {
                            Text("Song").tag(0)
                            Text("Album").tag(1)
                        }
                        .pickerStyle(.segmented)
                        if mode == 0 { SongForm() } else { AlbumPicker() }
                    } else {
                        SignInCard()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(Backdrop())
            .navigationTitle("Scrobble (beta)")
        }
    }
}

struct SignInCard: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: ScrobbleStore
    @State private var user = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "plus.circle.fill").font(.system(size: 54)).foregroundStyle(Theme.gradient)
            Text("Sign in to scrobble").font(.system(.title2, design: .rounded, weight: .bold))
            Text("Reading stats needs no login, but submitting scrobbles does. Scrobbling is still in beta so it might not work, or might not store your password.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            FormField(icon: "person.fill", placeholder: "Last.fm username", text: $user)
            FormField(icon: "lock.fill", placeholder: "Password", text: $password, secure: true)
            if Config.apiSecret == "YOUR_LASTFM_API_SECRET" {
                StatusPill(text: "Add your API shared secret to Config.apiSecret in Models.swift.")
            }
            if let error { StatusPill(text: error) }
            PrimaryButton(title: "Sign in", busy: busy) {
                Task {
                    busy = true
                    error = nil
                    do { try await store.signIn(username: user.trimmed, password: password) }
                    catch { self.error = error.localizedDescription }
                    password = ""
                    busy = false
                }
            }
            .opacity(user.trimmed.isEmpty || password.isEmpty ? 0.5 : 1)
            .disabled(user.trimmed.isEmpty || password.isEmpty)
        }
        .padding(22)
        .glass(28)
        .onAppear { user = app.username }
    }
}

struct PendingCard: View {
    @EnvironmentObject var store: ScrobbleStore

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.full.fill").foregroundStyle(Theme.accent2)
            Text("\(store.pending.count) queued scrobble\(store.pending.count == 1 ? "" : "s")")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button("Send") { Task { await store.flush() } }.font(.footnote.weight(.bold))
            Button("Discard", role: .destructive) { store.discardPending() }.font(.footnote)
        }
        .padding(14)
        .glass(18)
    }
}

struct SongForm: View {
    @EnvironmentObject var store: ScrobbleStore
    @State private var artist = ""
    @State private var track = ""
    @State private var album = ""
    @State private var useNow = true
    @State private var when = Date()
    @State private var status: String?
    @State private var busy = false

    private var valid: Bool { !artist.trimmed.isEmpty && !track.trimmed.isEmpty }

    var body: some View {
        VStack(spacing: 14) {
            FormField(icon: "person.fill", placeholder: "Artist", text: $artist)
            FormField(icon: "music.note", placeholder: "Track", text: $track)
            FormField(icon: "opticaldisc", placeholder: "Album (optional)", text: $album)
            Toggle("Played just now", isOn: $useNow).tint(Theme.accent)
            if !useNow {
                DatePicker("Played at", selection: $when, in: Date().addingTimeInterval(-13 * 86400)...Date())
            }
            PrimaryButton(title: "Scrobble", icon: "plus.circle.fill", busy: busy) {
                Task {
                    busy = true
                    let ts = Int((useNow ? Date() : when).timeIntervalSince1970)
                    let entry = ScrobbleEntry(artist: artist.trimmed, track: track.trimmed, album: album.trimmed, timestamp: ts)
                    status = await store.submit([entry])
                    busy = false
                }
            }
            .opacity(valid ? 1 : 0.5)
            .disabled(!valid)
            Button("Set as Now Playing") {
                Task { status = await store.updateNowPlaying(artist: artist.trimmed, track: track.trimmed, album: album.trimmed) }
            }
            .font(.subheadline.weight(.semibold))
            .disabled(!valid)
            if let status { StatusPill(text: status) }
        }
        .padding(18)
        .glass(26)
    }
}

struct AlbumPicker: View {
    @State private var query = ""
    @State private var results: [LFItem] = []
    @State private var selected: LFItem?

    var body: some View {
        VStack(spacing: 14) {
            if let s = selected {
                Button { selected = nil } label: {
                    Label("Back to results", systemImage: "chevron.left").font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                AlbumScrobbleForm(artist: s.artistName, album: s.name)
            } else {
                FormField(icon: "magnifyingglass", placeholder: "Search albums to scrobble", text: $query)
                    .glass(14)
                ForEach(results) { a in
                    Button { selected = a } label: {
                        HStack(spacing: 14) {
                            Artwork(url: a.artworkURL)
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(a.name).font(.body.weight(.semibold)).lineLimit(1)
                                Text(a.artistName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .glass(20)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task(id: query) {
            let q = query.trimmed
            guard !q.isEmpty else {
                results = []
                return
            }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            results = (try? await LastFM.shared.search(.albums, q)) ?? []
        }
    }
}

struct AlbumScrobbleForm: View {
    let artist: String
    let album: String
    @EnvironmentObject var store: ScrobbleStore
    @State private var detail: AlbumDetail?
    @State private var chosen: Set<String> = []
    @State private var endNow = true
    @State private var end = Date()
    @State private var status: String?
    @State private var busy = false
    @State private var loaded = false

    private var tracks: [LFItem] { detail?.tracks?.items ?? [] }
    private var selectedTracks: [LFItem] { tracks.filter { chosen.contains($0.id) } }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                Artwork(url: detail?.image?.best)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(detail?.name ?? album).font(.headline).lineLimit(2)
                    Text(detail?.artist.name ?? artist).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }

            if !store.signedIn {
                StatusPill(text: "Sign in from the Scrobble tab to submit scrobbles.")
            } else if tracks.isEmpty {
                if loaded { StatusPill(text: "No tracklist found for this album.") } else { ProgressView() }
            } else {
                HStack {
                    Text("\(chosen.count) of \(tracks.count) selected").font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button(chosen.count == tracks.count ? "None" : "All") {
                        chosen = chosen.count == tracks.count ? [] : Set(tracks.map(\.id))
                    }
                    .font(.footnote.weight(.bold))
                }
                VStack(spacing: 0) {
                    ForEach(tracks) { t in
                        Button {
                            if chosen.contains(t.id) { chosen.remove(t.id) } else { chosen.insert(t.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: chosen.contains(t.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(chosen.contains(t.id) ? Theme.accent : Color.secondary)
                                Text(t.name).font(.subheadline).lineLimit(1)
                                Spacer()
                                Text(t.seconds > 0 ? t.seconds.clock : "").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Toggle("Finished just now", isOn: $endNow).tint(Theme.accent)
                if !endNow {
                    DatePicker("Finished at", selection: $end, in: Date().addingTimeInterval(-13 * 86400)...Date())
                }
                PrimaryButton(title: "Scrobble \(chosen.count) track\(chosen.count == 1 ? "" : "s")", icon: "plus.circle.fill", busy: busy) {
                    Task {
                        busy = true
                        status = await store.submit(entries())
                        busy = false
                    }
                }
                .opacity(chosen.isEmpty ? 0.5 : 1)
                .disabled(chosen.isEmpty)
            }
            if let status { StatusPill(text: status) }
        }
        .padding(18)
        .glass(26)
        .task(id: artist + album) {
            detail = try? await LastFM.shared.albumInfo(artist: artist, album: album, user: "")
            chosen = Set(tracks.map(\.id))
            loaded = true
        }
    }

    private func entries() -> [ScrobbleEntry] {
        let finish = endNow ? Date() : end
        let picked = selectedTracks
        let durations = picked.map { $0.seconds > 0 ? $0.seconds : 210 }
        var t = Int(finish.timeIntervalSince1970) - durations.reduce(0, +)
        var out: [ScrobbleEntry] = []
        for (track, d) in zip(picked, durations) {
            out.append(ScrobbleEntry(artist: detail?.artist.name ?? artist, track: track.name, album: detail?.name ?? album, timestamp: t))
            t += d
        }
        return out
    }
}
