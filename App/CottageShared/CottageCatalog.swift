import Foundation

nonisolated enum CottageMediaKind: String, Codable, CaseIterable, Sendable {
    case wallpaper
    case stickerPack = "sticker_pack"

    var title: LocalizedStringResource {
        switch self {
        case .wallpaper:
            "Wallpapers"
        case .stickerPack:
            "Sticker Packs"
        }
    }

    var symbolName: String {
        switch self {
        case .wallpaper:
            "photo.on.rectangle.angled"
        case .stickerPack:
            "face.smiling.inverse"
        }
    }
}

nonisolated enum CottageCreditRole: String, Codable, Sendable {
    case artist
    case collaborator

    var title: LocalizedStringResource {
        switch self {
        case .artist:
            "Artist"
        case .collaborator:
            "Collaborator"
        }
    }
}

nonisolated struct CottageArtworkCredit: Codable, Hashable, Sendable {
    let artistID: String
    let role: CottageCreditRole
}

nonisolated enum CottageArtistLinkKind: String, Codable, Sendable {
    case website
    case social
    case support

    var title: LocalizedStringResource {
        switch self {
        case .website:
            "Website"
        case .social:
            "Social"
        case .support:
            "Support Artist"
        }
    }

    var symbolName: String {
        switch self {
        case .website:
            "globe"
        case .social:
            "person.2"
        case .support:
            "heart"
        }
    }
}

nonisolated struct CottageArtistLink: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let kind: CottageArtistLinkKind
    let url: URL
}

nonisolated struct CottageArtist: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let slug: String
    let displayName: String
    let handle: String?
    let biography: String?
    let avatarURL: URL?
    let headerURL: URL?
    let links: [CottageArtistLink]
    var usage: String? = nil
}

nonisolated enum CottageDeliveryKind: String, Codable, Sendable {
    case cottage
    case planned
}

nonisolated enum CottageUsageLicense: String, Codable, Sendable {
    case personalUse = "personal_use"
    case artistSpecified = "artist_specified"
    case unspecified

    var title: LocalizedStringResource {
        switch self {
        case .personalUse:
            "Personal use"
        case .artistSpecified:
            "See artist terms"
        case .unspecified:
            "Terms not yet recorded"
        }
    }
}

nonisolated struct CottageMediaFile: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let url: URL
    let sha256: String
}

nonisolated struct CottageArtwork: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let summary: String
    let kind: CottageMediaKind
    let credits: [CottageArtworkCredit]
    let previewURL: URL?
    let deliveryKind: CottageDeliveryKind
    let usageLicense: CottageUsageLicense
    let itemCount: Int?
    var collectionTitle: String? = nil
    var files: [CottageMediaFile]? = nil
}

nonisolated struct CottageCatalog: Codable, Hashable, Sendable {
    let version: Int
    let artists: [CottageArtist]
    let artworks: [CottageArtwork]
}

nonisolated struct CottageArtistEntry: Identifiable, Codable, Hashable, Sendable {
    let artist: CottageArtist
    let artworks: [CottageArtworkEntry]

    var id: String { artist.id }
}

nonisolated struct CottageArtworkEntry: Identifiable, Codable, Hashable, Sendable {
    let artwork: CottageArtwork
    let creditedArtists: [CottageArtist]

    var id: String { artwork.id }
}

nonisolated struct CottageCatalogIndex: Sendable {
    let catalog: CottageCatalog
    let artists: [CottageArtistEntry]
    let artworks: [CottageArtworkEntry]
    let wallpapers: [CottageArtworkEntry]
    let stickerPacks: [CottageArtworkEntry]

    init(catalog: CottageCatalog) {
        let artistByID = Dictionary(uniqueKeysWithValues: catalog.artists.map { ($0.id, $0) })
        let artworkEntries = catalog.artworks.map { artwork in
            CottageArtworkEntry(
                artwork: artwork,
                creditedArtists: artwork.credits.compactMap { artistByID[$0.artistID] }
            )
        }

        var artworkByArtistID: [String: [CottageArtworkEntry]] = [:]
        for entry in artworkEntries {
            for credit in entry.artwork.credits {
                artworkByArtistID[credit.artistID, default: []].append(entry)
            }
        }

        self.catalog = catalog
        self.artworks = artworkEntries
        self.wallpapers = artworkEntries.filter { $0.artwork.kind == .wallpaper }
        self.stickerPacks = artworkEntries.filter { $0.artwork.kind == .stickerPack }
        self.artists = catalog.artists.map { artist in
            CottageArtistEntry(
                artist: artist,
                artworks: artworkByArtistID[artist.id, default: []]
            )
        }
    }
}

nonisolated enum CottageCatalogValidationError: LocalizedError {
    case invalidVersion
    case duplicateArtistID
    case duplicateArtworkID
    case missingCredit(String)
    case invalidFiles
    case missingUsage
    case insecureURL

    var errorDescription: String? {
        switch self {
        case .invalidVersion:
            String(localized: "The catalog version is invalid.")
        case .duplicateArtistID:
            String(localized: "The catalog contains a duplicate artist.")
        case .duplicateArtworkID:
            String(localized: "The catalog contains duplicate artwork.")
        case .missingCredit(let artworkID):
            String(localized: "Artwork \(artworkID) has an invalid artist credit.")
        case .invalidFiles:
            String(localized: "The catalog contains invalid image files.")
        case .missingUsage:
            String(localized: "Downloadable artwork must include artist usage permissions.")
        case .insecureURL:
            String(localized: "The catalog contains a non-secure link.")
        }
    }
}

nonisolated extension CottageCatalog {
    func validated() throws -> CottageCatalog {
        guard version == 1 else {
            throw CottageCatalogValidationError.invalidVersion
        }

        guard Set(artists.map(\.id)).count == artists.count else {
            throw CottageCatalogValidationError.duplicateArtistID
        }

        guard Set(artworks.map(\.id)).count == artworks.count else {
            throw CottageCatalogValidationError.duplicateArtworkID
        }

        let artistIDs = Set(artists.map(\.id))
        for artwork in artworks {
            guard !artwork.credits.isEmpty,
                  artwork.credits.allSatisfy({ artistIDs.contains($0.artistID) }) else {
                throw CottageCatalogValidationError.missingCredit(artwork.id)
            }
        }

        for artwork in artworks where artwork.deliveryKind == .cottage {
            let files = artwork.files ?? []
            guard !files.isEmpty, files.count <= 200,
                  Set(files.map(\.id)).count == files.count,
                  files.allSatisfy({ $0.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil }) else {
                throw CottageCatalogValidationError.invalidFiles
            }
            guard artwork.usageLicense != .unspecified,
                  artwork.credits.allSatisfy({ credit in
                      artists.first(where: { $0.id == credit.artistID })?.usage?
                          .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                  }) else { throw CottageCatalogValidationError.missingUsage }
        }

        let artistURLs = artists.flatMap { artist in
            [artist.avatarURL, artist.headerURL].compactMap { $0 } + artist.links.map(\.url)
        }
        let artworkURLs = artworks.flatMap { artwork in
            [artwork.previewURL].compactMap { $0 } + (artwork.files ?? []).map(\.url)
        }

        guard (artistURLs + artworkURLs).allSatisfy({ $0.scheme == "https" }) else {
            throw CottageCatalogValidationError.insecureURL
        }

        return self
    }
}

nonisolated extension CottageCatalogIndex {
    // The app ships without content; everything comes from the public repository.
    static let empty = CottageCatalogIndex(catalog: CottageCatalog(version: 1, artists: [], artworks: []))
}
