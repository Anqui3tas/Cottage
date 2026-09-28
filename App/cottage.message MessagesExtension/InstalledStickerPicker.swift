import Messages
import SwiftUI

struct CottageMessagesPicker: View {
    let refreshID = UUID()
    @State private var packs: [CottageInstalledPack] = []
    @State private var selectedID: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(packs) { pack in
                        Button { selectedID = pack.id } label: {
                            VStack(spacing: 3) {
                                Text(pack.entry.creditedArtists.map(\.displayName).formatted()).font(.caption.weight(.semibold))
                                Text(pack.entry.artwork.title).font(.caption2)
                            }
                            .padding(10)
                            .background(selectedID == pack.id ? Color.green.opacity(0.15) : Color.clear, in: Capsule())
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
            .buttonStyle(.plain)
            if let pack = packs.first(where: { $0.id == selectedID }) {
                InstalledStickerPicker(pack: pack).id(pack)
            } else {
                ContentUnavailableView(
                    "Your stickers live here",
                    systemImage: "leaf",
                    description: Text("Open The Cottage and add an artist’s pack to use it in Messages.")
                )
            }
        }
        .tint(Color(red: 0.25, green: 0.38, blue: 0.27))
        .task(id: refreshID) {
            packs = ((try? await CottageDownloads.shared.installedPacks()) ?? []).filter { $0.entry.artwork.kind == .stickerPack }
            if !packs.contains(where: { $0.id == selectedID }) { selectedID = packs.first?.id }
        }
    }
}

private struct InstalledStickerPicker: View {
    let pack: CottageInstalledPack
    @State private var stickers: [MSSticker] = []
    @State private var error: String?

    var body: some View {
        Group {
            if let error {
                ContentUnavailableView("Pack Unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                InstalledStickerBrowser(stickers: stickers)
            }
        }
        .task {
            do {
                var prepared: [MSSticker] = []
                for file in pack.entry.artwork.files ?? [] {
                    let url = try await CottageDownloads.shared.stickerURL(for: file, in: pack)
                    prepared.append(try MSSticker(contentsOfFileURL: url, localizedDescription: "\(file.title) — \(pack.entry.creditedArtists.map(\.displayName).formatted())"))
                }
                stickers = prepared
            } catch { self.error = error.localizedDescription }
        }
    }
}

private struct InstalledStickerBrowser: UIViewRepresentable {
    let stickers: [MSSticker]
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> MSStickerBrowserView {
        let view = MSStickerBrowserView(frame: .zero, stickerSize: .regular)
        view.backgroundColor = .clear
        view.dataSource = context.coordinator
        return view
    }
    func updateUIView(_ view: MSStickerBrowserView, context: Context) {
        context.coordinator.stickers = stickers
        view.reloadData()
    }
    final class Coordinator: NSObject, MSStickerBrowserViewDataSource {
        var stickers: [MSSticker] = []
        func numberOfStickers(in stickerBrowserView: MSStickerBrowserView) -> Int { stickers.count }
        func stickerBrowserView(_ stickerBrowserView: MSStickerBrowserView, stickerAt index: Int) -> MSSticker { stickers[index] }
    }
}
