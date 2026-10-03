import Foundation
import SwiftUI

enum Config {
    static let apiKey = "APIKEY"
    static let apiSecret = "APISECRET"
    static let defaultUsername = ""
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var icon: String {
        switch self {
        case .system: return "laptopcomputer"
        case .light: return "sun.max.fill"
        case .dark: return "moon.stars.fill"
        }
    }
}

enum AccentColorOption: String, CaseIterable, Identifiable {
    case purple = "Violet Pulse"
    case blue = "Ocean Blue"
    case red = "Crimson Flame"
    case gold = "Sunset Gold"
    case emerald = "Neon Emerald"
    case pink = "Cyber Pink"
    case indigo = "Midnight Indigo"
    case lime = "Toxic Lime"
    case amethyst = "Electric Amethyst"
    case cherry = "Cherry Blossom"
    case solar = "Solar Flare"
    case custom = "Custom Color"

    var id: String { rawValue }

    var primary: Color {
        switch self {
        case .purple: return Color(red: 0.65, green: 0.35, blue: 0.95)
        case .blue: return Color(red: 0.15, green: 0.55, blue: 0.98)
        case .red: return Color(red: 0.95, green: 0.25, blue: 0.35)
        case .gold: return Color(red: 0.98, green: 0.65, blue: 0.15)
        case .emerald: return Color(red: 0.10, green: 0.80, blue: 0.55)
        case .pink: return Color(red: 0.98, green: 0.30, blue: 0.65)
        case .indigo: return Color(red: 0.40, green: 0.35, blue: 0.95)
        case .lime: return Color(red: 0.65, green: 0.88, blue: 0.18)
        case .amethyst: return Color(red: 0.55, green: 0.25, blue: 0.88)
        case .cherry: return Color(red: 0.98, green: 0.45, blue: 0.60)
        case .solar: return Color(red: 1.00, green: 0.40, blue: 0.10)
        case .custom: return Color(red: 0.65, green: 0.35, blue: 0.95)
        }
    }

    var secondary: Color {
        switch self {
        case .purple: return Color(red: 0.90, green: 0.40, blue: 0.75)
        case .blue: return Color(red: 0.20, green: 0.80, blue: 0.90)
        case .red: return Color(red: 0.98, green: 0.55, blue: 0.20)
        case .gold: return Color(red: 0.95, green: 0.35, blue: 0.20)
        case .emerald: return Color(red: 0.20, green: 0.85, blue: 0.80)
        case .pink: return Color(red: 0.60, green: 0.25, blue: 0.95)
        case .indigo: return Color(red: 0.75, green: 0.35, blue: 0.95)
        case .lime: return Color(red: 0.20, green: 0.85, blue: 0.40)
        case .amethyst: return Color(red: 0.88, green: 0.40, blue: 0.95)
        case .cherry: return Color(red: 0.98, green: 0.65, blue: 0.80)
        case .solar: return Color(red: 0.98, green: 0.75, blue: 0.20)
        case .custom: return Color(red: 0.90, green: 0.40, blue: 0.75)
        }
    }

    var gradient: LinearGradient {
        LinearGradient(
            colors: [primary, secondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

enum FontStyleOption: String, CaseIterable, Identifiable {
    case rounded = "SF Rounded"
    case system = "Modern Standard"
    case serif = "Serif Classic"
    case monospace = "Monospace Tech"
    case condensed = "Condensed Dynamic"
    case expanded = "Expanded Display"

    var id: String { rawValue }

    var design: Font.Design {
        switch self {
        case .rounded: return .rounded
        case .system: return .default
        case .serif: return .serif
        case .monospace: return .monospaced
        case .condensed: return .default
        case .expanded: return .rounded
        }
    }

    var width: Font.Width {
        switch self {
        case .condensed: return .condensed
        case .expanded: return .expanded
        default: return .standard
        }
    }
}

enum CornerRadiusStyle: String, CaseIterable, Identifiable {
    case extraRounded = "Extra Rounded (22px)"
    case balanced = "Balanced (14px)"
    case sharp = "Minimal Sharp (8px)"

    var id: String { rawValue }

    var value: CGFloat {
        switch self {
        case .extraRounded: return 22
        case .balanced: return 14
        case .sharp: return 8
        }
    }
}

enum GlassStyleOption: String, CaseIterable, Identifiable {
    case vibrant = "Vibrant Glass"
    case clean = "Clean Solid"
    case minimal = "Minimalist"

    var id: String { rawValue }
}

enum DefaultTabOption: String, CaseIterable, Identifiable {
    case stats = "Stats & Facts"
    case history = "History"
    case explore = "Explore"
    case scrobble = "Scrobble"

    var id: String { rawValue }
    var tagIndex: Int {
        switch self {
        case .stats: return 0
        case .history: return 1
        case .explore: return 2
        case .scrobble: return 3
        }
    }
}

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

struct OneOrMany<T: Decodable>: Decodable {
    let items: [T]
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let a = try? c.decode([T].self) { items = a }
        else if let o = try? c.decode(T.self) { items = [o] }
        else { items = [] }
    }
}

struct Box<T: Decodable>: Decodable {
    let items: [T]
    init(from decoder: Decoder) throws {
        var found: [T] = []
        if let c = try? decoder.container(keyedBy: AnyKey.self) {
            for k in c.allKeys where k.stringValue != "@attr" {
                if let v = try? c.decode(OneOrMany<T>.self, forKey: k), !v.items.isEmpty {
                    found = v.items
                    break
                }
            }
        }
        items = found
    }
}

struct Flex: Decodable, Hashable {
    let value: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s }
        else if let i = try? c.decode(Int.self) { value = String(i) }
        else if let d = try? c.decode(Double.self) { value = String(d) }
        else { value = "" }
    }
    var int: Int { Int(value) ?? Int(Double(value) ?? 0) }
}

struct NameRef: Decodable, Hashable {
    let name: String
    init(from decoder: Decoder) throws {
        if let s = try? decoder.singleValueContainer().decode(String.self) {
            name = s
            return
        }
        let c = try decoder.container(keyedBy: AnyKey.self)
        name = (try? c.decode(String.self, forKey: AnyKey("name")))
            ?? (try? c.decode(String.self, forKey: AnyKey("#text")))
            ?? ""
    }
}

struct LFImage: Decodable, Hashable {
    let url: String
    let size: String?
    enum CodingKeys: String, CodingKey { case url = "#text", size }
}

extension Array where Element == LFImage {
    var best: URL? {
        for img in reversed() where !img.url.isEmpty && !img.url.contains("2a96cbd8b46e442fc41c2b86b821562f") {
            return URL(string: img.url)
        }
        return nil
    }
}

struct LFItem: Decodable, Identifiable, Hashable {
    let name: String
    let artist: NameRef?
    let album: NameRef?
    let playcount: Flex?
    let count: Flex?
    let listeners: Flex?
    let duration: Flex?
    let image: [LFImage]?
    let date: DateRef?
    let attr: Attr?

