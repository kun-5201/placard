import Foundation

enum WallpaperCollection: String, CaseIterable, Identifiable, Sendable {
    case caPlayground
    case nugget
    case apple
    case wallive
    case camlo
    case win97

    var id: Self { self }

    var title: String {
        switch self {
        case .caPlayground: "CAP"
        case .nugget: "Nugget"
        case .apple: "Apple"
        case .wallive: "Wallive"
        case .camlo: "Camlo"
        case .win97: "Win97"
        }
    }
}

enum WallpaperSource: String, Codable, Sendable {
    case nugget
    case caPlayground
    case wallive
    case camlo
    case win97

    nonisolated var assetBaseURL: URL {
        switch self {
        case .nugget: WallpaperCatalog.nuggetAssetBaseURL
        case .caPlayground: WallpaperCatalog.caPlaygroundAssetBaseURL
        case .wallive: WalliveAPI.baseURL
        case .camlo: WallpaperCatalog.camloAssetBaseURL
        case .win97: WallpaperCatalog.win97AssetBaseURL
        }
    }

    nonisolated var packageBaseURL: URL {
        switch self {
        case .nugget: WallpaperCatalog.nuggetPackageBaseURL
        case .caPlayground: WallpaperCatalog.caPlaygroundPackageBaseURL
        case .wallive: WalliveAPI.baseURL
        case .camlo: WallpaperCatalog.camloPackageBaseURL
        case .win97: WallpaperCatalog.win97PackageBaseURL
        }
    }

    nonisolated var directPackageBaseURL: URL {
        switch self {
        case .nugget: URL(string: "https://raw.githubusercontent.com/SerStars/nugget-wallpapers/main/")!
        case .caPlayground: URL(string: "https://raw.githubusercontent.com/CAPlayground/wallpapers/main/")!
        case .wallive: WalliveAPI.baseURL
        case .camlo: URL(string: "https://raw.githubusercontent.com/Kianuni/Camlo/main/")!
        case .win97: URL(string: "https://raw.githubusercontent.com/zylovehh/win97/main/")!
        }
    }
}

enum WallpaperSortOrder: String, CaseIterable, Identifiable, Sendable {
    case random
    case newest
    case oldest

    var id: Self { self }

    var title: String {
        switch self {
        case .random: String(localized: "Random")
        case .newest: String(localized: "Newest")
        case .oldest: String(localized: "Oldest")
        }
    }

    var symbol: String {
        switch self {
        case .random: "shuffle"
        case .newest: "arrow.up"
        case .oldest: "arrow.down"
        }
    }

    /// Reorders the catalog (as-fetched: oldest first) to match this option.
    func apply(to wallpapers: [Wallpaper]) -> [Wallpaper] {
        switch self {
        case .random: wallpapers.shuffled()
        case .newest: wallpapers.reversed()
        case .oldest: wallpapers
        }
    }
}

struct Wallpaper: Codable, Identifiable, Equatable, Sendable {
    let remoteID: Int?
    let name: String
    let description: String?
    let url: String
    let preview: String
    let authors: String?
    let contest: String?
    let source: WallpaperSource

    var id: String { "\(source.rawValue):\(url)" }
    /// Wallive items keep their direct media link (absolute) in `url`,
    /// unlike the catalog sources, whose `url` is a package path relative
    /// to the source's base URL.
    nonisolated var downloadURL: URL {
        if source == .wallive { return WalliveAPI.resolve(url) }
        return source.packageBaseURL.appending(path: url)
    }
    nonisolated var downloadCandidates: [URL] {
        if source == .wallive { return [downloadURL] }
        return [downloadURL, source.directPackageBaseURL.appending(path: url)]
    }
    nonisolated var previewURL: URL {
        if source == .wallive { return WalliveAPI.resolve(preview) }
        return source.assetBaseURL.appending(path: preview)
    }

    enum CodingKeys: String, CodingKey {
        case remoteID = "id"
        case name, description, url, preview, authors, contest, source
    }

