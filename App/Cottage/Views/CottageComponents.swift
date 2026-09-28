import SwiftUI

// Warm paper-and-forest palette, adjusted for dark mode.
enum CottageTheme {
    static let moss = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.66, green: 0.77, blue: 0.61, alpha: 1)
            : UIColor(red: 0.18, green: 0.25, blue: 0.19, alpha: 1)
    })
    static let parchment = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.09, green: 0.11, blue: 0.09, alpha: 1)
            : UIColor(red: 0.97, green: 0.95, blue: 0.91, alpha: 1)
    })
    static let card = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.14, green: 0.17, blue: 0.14, alpha: 1)
            : UIColor(red: 1, green: 0.99, blue: 0.97, alpha: 1)
    })
}

struct CottageWordmark: View {
    var body: some View {
        HStack(spacing: 9) {
            Image("CottageLogo")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 46, height: 38)
                .accessibilityHidden(true)
            Text("The Cottage")
                .font(.system(.title, design: .serif))
        }
        .foregroundStyle(CottageTheme.moss)
        .accessibilityElement(children: .combine)
    }
}

struct CottageWelcomeScreen: View {
    let onExplore: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                CottageWelcomeGarden()
                    .frame(height: 230)
                VStack(spacing: 16) {
                    CottageWordmark()
                        .scaleEffect(1.15)
                        .padding(.bottom, 8)
                    Text("Small stickers.\nBrighter conversations.")
                        .font(.system(.largeTitle, design: .serif))
                        .multilineTextAlignment(.center)
                    Text("A cozy home for independent artists,\nand the little things they create.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("Always free. Always artist first.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(CottageTheme.moss)
                        .padding(.top, 6)
                }
                Button(action: onExplore) {
                    HStack {
                        Text("Explore Artists")
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .padding(.top, 12)
                Text("Good people. Little joys.")
                    .font(.system(.subheadline, design: .serif).italic())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 520)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .background(CottageTheme.parchment)
    }
}

private struct CottageWelcomeGarden: View {
    var body: some View {
        ZStack {
            Circle().fill(CottageTheme.moss.opacity(0.06))
                .frame(width: 220, height: 220)
            Image("CottageLogo")
                .renderingMode(.template)
                .resizable().scaledToFit()
                .frame(width: 140, height: 130)
                .foregroundStyle(CottageTheme.moss)
            Image(systemName: "leaf.fill")
                .font(.system(size: 44)).rotationEffect(.degrees(-28))
                .offset(x: -118, y: -50)
            Image(systemName: "leaf")
                .font(.system(size: 54)).rotationEffect(.degrees(32))
                .offset(x: 110, y: 70)
            Image(systemName: "sparkles")
                .font(.system(size: 30)).offset(x: 112, y: -78)
            Image(systemName: "heart")
                .font(.system(size: 28)).rotationEffect(.degrees(-12))
                .offset(x: -105, y: 89)
        }
        .foregroundStyle(CottageTheme.moss.opacity(0.65))
        .accessibilityHidden(true)
    }
}

struct CottageSectionHeader: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(.title2, design: .serif).weight(.semibold))
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CottageArtistAvatar: View {
    let artist: CottageArtist
    let size: CGFloat

    var body: some View {
        CottageRemoteImage(url: artist.avatarURL ?? artist.headerURL, symbol: "leaf")
            .frame(width: size, height: size)
            .clipShape(Circle())
            .accessibilityLabel(Text("Artwork by \(artist.displayName)"))
    }
}

struct CottageArtworkPreview: View {
    @Environment(CottageStore.self) private var store
    let artwork: CottageArtwork
    let cornerRadius: CGFloat

    private var previewURL: URL? {
        if let pack = store.installedPacks.first(where: { $0.id == artwork.id }),
           let file = pack.entry.artwork.files?.first {
            return pack.fileURL(for: file)
        }
        return artwork.previewURL
    }

    var body: some View {
        CottageRemoteImage(url: previewURL, symbol: artwork.kind.symbolName, fit: artwork.kind == .stickerPack)
        .background(CottageTheme.moss.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .accessibilityLabel(Text("Preview of \(artwork.title)"))
    }
}

struct CottageArtworkByline: View {
    let artists: [CottageArtist]
    var body: some View {
        Text("by \(artists.map(\.displayName).formatted())")
            .foregroundStyle(CottageTheme.moss)
    }
}

struct CottageArtworkRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let entry: CottageArtworkEntry
    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(spacing: 14))
        layout {
            CottageArtworkPreview(artwork: entry.artwork, cornerRadius: 14)
                .frame(width: 84, height: 92)
            VStack(alignment: .leading, spacing: 5) {
                if let collection = entry.artwork.collectionTitle {
                    Text(collection).font(.caption).foregroundStyle(.secondary)
                }
                Text(entry.artwork.title).font(.system(.headline, design: .serif))
                CottageArtworkByline(artists: entry.creditedArtists).font(.caption)
                if let count = entry.artwork.itemCount {
                    Text("^[\(count) image](inflect: true)").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(12)
        .foregroundStyle(.primary)
        .background(CottageTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .contentShape(.rect)
    }
}

struct CottageAboutToolbarItem: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink { CottageAboutScreen() } label: {
                Label("About The Cottage", systemImage: "gearshape")
            }
        }
    }
}

struct CottageAboutScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                CottageWordmark()
                CottageSectionHeader(title: "A little art. A little joy.", subtitle: "Free to download. Free to use. No paid packs or artist submission fees.")
                CottageSectionHeader(title: "Made by artists", subtitle: "Artwork belongs to its artists and rights holders. Please follow each artist's usage permissions and keep their credit attached.")
                CottageSectionHeader(title: "Saved for you", subtitle: "Only the packs you add are stored on your device. Open The Cottage to check for new collections and updates.")
                CottageSectionHeader(title: "Respecting artists", subtitle: "Valid DMCA takedown notices will be honored. Removed artwork is cleared from this app on the next successful catalog update; copies already shared cannot be recalled.")
                Link("About The Cottage", destination: CottageServiceConfiguration.aboutURL)
            }
            .padding(24)
        }
        .background(CottageTheme.parchment)
        .navigationTitle("The Cottage")
        .navigationBarTitleDisplayMode(.inline)
    }
}