    enum CodingKeys: String, CodingKey {
        case name, artist, album, playcount, count, listeners, duration, image, date
        case attr = "@attr"
    }

    struct DateRef: Decodable, Hashable { let uts: String }
    struct Attr: Decodable, Hashable {
        let nowplaying: Flex?
        let rank: Flex?
    }

    var id: String { "\(name)|\(artist?.name ?? "")|\(date?.uts ?? "")|\(attr?.rank?.value ?? "")" }
    var plays: Int { playcount?.int ?? count?.int ?? 0 }
    var listenerCount: Int { listeners?.int ?? 0 }
    var seconds: Int { duration?.int ?? 0 }
    var rank: Int? { attr?.rank?.int }
    var isNowPlaying: Bool { attr?.nowplaying?.value == "true" }
    var artworkURL: URL? { image?.best }
    var artistName: String { artist?.name ?? "" }
    var albumName: String { album?.name ?? "" }
    var playedAt: Date? { date.flatMap { Double($0.uts) }.map { Date(timeIntervalSince1970: $0) } }
}

struct Tag: Decodable, Hashable, Identifiable {
    let name: String
    let count: Flex?
    var id: String { name }
    var playCount: Int { count?.int ?? 0 }
}

struct Stats: Decodable {
    let listeners: Flex?
    let playcount: Flex?
    let userplaycount: Flex?
}

struct Bio: Decodable {
    let summary: String?
}

struct ArtistDetail: Decodable {
    let name: String
    let image: [LFImage]?
    let stats: Stats?
    let similar: Box<LFItem>?
    let tags: Box<Tag>?
    let bio: Bio?
}

struct AlbumDetail: Decodable {
    let name: String
    let artist: NameRef
    let image: [LFImage]?
    let listeners: Flex?
    let playcount: Flex?
    let userplaycount: Flex?
    let tracks: Box<LFItem>?
    let tags: Box<Tag>?
    let wiki: Bio?
}

struct UserInfo: Decodable {
    let name: String
    let realname: String?
    let playcount: Flex
    let country: String?
    let image: [LFImage]?
    let registered: Registered

    struct Registered: Decodable { let unixtime: Flex }

    var since: Date { Date(timeIntervalSince1970: Double(registered.unixtime.int)) }
    var displayName: String { (realname?.isEmpty == false ? realname : nil) ?? name }
    var avatarURL: URL? { image?.best }
}

enum Period: String, CaseIterable, Identifiable {
    case week = "7day", month = "1month", quarter = "3month", half = "6month", year = "12month", overall

    var id: String { rawValue }
    var label: String {
        switch self {
        case .week: return "7D"
        case .month: return "1M"
        case .quarter: return "3M"
        case .half: return "6M"
        case .year: return "12M"
        case .overall: return "All"
        }
    }
}

enum SearchKind: String, CaseIterable, Identifiable {
    case artists, albums, tracks

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var singular: String { String(rawValue.dropLast()) }
    var method: String { "\(singular).search" }
    var path: [String] { ["results", "\(singular)matches", singular] }
}

struct ArtistRoute: Hashable { let name: String }
struct AlbumRoute: Hashable { let artist: String; let name: String }

extension String {
    var plainText: String {
        var s = replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "Read more on Last.fm", with: "")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Int {
    var compact: String { formatted(.number.notation(.compactName)) }
    var full: String { formatted(.number) }
    var clock: String { String(format: "%d:%02d", self / 60, self % 60) }
}

extension Date {
    var ago: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: self, relativeTo: Date())
    }
}