    nonisolated init(
        remoteID: Int?,
        name: String,
        description: String?,
        url: String,
        preview: String,
        authors: String?,
        contest: String?,
        source: WallpaperSource
    ) {
        self.remoteID = remoteID
        self.name = name
        self.description = description
        self.url = url
        self.preview = preview
        self.authors = authors
        self.contest = contest
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        remoteID = try container.decodeIfPresent(Int.self, forKey: .remoteID)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        url = try container.decode(String.self, forKey: .url)
        preview = try container.decode(String.self, forKey: .preview)
        authors = try container.decodeIfPresent(String.self, forKey: .authors)
        contest = try container.decodeIfPresent(String.self, forKey: .contest)
        source = try container.decodeIfPresent(WallpaperSource.self, forKey: .source) ?? .nugget
    }

    nonisolated static let placeholder = Wallpaper(
        remoteID: nil,
        name: "Wallpaper",
        description: nil,
        url: "placeholder.tendies",
        preview: "placeholder.png",
        authors: "Author",
        contest: nil,
        source: .nugget
    )

    nonisolated static let previewFixture = Wallpaper(
        remoteID: 1,
        name: "Cipher",
        description: "Decoding…",
        url: "wallpapers/custom/Cipher.tendies",
        preview: "previews/custom/gifs/Cipher.gif",
        authors: "@mightycooldude12",
        contest: "🏆 1st Place",
        source: .nugget
    )
}

struct WallpaperCatalog: Sendable {
    nonisolated static let nuggetAssetBaseURL = URL(string: "https://cdn.jsdmirror.com/gh/SerStars/nugget-wallpapers@main/")!
    nonisolated static let nuggetPackageBaseURL = URL(string: "https://gh-proxy.com/https://raw.githubusercontent.com/SerStars/nugget-wallpapers/main/")!
    nonisolated static let caPlaygroundAssetBaseURL = URL(string: "https://cdn.jsdmirror.com/gh/CAPlayground/wallpapers@main/")!
    nonisolated static let caPlaygroundPackageBaseURL = URL(string: "https://gh-proxy.com/https://raw.githubusercontent.com/CAPlayground/wallpapers/main/")!
    nonisolated static let camloAssetBaseURL = URL(string: "https://cdn.jsdmirror.com/gh/Kianuni/Camlo@main/")!
    nonisolated static let camloPackageBaseURL = URL(string: "https://gh-proxy.com/https://raw.githubusercontent.com/Kianuni/Camlo/main/")!
    nonisolated static let win97AssetBaseURL = URL(string: "https://cdn.jsdmirror.com/gh/zylovehh/win97@main/")!
    nonisolated static let win97PackageBaseURL = URL(string: "https://gh-proxy.com/https://raw.githubusercontent.com/zylovehh/win97/main/")!

    var fetch: @Sendable (WallpaperCollection, CatalogFetchPolicy) async throws -> [Wallpaper]

    static let live = WallpaperCatalog { collection, policy in
        let refresh = policy == .refresh
        switch collection {
        case .nugget:
            let data = try await RemoteAssetCache.shared.data(
                for: nuggetAssetBaseURL.appending(path: "wallpapers-custom.json"),
                refresh: refresh
            )
            return try JSONDecoder().decode([Wallpaper].self, from: data)
        case .apple:
            let data = try await RemoteAssetCache.shared.data(
                for: nuggetAssetBaseURL.appending(path: "wallpapers-apple.json"),
                refresh: refresh
            )
            return try JSONDecoder().decode([Wallpaper].self, from: data)
        case .caPlayground:
            let data = try await RemoteAssetCache.shared.data(
                for: caPlaygroundAssetBaseURL.appending(path: "wallpapers.json"),
                refresh: refresh
            )
            let response = try JSONDecoder().decode(CAPlaygroundCatalogResponse.self, from: data)
            return response.wallpapers
                .sorted { $0.date < $1.date }
                .map(\.wallpaper)
        case .wallive:
            return try await WalliveCatalog.fetchAll(refresh: refresh)
        case .camlo:
            let data = try await RemoteAssetCache.shared.data(
                for: camloAssetBaseURL.appending(path: "wallpapers/catalog.json"),
                refresh: refresh
            )
            let response = try JSONDecoder().decode(CamloCatalogResponse.self, from: data)
            return response.packs.map(\.wallpaper)
        case .win97:
            let data = try await RemoteAssetCache.shared.data(
                for: win97AssetBaseURL.appending(path: "catalog.json"),
                refresh: refresh
            )
            let response = try JSONDecoder().decode(Win97CatalogResponse.self, from: data)
            return response.items.map(\.wallpaper) + Win97CatalogResponse.extras
        }
    }

