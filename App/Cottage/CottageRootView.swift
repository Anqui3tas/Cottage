import SwiftUI

private enum CottageTab: Hashable {
    case artists, explore, library
}

struct CottageRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasEnteredCottage") private var hasEnteredCottage = false
    @State private var selectedTab: CottageTab = .artists
    @State private var store = CottageStore()

    var body: some View {
        Group {
            if hasEnteredCottage {
                TabView(selection: $selectedTab) {
                    Tab("Artists", systemImage: "person.2", value: CottageTab.artists) {
                        ArtistsScreen(entries: store.index.artists)
                    }
                    Tab("Explore", systemImage: "leaf", value: CottageTab.explore) {
                        ExploreScreen(index: store.index)
                    }
                    Tab("Library", systemImage: "books.vertical", value: CottageTab.library) {
                        LibraryScreen { selectedTab = .artists }
                    }
                }
            } else {
                CottageWelcomeScreen { hasEnteredCottage = true }
            }
        }
        .environment(store)
        .task(id: scenePhase) {
            if scenePhase == .active { await store.refresh() }
        }
        .alert("Something needs attention", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

#Preview { CottageRootView() }
