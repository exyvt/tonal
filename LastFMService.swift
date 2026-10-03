import Foundation

enum LFError: LocalizedError {
    case api(String), badURL

    var errorDescription: String? {
        switch self {
        case .api(let m): return m
        case .badURL: return "Invalid request."
        }
    }
}

extension CodingUserInfoKey {
    static let path = CodingUserInfoKey(rawValue: "path")!
}

private struct PathItems: Decodable {
    let items: [LFItem]
    init(from decoder: Decoder) throws {
        let path = decoder.userInfo[.path] as? [String] ?? []
        var c = try decoder.container(keyedBy: AnyKey.self)
        for key in path.dropLast() {
            c = try c.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey(key))
        }
        items = (try? c.decode(OneOrMany<LFItem>.self, forKey: AnyKey(path.last ?? "")).items) ?? []
    }
}

private struct ErrorBody: Decodable {
    let error: Int
    let message: String
}

actor LastFM {
    static let shared = LastFM()
    private var cache: [String: (data: Data, timestamp: Date)] = [:]
    private let cacheTTL: TimeInterval = 300 // 5 minutes

    func clearCache() {
        cache.removeAll()
    }

    private func cacheKey(_ method: String, _ params: [String: String]) -> String {
        let sorted = params.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        return "\(method)?\(sorted)"
    }

    private func data(_ method: String, _ params: [String: String], bypassCache: Bool = false) async throws -> Data {
        let key = cacheKey(method, params)
        if !bypassCache, let cached = cache[key], Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return cached.data
        }

        var comps = URLComponents(string: "https://ws.audioscrobbler.com/2.0/")!
        var q = [
            URLQueryItem(name: "method", value: method),
            URLQueryItem(name: "api_key", value: Config.apiKey),
            URLQueryItem(name: "format", value: "json")
        ]
        q += params.map { URLQueryItem(name: $0.key, value: $0.value) }
        comps.queryItems = q
        guard let url = comps.url else { throw LFError.badURL }

        let (d, _) = try await URLSession.shared.data(from: url)
        if let e = try? JSONDecoder().decode(ErrorBody.self, from: d) { throw LFError.api(e.message) }

        cache[key] = (d, Date())
        return d
    }

    private func decode<T: Decodable>(_ type: T.Type, _ method: String, _ params: [String: String], bypassCache: Bool = false) async throws -> T {
        let d = try await data(method, params, bypassCache: bypassCache)
        return try JSONDecoder().decode(type, from: d)
    }

    private func items(_ method: String, _ params: [String: String], path: [String], bypassCache: Bool = false) async throws -> [LFItem] {
        let d = try await data(method, params, bypassCache: bypassCache)
        let decoder = JSONDecoder()
        decoder.userInfo[.path] = path
        return try decoder.decode(PathItems.self, from: d).items
    }

    func history(_ user: String, from: Int, page: Int, bypassCache: Bool = false) async throws -> [LFItem] {
        try await items("user.getrecenttracks", ["user": user, "limit": "200", "from": "\(from)", "page": "\(page)"], path: ["recenttracks", "track"], bypassCache: bypassCache)
    }

    func userInfo(_ user: String, bypassCache: Bool = false) async throws -> UserInfo {
        struct R: Decodable { let user: UserInfo }
        return try await decode(R.self, "user.getinfo", ["user": user], bypassCache: bypassCache).user
    }

    func userTopTags(_ user: String, limit: Int = 20, bypassCache: Bool = false) async throws -> [Tag] {
        let d = try await data("user.gettoptags", ["user": user, "limit": "\(limit)"], bypassCache: bypassCache)
        struct Root: Decodable {
            struct TopTags: Decodable {
                let tag: [Tag]
            }
            let toptags: TopTags
        }
        let decoded = try JSONDecoder().decode(Root.self, from: d)
        return decoded.toptags.tag
    }

    func topArtists(_ user: String, period: String, limit: Int = 20, bypassCache: Bool = false) async throws -> [LFItem] {
        try await items("user.gettopartists", ["user": user, "period": period, "limit": "\(limit)"], path: ["topartists", "artist"], bypassCache: bypassCache)
    }

    func topAlbums(_ user: String, period: String, limit: Int = 12, bypassCache: Bool = false) async throws -> [LFItem] {
        try await items("user.gettopalbums", ["user": user, "period": period, "limit": "\(limit)"], path: ["topalbums", "album"], bypassCache: bypassCache)
    }

    func topTracks(_ user: String, period: String, limit: Int = 10, bypassCache: Bool = false) async throws -> [LFItem] {
        try await items("user.gettoptracks", ["user": user, "period": period, "limit": "\(limit)"], path: ["toptracks", "track"], bypassCache: bypassCache)
    }

    func recent(_ user: String, limit: Int = 30, bypassCache: Bool = false) async throws -> [LFItem] {
        try await items("user.getrecenttracks", ["user": user, "limit": "\(limit)"], path: ["recenttracks", "track"], bypassCache: bypassCache)
    }

    func artistInfo(_ name: String, user: String) async throws -> ArtistDetail {
        struct R: Decodable { let artist: ArtistDetail }
        var p = ["artist": name, "autocorrect": "1"]
        if !user.isEmpty { p["username"] = user }
        return try await decode(R.self, "artist.getinfo", p).artist
    }

    func artistAlbums(_ name: String) async throws -> [LFItem] {
        try await items("artist.gettopalbums", ["artist": name, "autocorrect": "1", "limit": "12"], path: ["topalbums", "album"])
    }

    func artistTracks(_ name: String) async throws -> [LFItem] {
        try await items("artist.gettoptracks", ["artist": name, "autocorrect": "1", "limit": "8"], path: ["toptracks", "track"])
    }

    func albumInfo(artist: String, album: String, user: String) async throws -> AlbumDetail {
        struct R: Decodable { let album: AlbumDetail }
        var p = ["artist": artist, "album": album, "autocorrect": "1"]
        if !user.isEmpty { p["username"] = user }
        return try await decode(R.self, "album.getinfo", p).album
    }

    func search(_ kind: SearchKind, _ query: String) async throws -> [LFItem] {
        try await items(kind.method, [kind.singular: query, "limit": "25"], path: kind.path)
    }

    func chartArtists() async throws -> [LFItem] {
        try await items("chart.gettopartists", ["limit": "15"], path: ["artists", "artist"])
    }

    func chartTracks() async throws -> [LFItem] {
        try await items("chart.gettoptracks", ["limit": "10"], path: ["tracks", "track"])
    }

    func topTags() async throws -> [LFItem] {
        try await items("chart.gettoptags", ["limit": "16"], path: ["tags", "tag"])
    }

    func tagArtists(_ tag: String) async throws -> [LFItem] {
        try await items("tag.gettopartists", ["tag": tag, "limit": "12"], path: ["topartists", "artist"])
    }

    func similar(_ artist: String) async throws -> [LFItem] {
        try await items("artist.getsimilar", ["artist": artist, "autocorrect": "1", "limit": "14"], path: ["similarartists", "artist"])
    }
}

