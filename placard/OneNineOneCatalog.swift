import Foundation

/// 191壁纸 (191.bz) as a wallpaper source for Placard.
///
/// List: `GET https://191.bz/tendies-wallpaper?current=N&pageSize=10`
/// (server-rendered HTML, 10 items per page, 898 items / 90 pages).
/// Each list page embeds a JSON-LD `ItemList` (name + detail URL) and
/// card markup (format tag, preview gif, description, 免费 badge).
///
/// Downloads are NOT direct links: each detail page carries
/// `tendiesPanShareUrl` (Quark 夸克网盘, pan.quark.cn) and/or
/// `tendiexPanShareUrl` (Baidu 百度网盘, pan.baidu.com), plus a JSON-LD
/// price (`"0.00"` = free). This collection is `.tendiex`-first: the
/// `.tendiex` file (Baidu link) is the standard download. A Quark link
/// only exists for the wallpapers the site uploaded a `.tendies` file
/// for (a minority, mostly free TENDIES items); a `.tendies`-only item
/// has no `.tendiex` file at all — there is no `.tendiex` link to
/// invent for those. Placard cannot download from a pan share link, so
/// installing a 191 wallpaper opens its pan link for the user to
/// download the `.tendiex` file, which is then installed via Browse →
/// Import Wallpaper.
enum OneNineOneAPI {
    nonisolated static let baseURL = URL(string: "https://191.bz")!

    nonisolated static func listURL(page: Int) -> URL {
        baseURL.appending(path: "tendies-wallpaper")
            .appending(queryItems: [
                URLQueryItem(name: "current", value: String(page)),
                URLQueryItem(name: "pageSize", value: "10"),
            ])
    }

    nonisolated static func detailURL(slug: String) -> URL {
        baseURL.appending(path: "tendies-wallpaper/\(slug)")
    }

    /// Resolves a 191 media string to an absolute URL. Absolute strings
    /// pass through untouched; root-relative paths resolve against the
    /// site host.
    nonisolated static func resolve(_ string: String) -> URL {
        if let absolute = URL(string: string), absolute.scheme != nil {
            return absolute
        }
        if let relative = URL(string: string, relativeTo: baseURL)?.absoluteURL {
            return relative
        }
        return baseURL.appending(path: string)
    }
}

/// What a 191 detail page offers for one wallpaper. `tendiexURL` is the
/// `.tendiex` file on Baidu Pan (the standard download); `tendiesURL` is
/// the `.tendies` file on Quark Pan (only some wallpapers have one).
/// Either may be absent. `price` is the JSON-LD price string (`"0.00"`
/// for free wallpapers).
struct OneNineOneDownloadLinks: Sendable {
    let tendiexURL: URL?
    let tendiesURL: URL?
    let price: String?

    var isFree: Bool { price == "0.00" || price == "0" }

    var priceLabel: String? {
        guard let price, !isFree else { return nil }
        return "¥\(price)"
    }
}

enum OneNineOneCatalog: Sendable {
    /// Mirrors the Wallive page walk: 10 items per page, up to 90 pages.
    nonisolated static func fetchAll(refresh: Bool) async throws -> [Wallpaper] {
        var wallpapers: [Wallpaper] = []
        var page = 1
        while page <= 90 {
            let items = try await fetchPage(page, refresh: refresh)
            wallpapers.append(contentsOf: items)
            guard !items.isEmpty else { break }
            page += 1
        }
        return wallpapers
    }

