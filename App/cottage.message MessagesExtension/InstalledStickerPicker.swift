import Messages
import Observation
import SwiftUI

// Shared with the view controller so presentation changes don't reload stickers.
@MainActor @Observable
final class CottageMessagesState {
    var isExpanded = false
    var reloadID = UUID()
}

private struct ArtistShelf: Identifiable {
    let artist: CottageArtist
    let collections: [StickerCollection]
    var id: String { artist.id }
}

private struct StickerCollection: Identifiable {
    let title: String
    var packs: [CottageInstalledPack]
    var id: String { title }
}

struct CottageMessagesPicker: View {
    let state: CottageMessagesState
    @State private var shelves: [ArtistShelf] = []
    @State private var selectedID: String?

    var body: some View {
        VStack(spacing: 0) {
            if let shelf = shelves.first(where: { $0.id == selectedID }) {
                ArtistTabs(shelves: shelves, selectedID: $selectedID)
                ArtistStickers(shelf: shelf, isExpanded: state.isExpanded).id(shelf.id)
            } else {
                ContentUnavailableView(
                    "Your stickers live here",
                    systemImage: "leaf",
                    description: Text("Open The Cottage and add an artist’s pack to use it in Messages.")
                )
            }
        }
        .tint(Color(red: 0.25, green: 0.38, blue: 0.27))
        .task(id: state.reloadID) {
            let packs = ((try? await CottageDownloads.shared.installedPacks()) ?? [])
                .filter { $0.entry.artwork.kind == .stickerPack }
            shelves = Self.shelves(from: packs)
            if !shelves.contains(where: { $0.id == selectedID }) { selectedID = shelves.first?.id }
        }
    }

    // Artist → collection → pack, in the artist's folder order.
    private static func shelves(from packs: [CottageInstalledPack]) -> [ArtistShelf] {
        let byArtist = Dictionary(grouping: packs.filter { !$0.entry.creditedArtists.isEmpty }) {
            $0.entry.creditedArtists[0].id
        }
        return byArtist.values.compactMap { packs -> ArtistShelf? in
            guard let artist = packs.first?.entry.creditedArtists.first else { return nil }
            let sorted = packs.sorted {
                ($0.entry.artwork.order ?? .max, $0.entry.artwork.title) < ($1.entry.artwork.order ?? .max, $1.entry.artwork.title)
            }
            var collections: [StickerCollection] = []
            for pack in sorted {
                let title = pack.entry.artwork.collectionTitle ?? ""
                if let index = collections.firstIndex(where: { $0.title == title }) {
                    collections[index].packs.append(pack)
                } else {
                    collections.append(StickerCollection(title: title, packs: [pack]))
                }
            }
            return ArtistShelf(artist: artist, collections: collections)
        }
        .sorted { $0.artist.displayName.localizedStandardCompare($1.artist.displayName) == .orderedAscending }
    }
}

private struct ArtistTabs: View {
    let shelves: [ArtistShelf]
    @Binding var selectedID: String?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(shelves) { shelf in
                    Button { selectedID = shelf.id } label: {
                        Text(shelf.artist.displayName)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(selectedID == shelf.id ? Color.green.opacity(0.15) : Color.clear, in: Capsule())
                    }
                    .accessibilityAddTraits(selectedID == shelf.id ? .isSelected : [])
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
        .buttonStyle(.plain)
    }
}

private struct ArtistStickers: View {
    let shelf: ArtistShelf
    let isExpanded: Bool
    @State private var stickers: [String: [MSSticker]] = [:]

    private var packs: [CottageInstalledPack] { shelf.collections.flatMap(\.packs) }

    var body: some View {
        Group {
            if isExpanded {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(shelf.collections) { collection in
                            Text(collection.title).font(.system(.title3, design: .serif).weight(.semibold))
                            ForEach(collection.packs) { pack in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(pack.entry.artwork.title).font(.subheadline).foregroundStyle(.secondary)
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 10)], spacing: 10) {
                                        ForEach(stickers[pack.id] ?? [], id: \.imageFileURL) { sticker in
                                            Color.clear.aspectRatio(1, contentMode: .fit)
                                                .overlay { StickerCell(sticker: sticker) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            } else {
                GeometryReader { geometry in
                    // Two rows that fill the compact height.
                    let side = max(48, (geometry.size.height - 44) / 2)
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 22) {
                            ForEach(packs) { pack in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(Self.label(for: pack))
                                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    LazyHGrid(rows: Array(repeating: GridItem(.fixed(side), spacing: 8), count: 2), spacing: 8) {
                                        ForEach(stickers[pack.id] ?? [], id: \.imageFileURL) { sticker in
                                            StickerCell(sticker: sticker).frame(width: side, height: side)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .task {
            for pack in packs where stickers[pack.id] == nil {
                stickers[pack.id] = await Self.load(pack)
            }
        }
    }

    private static func label(for pack: CottageInstalledPack) -> String {
        [pack.entry.artwork.collectionTitle, pack.entry.artwork.title]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // Packs that fail to prepare are left empty rather than blocking the rest.
    private static func load(_ pack: CottageInstalledPack) async -> [MSSticker] {
        let credit = pack.entry.creditedArtists.map(\.displayName).formatted()
        var loaded: [MSSticker] = []
        for file in pack.entry.artwork.files ?? [] {
            guard let url = try? await CottageDownloads.shared.stickerURL(for: file, in: pack),
                  let sticker = try? MSSticker(contentsOfFileURL: url, localizedDescription: "\(file.title) — \(credit)") else { continue }
            loaded.append(sticker)
        }
        return loaded
    }
}

// MSStickerView keeps Messages' tap-to-send and peel-and-place behavior.
// It draws at the size it has when the sticker is set, so it is rebuilt whenever
// SwiftUI gives it a new size instead of being created at zero size.
private struct StickerCell: UIViewRepresentable {
    let sticker: MSSticker

    func makeUIView(context: Context) -> StickerContainer {
        StickerContainer()
    }

    func updateUIView(_ view: StickerContainer, context: Context) {
        view.sticker = sticker
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: StickerContainer, context: Context) -> CGSize? {
        let side = min(proposal.width ?? 80, proposal.height ?? proposal.width ?? 80)
        return CGSize(width: side, height: side)
    }
}

final class StickerContainer: UIView {
    private var stickerView: MSStickerView?
    private var renderedSize: CGSize = .zero

    var sticker: MSSticker? {
        didSet {
            if sticker !== oldValue { rebuild() }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != renderedSize { rebuild() }
    }

    private func rebuild() {
        stickerView?.removeFromSuperview()
        stickerView = nil
        renderedSize = bounds.size
        guard let sticker, bounds.width > 0, bounds.height > 0 else { return }
        let view = MSStickerView(frame: bounds, sticker: sticker)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(view)
        stickerView = view
    }
}