actor LastFMArtworkResolver {
    static let shared = LastFMArtworkResolver()
    private var cache: [String: URL] = [:]
    private var misses: Set<String> = []

    func clearCache() {
        cache.removeAll()
        misses.removeAll()
    }

    func artistImage(_ name: String) async -> URL? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = "artist:\(cleanName)"

        if let u = cache[key] { return u }
        if misses.contains(key) { return nil }

        // 1. Try Last.fm artist info
        if let detail = try? await LastFM.shared.artistInfo(cleanName, user: ""),
           let url = detail.image?.best {
            cache[key] = url
            return url
        }

        // 2. Fallback to Deezer Search API
        if let deezerURL = await fetchDeezerArtistImage(cleanName) {
            cache[key] = deezerURL
            return deezerURL
        }

        // 3. Fallback to iTunes Search API
        if let itunesURL = await fetchITunesArtistImage(cleanName) {
            cache[key] = itunesURL
            return itunesURL
        }

        misses.insert(key)
        return nil
    }

    func albumImage(artist: String, album: String) async -> URL? {
        let key = "album:\(artist):\(album)"
        if let u = cache[key] { return u }
        if misses.contains(key) { return nil }

        if let detail = try? await LastFM.shared.albumInfo(artist: artist, album: album, user: ""),
           let url = detail.image?.best {
            cache[key] = url
            return url
        }
        misses.insert(key)
        return nil
    }

    private func fetchDeezerArtistImage(_ name: String) async -> URL? {
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.deezer.com/search/artist?q=\(encoded)") else { return nil }
        struct DeezerSearch: Decodable {
            struct DeezerArtist: Decodable {
                let picture_xl: String?
                let picture_big: String?
                let picture_medium: String?
            }
            let data: [DeezerArtist]
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let res = try JSONDecoder().decode(DeezerSearch.self, from: data)
            if let first = res.data.first, let pic = first.picture_xl ?? first.picture_big ?? first.picture_medium {
                return URL(string: pic)
            }
        } catch {}
        return nil
    }

    private func fetchITunesArtistImage(_ name: String) async -> URL? {
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let trackURL = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=song&limit=1") else { return nil }
        struct ITunesSongSearch: Decodable {
            struct ITunesSong: Decodable {
                let artworkUrl100: String?
            }
            let results: [ITunesSong]
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: trackURL)
            let res = try JSONDecoder().decode(ITunesSongSearch.self, from: data)
            if let first = res.results.first, let art = first.artworkUrl100 {
                let highRes = art.replacingOccurrences(of: "100x100bb.jpg", with: "600x600bb.jpg")
                return URL(string: highRes)
            }
        } catch {}
        return nil
    }
}
