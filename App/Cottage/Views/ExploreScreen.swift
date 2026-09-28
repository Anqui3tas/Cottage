import SwiftUI

struct ExploreScreen: View {
    @Environment(CottageStore.self) private var store
    let index: CottageCatalogIndex

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 28) {
                    ExploreIntroduction()
                    ArtworkShelf(
                        title: CottageMediaKind.wallpaper.title,
                        subtitle: "Downloadable art for the screens you use every day.",
                        entries: index.wallpapers
                    )
                    ArtworkShelf(
                        title: CottageMediaKind.stickerPack.title,
                        subtitle: "Install a pack, then use it from Messages.",
                        entries: index.stickerPacks
                    )
                }
                .padding()
            }
            .refreshable { await store.refresh(force: true) }
            .background(CottageTheme.parchment)
            .navigationTitle("Explore")
            .toolbar {
                CottageAboutToolbarItem()
            }
        }
    }
}

private struct ExploreIntroduction: View {
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(CottageTheme.moss)
                .frame(width: 48, height: 48)
                .background(CottageTheme.moss.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text("Find your next little joy")
                    .font(.system(.title2, design: .serif))

                Text("Free collections, with the artists who made them always close by.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(CottageTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct ArtworkShelf: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let entries: [CottageArtworkEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CottageSectionHeader(title: title, subtitle: subtitle)

            if entries.isEmpty {
                ContentUnavailableView(
                    "Coming Soon",
                    systemImage: "shippingbox",
                    description: Text("The first reviewed collection is being prepared.")
                )
                .frame(minHeight: 220)
            } else {
                ForEach(entries) { entry in
                    NavigationLink {
                        ArtworkDetailScreen(entry: entry)
                    } label: {
                        CottageArtworkRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#Preview {
    ExploreScreen(index: .empty).environment(CottageStore())
}
