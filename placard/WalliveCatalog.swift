import AVFoundation
import CoreImage
import Foundation
import UIKit

/// Wallive (walllive.18ir.cn) as a wallpaper source for Placard.
///
/// The list API and media mapping come from lty5201/wallive-unlock
/// (`Tweak.xm`: `WUFetchPage` / `WUAbsorbPage`), which reads the same
/// public endpoint to resolve a wallpaper id to a direct media link:
/// `GET /api/get_wallpaper.php?page=N` returns
/// `{ code, message, data: [...], hasMore, page, total }`, 10 items per
/// page, each item carrying `id`, `title`, `tag`, `media_type`
/// (`"video"` / `"image"`), `video_url`, `image_url` and `thumb_url`
/// (relative paths are rooted at the API host).
///
/// Wallive serves raw media (mp4 / images), not `.tendies` packages, so
/// installing one goes through Placard's own video-wallpaper pipeline
/// (`VideoWallpaperInstaller`): the mp4 is downloaded, trimmed to the
/// 12-second cap when needed, and its frames become a PosterBoard
/// descriptor. Still images are rendered into a short looping clip first,
/// so every Wallive item is installable the same way.
enum WalliveAPI {
    nonisolated static let baseURL = URL(string: "https://walllive.18ir.cn")!

    nonisolated static func listURL(page: Int) -> URL {
        baseURL.appending(path: "api/get_wallpaper.php")
            .appending(queryItems: [URLQueryItem(name: "page", value: String(page))])
    }

    /// Resolves a Wallive media string to an absolute URL. Absolute
    /// strings pass through untouched; root-relative paths (including
    /// query strings such as `/api/thumb.php?id=…&w=600`) resolve against
    /// the API host without re-encoding the query.
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

private struct WalliveListResponse: Decodable {
    let data: [WalliveItem]
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case data, hasMore
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decodeIfPresent([WalliveItem].self, forKey: .data) ?? []
        hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
    }
}

private struct WalliveItem: Decodable {
    let id: Int
    let title: String?
    let tag: String?
    let mediaType: String?
    let videoURL: String?
    let imageURL: String?
    let thumbURL: String?
    let isVisible: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, tag, imageURL = "image_url", isVisible = "is_visible"
        case mediaType = "media_type", videoURL = "video_url", thumbURL = "thumb_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try? container.decode(Int.self, forKey: .id) {
            self.id = id
        } else if let idString = try? container.decode(String.self, forKey: .id),
                  let id = Int(idString) {
            self.id = id
        } else {
            throw DecodingError.typeMismatch(
                Int.self,
                DecodingError.Context(
                    codingPath: container.codingPath + [CodingKeys.id],
                    debugDescription: "Wallive item id is neither an integer nor a numeric string"
                )
            )
        }
        title = try container.decodeIfPresent(String.self, forKey: .title)
        tag = try container.decodeIfPresent(String.self, forKey: .tag)
        mediaType = try container.decodeIfPresent(String.self, forKey: .mediaType)
        videoURL = try container.decodeIfPresent(String.self, forKey: .videoURL)
        imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
        thumbURL = try container.decodeIfPresent(String.self, forKey: .thumbURL)
        isVisible = try container.decodeIfPresent(Int.self, forKey: .isVisible)
    }

    /// Maps one list item to Placard's catalog model, or nil when the item
    /// is hidden or carries no usable media. `url` keeps the direct media
    /// link (absolute); `preview` keeps the thumbnail path, resolved
    /// against the API host when it is displayed.
    nonisolated var wallpaper: Wallpaper? {
        guard isVisible != 0 else { return nil }
        let mediaString: String
        if mediaType == "video", let videoURL, !videoURL.isEmpty {
            mediaString = videoURL
        } else if let imageURL, !imageURL.isEmpty {
            mediaString = imageURL
        } else {
            return nil
        }
        let previewString: String
        if let thumbURL, !thumbURL.isEmpty {
            previewString = thumbURL
        } else {
            previewString = mediaString
        }
        let name: String
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = title
        } else {
            name = "Wallive #\(id)"
        }
        return Wallpaper(
            remoteID: id,
            name: name,
            description: Self.tagText(tag),
            url: WalliveAPI.resolve(mediaString).absoluteString,
            preview: previewString,
            authors: nil,
            contest: nil,
            source: .wallive
        )
    }

    /// `tag` arrives as a JSON-encoded string array, e.g. `["最新"]`.
    private static func tagText(_ tag: String?) -> String? {
        guard let tag, !tag.isEmpty else { return nil }
        guard tag.hasPrefix("["), let data = tag.data(using: .utf8),
              let tags = try? JSONSerialization.jsonObject(with: data) as? [String],
              !tags.isEmpty else {
            return tag
        }
        return tags.joined(separator: " · ")
    }
}

