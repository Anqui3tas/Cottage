import SwiftUI

@main
struct CottageApp: App {
    init() {
        URLCache.shared = URLCache(memoryCapacity: 16_000_000, diskCapacity: 80_000_000)
    }

    var body: some Scene {
        WindowGroup {
            CottageRootView()
                .tint(CottageTheme.moss)
        }
    }
}
