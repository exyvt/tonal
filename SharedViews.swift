import SwiftUI

struct UserAvatarView: View {
    let url: URL?
    let username: String
    var size: CGFloat = 64

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle()
                        .fill(Theme.gradient)
                    Text(username.prefix(1).uppercased())
                        .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Theme.gradient.opacity(0.6), lineWidth: 2)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
    }
}

struct Chip: View {
    let text: String
    var selected = false

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                selected ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.primary.opacity(0.08)),
                in: Capsule()
            )
            .foregroundStyle(selected ? Color.white : Color.primary)
    }
}

struct BarRow: View {
    let rank: Int
    let title: String
    let subtitle: String
    let value: String
    let fraction: Double

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(value)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.accent)
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                GeometryReader { proxy in
                    Capsule()
                        .fill(Theme.gradient)
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1), height: 4)
                }
                .frame(height: 4)
            }
        }
        .padding(.vertical, 5)
    }
}

struct ArtistArtwork: View {
    let name: String
    var fallback: URL? = nil
    @State private var resolvedURL: URL? = nil

    var body: some View {
        Artwork(url: fallback ?? resolvedURL)
            .overlay {
                if fallback == nil && resolvedURL == nil {
                    ZStack {
                        LinearGradient(colors: [Theme.accent.opacity(0.2), Theme.accent2.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Text(name.prefix(1).uppercased())
                            .font(.title.weight(.bold))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .task(id: name) {
                if fallback == nil {
                    resolvedURL = await LastFMArtworkResolver.shared.artistImage(name)
                }
            }
    }
}

struct ArtistStrip: View {
    let items: [LFItem]
    let subtitle: (LFItem) -> String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                ForEach(items) { item in
                    NavigationLink(value: ArtistRoute(name: item.name)) {
                        VStack(alignment: .leading, spacing: 8) {
                            ArtistArtwork(name: item.name, fallback: item.artworkURL)
                                .frame(width: 108, height: 108)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Theme.gradient.opacity(0.4), lineWidth: 1.5))

                            Text(item.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)

                            let detail = subtitle(item)
                            if !detail.isEmpty {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 120, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct TagRow: View {
    let tags: [Tag]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags) { tag in
                    Chip(text: tag.name)
                }
            }
        }
    }
}

struct AlbumCard: View {
    let item: LFItem
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Artwork(url: item.artworkURL)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.gradient.opacity(0.3), lineWidth: 1))
            Text(item.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