    static let preview = WallpaperCatalog { _, _ in
        let second = Wallpaper(
            remoteID: 2,
            name: "Rolling Hills",
            description: "boink boink boink",
            url: "wallpapers/custom/RollingHills.tendies",
            preview: "previews/custom/gifs/RollingHills.gif",
            authors: "@i.mes",
            contest: nil,
            source: .nugget
        )
        return [.previewFixture, second]
    }

    static let failingPreview = WallpaperCatalog { _, _ in
        throw CatalogError.invalidResponse
    }
}

private struct CAPlaygroundCatalogResponse: Decodable {
    let wallpapers: [CAPlaygroundWallpaper]
}

private struct CamloCatalogResponse: Decodable {
    let packs: [CamloPack]
}

/// One entry of Kianuni/Camlo `wallpapers/catalog.json`
/// (schemaVersion 1, 60 packs). `packagePath` is a direct `.tendies`
/// path under the repo root, `thumbPath` a preview image, `tagsZh`
/// the Chinese tag list shown in the description.
private struct CamloPack: Decodable {
    let titleZh: String?
    let titleEn: String?
    let subtitleZh: String?
    let badgeZh: String?
    let tagsZh: [String]?
    let packagePath: String
    let thumbPath: String?

    nonisolated var wallpaper: Wallpaper {
        let name: String
        if let titleZh, !titleZh.isEmpty {
            name = titleZh
        } else if let titleEn, !titleEn.isEmpty {
            name = titleEn
        } else {
            name = (packagePath as NSString).lastPathComponent
        }
        var parts: [String] = []
        if let badgeZh, !badgeZh.isEmpty { parts.append(badgeZh) }
        if let tagsZh, !tagsZh.isEmpty { parts.append(tagsZh.joined(separator: " · ")) }
        if let subtitleZh, !subtitleZh.isEmpty { parts.append(subtitleZh) }
        return Wallpaper(
            remoteID: nil,
            name: name,
            description: parts.isEmpty ? nil : parts.joined(separator: " — "),
            url: packagePath,
            preview: thumbPath ?? packagePath,
            authors: nil,
            contest: nil,
            source: .camlo
        )
    }
}

private struct Win97CatalogResponse: Decodable {
    let items: [Win97Item]

    /// Files present in zylovehh/win97 `wallpapers/` but not listed in
    /// the author's catalog.json (2026-11-19). Same layout, thumbnails
    /// live next to the packages.
    nonisolated static let extras: [Wallpaper] = [
        ("极光雪", "wallpapers/aurora-snow.tendies", "wallpapers/aurora-snow-thumb.jpg"),
        ("雾林", "wallpapers/mist-forest.tendies", "wallpapers/mist-forest-thumb.jpg"),
        ("夜山", "wallpapers/night-mountains.tendies", "wallpapers/night-mountains-thumb.jpg"),
        ("日落海", "wallpapers/sunset-sea.tendies", "wallpapers/sunset-sea-thumb.jpg"),
    ].map { name, package, thumb in
        Wallpaper(
            remoteID: nil,
            name: name,
            description: nil,
            url: package,
            preview: thumb,
            authors: nil,
            contest: nil,
            source: .win97
        )
    }
}

