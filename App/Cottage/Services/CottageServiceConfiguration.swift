import Foundation

nonisolated enum CottageServiceConfiguration {
    // Public code and artist repository. Artwork is downloaded only when requested.
    static let publicRepository = "Anqui3tas/Cottage"
    static let repositoryBranch = "main"
    static let catalogRefreshInterval: TimeInterval = 60 * 60
    static let aboutURL = URL(string: "https://github.com/Anqui3tas/Cottage")!

    static var catalogURL: URL? {
        let parts = publicRepository.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }),
              !publicRepository.contains(".."),
              publicRepository.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return URL(string: "https://raw.githubusercontent.com")!
            .appending(path: publicRepository)
            .appending(path: repositoryBranch)
            .appending(path: "catalog.json")
    }
}
