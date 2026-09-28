import SwiftUI

struct LibraryScreen: View {
    let onExplore: () -> Void
    @Environment(CottageStore.self) private var store
    @State private var packToRemove: CottageInstalledPack?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    CottageSectionHeader(title: "Your little collection", subtitle: "The art you love, ready whenever you are.")
                    if store.installedPacks.isEmpty {
                        ContentUnavailableView {
                            Label("Make yourself at home", systemImage: "books.vertical")
                        } description: {
                            Text("Find an artist you love and add your first free pack.")
                        } actions: {
                            Button("Explore Artists", action: onExplore)
                                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                        }
                    }
                    ForEach(store.installedPacks) { pack in
                        VStack(alignment: .leading, spacing: 10) {
                            NavigationLink {
                                ArtworkDetailScreen(entry: pack.entry)
                            } label: { CottageArtworkRow(entry: pack.entry) }
                            .buttonStyle(.plain)
                            Button("Remove from this device", role: .destructive) { packToRemove = pack }
                                .font(.caption).padding(.horizontal, 12)
                        }
                    }
                    Label("Only the packs you choose take up space. You can remove them and add them again anytime.", systemImage: "internaldrive")
                        .font(.footnote).foregroundStyle(.secondary)
                        .padding(18)
                        .background(CottageTheme.card, in: RoundedRectangle(cornerRadius: 18))
                }
                .padding(20)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(CottageTheme.parchment)
            .navigationTitle("Library")
            .toolbar { CottageAboutToolbarItem() }
            .confirmationDialog("Remove this pack from your device?", isPresented: Binding(
                get: { packToRemove != nil }, set: { if !$0 { packToRemove = nil } }
            ), titleVisibility: .visible) {
                if let packToRemove {
                    Button("Remove Pack", role: .destructive) {
                        Task { await store.remove(packToRemove) }
                    }
                }
                Button("Cancel", role: .cancel) { packToRemove = nil }
            } message: { Text("Copies you've already shared will remain.") }
        }
    }
}

#Preview { LibraryScreen(onExplore: {}).environment(CottageStore()) }