enum WalliveCatalog: Sendable {
    /// Mirrors the tweak's page walk: 10 items per page, up to 80 pages.
    nonisolated static func fetchAll(refresh: Bool) async throws -> [Wallpaper] {
        var wallpapers: [Wallpaper] = []
        var page = 1
        while page <= 80 {
            let response = try await fetchPage(page, refresh: refresh)
            wallpapers.append(contentsOf: response.data.compactMap(\.wallpaper))
            guard response.hasMore else { break }
            page += 1
        }
        return wallpapers
    }

    private static func fetchPage(_ page: Int, refresh: Bool) async throws -> WalliveListResponse {
        var request = URLRequest(url: WalliveAPI.listURL(page: page))
        request.timeoutInterval = 20
        request.cachePolicy = refresh ? .reloadIgnoringLocalCacheData : .returnCacheDataElseLoad
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200 else {
            throw CatalogError.invalidResponse
        }
        do {
            return try JSONDecoder().decode(WalliveListResponse.self, from: data)
        } catch {
            throw CatalogError.invalidResponse
        }
    }
}

/// Turns a Wallive catalog item's media into a local video file that
/// `VideoWallpaperInstaller` can turn into a PosterBoard descriptor.
enum WalliveVideoPrep {
    /// Same cap as `VideoWallpaperInstaller.maximumDuration`.
    nonisolated static let maximumDuration = 12.0
    /// Trimmed clips stop just short of the cap so float rounding can
    /// never push a 12-second clip over it.
    private nonisolated static let trimmedDuration = 11.9
    /// Still images loop for this long once rendered as video.
    private nonisolated static let stillDuration = 3.0
    private nonisolated static let stillFrameRate = 10
    private nonisolated static let stillSize = CGSize(width: 720, height: 1280)