    /// Fetches a 191 detail page and extracts its pan share links.
    nonisolated static func fetchDownloadLinks(for wallpaper: Wallpaper) async throws -> OneNineOneDownloadLinks {
        guard let detailURL = URL(string: wallpaper.url), detailURL.host == "191.bz" else {
            throw CatalogError.invalidResponse
        }
        var request = URLRequest(url: detailURL)
        request.timeoutInterval = 20
        request.cachePolicy = .returnCacheDataElseLoad
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            throw CatalogError.invalidResponse
        }
        let tendies = firstMatch(#"tendiesPanShareUrl:"([^"]+)""#, in: html)
        let tendiex = firstMatch(#"tendiexPanShareUrl:"([^"]+)""#, in: html)
        let price = firstMatch(#""price":"([^"]+)""#, in: html)
        return OneNineOneDownloadLinks(
            tendiexURL: tendiex.flatMap { URL(string: $0) },
            tendiesURL: tendies.flatMap { URL(string: $0) },
            price: price
        )
    }

    private static func fetchPage(_ page: Int, refresh: Bool) async throws -> [Wallpaper] {
        var request = URLRequest(url: OneNineOneAPI.listURL(page: page))
        request.timeoutInterval = 20
        request.cachePolicy = refresh ? .reloadIgnoringLocalCacheData : .returnCacheDataElseLoad
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            throw CatalogError.invalidResponse
        }
        return parseListPage(html)
    }

    /// Parses one list page: the JSON-LD `ItemList` gives the authoritative
    /// (name, detail slug) pairs in order; the card markup adds the format
    /// tag, preview gif, description and 免费 badge. Duplicates between the
    /// JSON-LD block and the embedded page data are merged by slug.
    private static func parseListPage(_ html: String) -> [Wallpaper] {
        var cards: [String: CardInfo] = [:]
        for article in matches(#"<article\b.*?</article>"#, in: html, dotMatchesLineSeparators: true) {
            guard let slug = firstMatch(#"href="/tendies-wallpaper/([^"]+)""#, in: article) else { continue }
            cards[slug] = CardInfo(
                format: firstMatch(#">(TENDIES|TENDIEX)<"#, in: article),
                preview: firstMatch(#"<img src="([^"]+)""#, in: article),
                description: firstMatch(#"<p class="mt-1[^"]*">(.*?)</p>"#, in: article, dotMatchesLineSeparators: true)?
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                isFree: article.contains(">免费</span>")
            )
        }
        var seen: Set<String> = []
        var wallpapers: [Wallpaper] = []
        for match in matches(#""name":"([^"]+)","url":"https://191\.bz/tendies-wallpaper/([^"]+)""#, in: html) {
            guard match.count == 3 else { continue }
            let name = match[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let slug = match[2]
            guard !name.isEmpty, !seen.contains(slug) else { continue }
            seen.insert(slug)
            let card = cards[slug]
            let format = card?.format ?? "TENDIES"
            var descriptionParts: [String] = [format]
            if card?.isFree == true { descriptionParts.append("免费") }
            if let short = card?.description, !short.isEmpty { descriptionParts.append(short) }
            wallpapers.append(Wallpaper(
                remoteID: nil,
                name: name,
                description: descriptionParts.joined(separator: " · "),
                url: OneNineOneAPI.detailURL(slug: slug).absoluteString,
                preview: card?.preview ?? "",
                authors: nil,
                contest: nil,
                source: .oneNineOne
            ))
        }
        return wallpapers
    }

    private struct CardInfo {
        let format: String?
        let preview: String?
        let description: String?
        let isFree: Bool
    }

    private static func firstMatch(_ pattern: String, in text: String, dotMatchesLineSeparators: Bool = false) -> String? {
        matches(pattern, in: text, dotMatchesLineSeparators: dotMatchesLineSeparators).first?.dropFirst().first
    }

    private static func matches(_ pattern: String, in text: String, dotMatchesLineSeparators: Bool = false) -> [[String]] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: dotMatchesLineSeparators ? [.dotMatchesLineSeparators] : []
        ) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            (0..<match.numberOfRanges).map { index in
                let nsRange = match.range(at: index)
                guard nsRange.location != NSNotFound, let range = Range(nsRange, in: text) else { return "" }
                return String(text[range])
            }
        }
    }
}
