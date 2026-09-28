import Foundation

nonisolated enum CottageSharedContainer {
    static let appGroupIdentifier = "group.com.lanteacorp.cottage"

    static var installedPacksDirectory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appending(path: "InstalledPacks", directoryHint: .isDirectory)
    }
}