/// One entry of zylovehh/win97 `catalog.json` (8 items). `package` and
/// `thumbnail` are absolute raw.githubusercontent URLs; the app only
/// needs the path under the repo root, so the known prefix is stripped.
private struct Win97Item: Decodable {
    let id: String?
    let title: String?
    let tags: [String]?
    let thumbnail: String
    let package: String

    nonisolated var wallpaper: Wallpaper {
        let name: String
        if let title, !title.isEmpty {
            name = title
        } else {
            name = (package as NSString).lastPathComponent
        }
        return Wallpaper(
            remoteID: nil,
            name: name,
            description: tags?.isEmpty == false ? tags!.joined(separator: " · ") : nil,
            url: Self.relativePath(package),
            preview: Self.relativePath(thumbnail),
            authors: nil,
            contest: nil,
            source: .win97
        )
    }

    nonisolated static func relativePath(_ absoluteURL: String) -> String {
        let prefix = "https://raw.githubusercontent.com/zylovehh/win97/main/"
        if absoluteURL.hasPrefix(prefix) {
            return String(absoluteURL.dropFirst(prefix.count))
        }
        return "wallpapers/" + (absoluteURL as NSString).lastPathComponent
    }
}

private struct CAPlaygroundWallpaper: Decodable {
    let name: String
    let creator: String?
    let description: String?
    let file: String
    let preview: String
    let date: Int64

    nonisolated var wallpaper: Wallpaper {
        Wallpaper(
            remoteID: nil,
            name: name,
            description: description,
            url: file,
            preview: preview,
            authors: creator,
            contest: nil,
            source: .caPlayground
        )
    }
}

enum CatalogFetchPolicy: Sendable {
    case cached
    case refresh
}

/// A persistent cache for the catalog and its preview assets. The upstream
/// files are effectively immutable, so normal browsing only goes to the
/// network after URLCache has evicted an item. Explicit refreshes bypass the
/// cached catalog response and replace it after a successful request.
actor RemoteAssetCache {
    nonisolated static let shared = RemoteAssetCache()

    private let cache: URLCache
    private let session: URLSession
    private var inFlight: [URL: Task<Data, Error>] = [:]
    private var activeDownloads = 0
    private var downloadWaiters: [CheckedContinuation<Void, Never>] = []

    init() {
        let cacheDirectory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0].appending(path: "PlacardRemoteAssets", directoryHint: .isDirectory)
        let cache = URLCache(
            memoryCapacity: 48 * 1_024 * 1_024,
            diskCapacity: 512 * 1_024 * 1_024,
            directory: cacheDirectory
        )
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = cache
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.httpMaximumConnectionsPerHost = 4
        self.cache = cache
        self.session = URLSession(configuration: configuration)
    }

    func data(for url: URL, refresh: Bool = false) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        if !refresh, let cached = cache.cachedResponse(for: request) {
            return cached.data
        }
        if let task = inFlight[url] {
            return try await task.value
        }

        request.cachePolicy = .reloadIgnoringLocalCacheData
        let task = Task<Data, Error> {
            try await self.download(request)
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        return try await task.value
    }

    private func download(_ request: URLRequest) async throws -> Data {
        await acquireDownloadSlot()
        defer { releaseDownloadSlot() }

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200 else {
            throw CatalogError.invalidResponse
        }
        cache.storeCachedResponse(
            CachedURLResponse(
                response: response,
                data: data,
                storagePolicy: .allowed
            ),
            for: request
        )
        return data
    }

    private func acquireDownloadSlot() async {
        guard activeDownloads >= 3 else {
            activeDownloads += 1
            return
        }
        await withCheckedContinuation { continuation in
            downloadWaiters.append(continuation)
        }
    }

    private func releaseDownloadSlot() {
        guard !downloadWaiters.isEmpty else {
            activeDownloads -= 1
            return
        }
        downloadWaiters.removeFirst().resume()
    }
}

enum CatalogError: LocalizedError {
    case invalidResponse

    var errorDescription: String? { String(localized: "Wallpapers are currently unavailable. Please try again later.") }
}