    private nonisolated static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]
    private nonisolated static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif",
    ]

    /// Downloads the wallpaper's media into `workspace` and returns a
    /// local mp4 (trimmed when the source runs longer than the install
    /// cap, or synthesized from the still image for photo wallpapers).
    nonisolated static func localVideo(
        for wallpaper: Wallpaper,
        in workspace: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let mediaURL = wallpaper.downloadURL
        let ext = mediaURL.pathExtension.lowercased()
        let downloaded: URL
        if videoExtensions.contains(ext) {
            downloaded = workspace.appending(path: "wallive.\(ext)")
            _ = try await WalliveDownloader(destination: downloaded, progress: progress)
                .download(URLRequest(url: mediaURL))
            return try await trimmedVideoIfNeeded(at: downloaded, in: workspace)
        }
        if imageExtensions.contains(ext) {
            downloaded = workspace.appending(path: "wallive.\(ext)")
            _ = try await WalliveDownloader(destination: downloaded, progress: progress)
                .download(URLRequest(url: mediaURL))
            return try await videoFromStillImage(at: downloaded, in: workspace)
        }
        // No telling extension (e.g. a download endpoint): download once,
        // then let the content decide.
        downloaded = workspace.appending(path: "wallive.media")
        _ = try await WalliveDownloader(destination: downloaded, progress: progress)
            .download(URLRequest(url: mediaURL))
        let videoTracks = try? await AVURLAsset(url: downloaded).loadTracks(withMediaType: .video)
        if videoTracks?.isEmpty == false {
            return try await trimmedVideoIfNeeded(at: downloaded, in: workspace)
        }
        return try await videoFromStillImage(at: downloaded, in: workspace)
    }

    private static func trimmedVideoIfNeeded(at url: URL, in workspace: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        guard duration.isFinite, duration > 0 else {
            throw VideoWallpaperError.invalidVideo
        }
        guard duration > maximumDuration else { return url }
        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw VideoWallpaperError.invalidVideo
        }
        let trimmedURL = workspace.appending(path: "wallive-trimmed.mp4")
        session.outputURL = trimmedURL
        session.outputFileType = .mp4
        session.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: trimmedDuration, preferredTimescale: 600)
        )
        try await session.export()
        return trimmedURL
    }

    /// Renders a still image as a short looping clip: the image, aspect
    /// filled to portrait, repeated for `stillDuration` at
    /// `stillFrameRate` fps.
    private static func videoFromStillImage(at url: URL, in workspace: URL) async throws -> URL {
        let data = try Data(contentsOf: url)
        guard let image = UIImage(data: data) else {
            throw VideoWallpaperError.invalidVideo
        }
        let size = stillSize
        let renderer = UIGraphicsImageRenderer(size: size)
        let frameImage = renderer.image { _ in
            let scale = max(size.width / image.size.width, size.height / image.size.height)
            let scaled = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(x: (size.width - scaled.width) / 2, y: (size.height - scaled.height) / 2)
            image.draw(in: CGRect(origin: origin, size: scaled))
        }
        guard let cgImage = frameImage.cgImage else {
            throw VideoWallpaperError.invalidVideo
        }
        let outputURL = workspace.appending(path: "wallive-still.mp4")
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
            ]
        )
        guard writer.canAdd(input) else { throw VideoWallpaperError.invalidVideo }
        writer.add(input)
        guard writer.startWriting() else { throw VideoWallpaperError.invalidVideo }
        writer.startSession(atSourceTime: .zero)
        let frameCount = Int(stillDuration) * stillFrameRate
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(10))
            }
            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                Int(size.width), Int(size.height),
                kCVPixelFormatType_32ARGB,
                nil,
                &pixelBuffer
            )
            guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
                throw VideoWallpaperError.frameEncodingFailed
            }
            CVPixelBufferLockBaseAddress(buffer, [])
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
            guard let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer),
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
            ) else {
                throw VideoWallpaperError.frameEncodingFailed
            }
            context.draw(cgImage, in: CGRect(origin: .zero, size: size))
            let presentationTime = CMTime(
                value: CMTimeValue(frame),
                timescale: CMTimeScale(stillFrameRate)
            )
            guard adaptor.append(buffer, withPresentationTime: presentationTime) else {
                throw VideoWallpaperError.frameEncodingFailed
            }
        }
        input.markAsFinished()
        try await writer.finishWriting()
        return outputURL
    }
}

private final class WalliveDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: @Sendable (Double) -> Void
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<URLResponse, Error>?
    private var fileError: Error?

    init(destination: URL, progress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    func download(_ request: URLRequest) async throws -> URLResponse {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                var request = request
                request.timeoutInterval = 90
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
                self.session = session
                let task = session.downloadTask(with: request)
                self.task = task
                task.resume()
            }
        } onCancel: {
            self.task?.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = min(max(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0), 1)
        progress(fraction)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            fileError = error
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        defer {
            continuation = nil
            self.task = nil
            self.session?.finishTasksAndInvalidate()
            self.session = nil
        }
        if let error {
            continuation?.resume(throwing: error)
        } else if let fileError {
            continuation?.resume(throwing: fileError)
        } else if let response = task.response {
            continuation?.resume(returning: response)
        } else {
            continuation?.resume(throwing: URLError(.badServerResponse))
        }
    }
}
