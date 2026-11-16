import AVFoundation
import Foundation
import UIKit
import ZIPFoundation

/// Builds a genuine `.tendies` package from a Wallive video, ported from
/// wallive-unlock's `scripts/make_tendies_offline.py`.
///
/// Wallive wallpapers are `.tendies` packages, not raw videos: the mp4
/// from the list API is the source material, and the installable package
/// is a `LayeredAnimation` descriptor whose background layer plays the
/// video as an 8 fps JPEG frame sequence. That is the same layout the
/// tweak builds, and the same shape as the original layered packages
/// (for example 枯木逢春.tendies, a WWDC22 `Tree Bloom` layered package
/// with no video track at all). The finished package installs through
/// Placard's existing `.tendies` installer, exactly like a downloaded
/// package, so a Wallive install produces a real `.tendies` wallpaper
/// instead of a video descriptor.
enum WalliveTendiesBuilder {
    /// Frames per second of the image sequence, matching the tweak.
    nonisolated static let frameFPS = 8
    /// Frame size, matching the tweak (`720x1565`, iPhone portrait).
    nonisolated static let frameSize = CGSize(width: 720, height: 1565)
    /// JPEG quality for the extracted frames.
    nonisolated static let jpegQuality: CGFloat = 0.8

    /// Builds `<name>.tendies` from the mp4 at `videoURL` into
    /// `workspace`, and returns the package URL. The layout mirrors
    /// `make_tendies_offline.py` exactly: `descriptors/<uuid>/` holding
    /// the provider files, with the wallpaper under
    /// `versions/1/contents/<name>-720w-1565h@3x~iphone.wallpaper/`.
    nonisolated static func build(
        from videoURL: URL,
        wallpaperID: Int,
        name: String,
        in workspace: URL
    ) async throws -> URL {
        let safeName = sanitizedName(name, fallback: "Wallive #\(wallpaperID)")
        let descriptorUUID = UUID().uuidString.uppercased()
        let providerUUID = UUID().uuidString.uppercased()
        let resolution = "720w-1565h@3x~iphone"
        let wallpaperFolder = "\(safeName)-\(resolution).wallpaper"
        let backgroundName = "\(safeName)_Background-\(resolution).ca"
        let floatingName = "\(safeName)_Floating-\(resolution).ca"

        let base = workspace.appending(path: "descriptors/\(descriptorUUID)", directoryHint: .isDirectory)
        let contents = base.appending(path: "versions/1/contents", directoryHint: .isDirectory)
        let wallpaperPath = contents.appending(path: wallpaperFolder, directoryHint: .isDirectory)
        let backgroundPath = wallpaperPath.appending(path: backgroundName, directoryHint: .isDirectory)
        let floatingPath = wallpaperPath.appending(path: floatingName, directoryHint: .isDirectory)
        let backgroundAssets = backgroundPath.appending(path: "assets", directoryHint: .isDirectory)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: backgroundAssets, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: floatingPath, withIntermediateDirectories: true)

        let frameCount = try await extractFrames(from: videoURL, into: backgroundAssets)
        guard frameCount > 0 else { throw VideoWallpaperError.invalidVideo }
        let duration = Double(frameCount) / Double(frameFPS)

        try backgroundCAML(frameCount: frameCount).write(
            to: backgroundPath.appending(path: "main.caml"), atomically: true, encoding: .utf8)
        try indexXML(duration: duration).write(
            to: backgroundPath.appending(path: "index.xml"), atomically: true, encoding: .utf8)
        try emptyAssetManifest().write(
            to: backgroundPath.appending(path: "assetManifest.caml"), atomically: true, encoding: .utf8)
        try emptyCAML().write(
            to: floatingPath.appending(path: "main.caml"), atomically: true, encoding: .utf8)
        try indexXML(duration: duration).write(
            to: floatingPath.appending(path: "index.xml"), atomically: true, encoding: .utf8)
        try emptyAssetManifest().write(
            to: floatingPath.appending(path: "assetManifest.caml"), atomically: true, encoding: .utf8)

        let wallpaperPlist: [String: Any] = [
            "appearanceAware": 1,
            "assets": ["lockAndHome": ["default": [
                "backgroundAnimationFileName": backgroundName,
                "floatingAnimationFileNameKey": floatingName,
                "identifier": wallpaperID,
                "name": safeName,
                "type": "LayeredAnimation",
            ]]],
            "contentVersion": 2.01,
            "family": safeName,
            "identifier": wallpaperID,
            "logicalScreenClass": resolution,
            "name": safeName,
            "preferredProminentColor": ["dark": "#4C9CBC", "default": "#4CA4BC"],
            "version": 1,
        ]
        try writePlist(wallpaperPlist, to: wallpaperPath.appending(path: "Wallpaper.plist"))

        let providerInfo: [String: Any] = ["kConfigurationLastUseDateKey": Date()]
        try writePlist(providerInfo, to: base.appending(path: "providerInfo.plist"))
        try "PRPosterRoleLockScreen".write(
            to: base.appending(path: "com.apple.posterkit.role.identifier"),
            atomically: true, encoding: .utf8)
        try providerUUID.write(
            to: base.appending(path: "com.apple.posterkit.provider.descriptor.identifier"),
            atomically: true, encoding: .utf8)
        let userInfo: [String: Any] = [
            "posterEnvironmentOverrides": Data(base64Encoded: "e30=") ?? Data(),
            "wallpaperRepresentingFileName": wallpaperFolder,
            "wallpaperRepresentingIdentifier": String(wallpaperID),
        ]
        try writePlist(
            userInfo,
            to: base.appending(path: "com.apple.posterkit.provider.contents.userInfo"))

        let packageURL = workspace.appending(path: "\(safeName).tendies")
        try zipDescriptors(in: workspace, to: packageURL)
        return packageURL
    }

    /// Extracts the video's frames at `frameFPS` into `assets` as
    /// `%05d.jpg`, and returns how many frames were written.
    private static func extractFrames(from videoURL: URL, into assets: URL) async throws -> Int {
        let asset = AVURLAsset(url: videoURL)
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        guard duration.isFinite, duration > 0 else { throw VideoWallpaperError.invalidVideo }
        let frameCount = Int(duration * Double(frameFPS))
        guard frameCount > 0 else { throw VideoWallpaperError.invalidVideo }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = frameSize
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        for frame in 0..<frameCount {
            try Task.checkCancellation()
            let time = CMTime(
                value: CMTimeValue(frame),
                timescale: CMTimeScale(frameFPS)
            )
            let cgImage: CGImage
            do {
                cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            } catch {
                throw VideoWallpaperError.frameEncodingFailed
            }
            guard let jpegData = UIImage(cgImage: cgImage).jpegData(compressionQuality: jpegQuality) else {
                throw VideoWallpaperError.frameEncodingFailed
            }
            let frameURL = assets.appending(path: String(format: "%05d.jpg", frame))
            try jpegData.write(to: frameURL, options: .atomic)
        }
        return frameCount
    }

    /// Zips the `descriptors/` tree under `workspace` into `packageURL`,
    /// with entries relative to `workspace` (the tweak zips the same way).
    private static func zipDescriptors(in workspace: URL, to packageURL: URL) throws {
        let fileManager = FileManager.default
        let descriptors = workspace.appending(path: "descriptors", directoryHint: .isDirectory)
        guard let enumerator = fileManager.enumerator(
            at: descriptors,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw VideoWallpaperError.frameEncodingFailed
        }
        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            guard (try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            files.append(fileURL)
        }
        guard !files.isEmpty else { throw VideoWallpaperError.frameEncodingFailed }
        files.sort { $0.path < $1.path }
        let archive = try Archive(url: packageURL, accessMode: .create)
        for fileURL in files {
            let entryPath = fileURL.path.replacingOccurrences(
                of: workspace.path + "/", with: "")
            try archive.addEntry(with: entryPath, fileURL: fileURL, compressionMethod: .deflate)
        }
    }

    private static func writePlist(_ plist: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
    }

    /// Wallpaper names come from the server; keep them usable as file
    /// and folder names.
    private static func sanitizedName(_ name: String, fallback: String) -> String {
        var cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in ["/", "\\", ":", "\0"] {
            cleaned = cleaned.replacingOccurrences(of: separator, with: "_")
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? fallback : cleaned
    }

    private static func backgroundCAML(frameCount: Int) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>view</key>
            <dict>
                <key>backgroundColor</key>
                <string>0 0 0 0</string>
                <key>drawsAsynchronously</key>
                <false/>
                <key>sublayers</key>
                <array>
                    <dict>
                        <key>bounds</key>
                        <string>{{0, 0}, {720, 1565}}</string>
                        <key>contents</key>
                        <dict>
                            <key>initialImage</key>
                            <string>assets/00000.jpg</string>
                            <key>frameDuration</key>
                            <real>0.125000</real>
                            <key>frameCount</key>
                            <integer>\(frameCount)</integer>
                            <key>imageFormat</key>
                            <string>jpg</string>
                            <key>imageNamePattern</key>
                            <string>assets/%05d.jpg</string>
                            <key>loop</key>
                            <true/>
                            <key>type</key>
                            <string>ImageSequence</string>
                        </dict>
                        <key>name</key>
                        <string>ContentLayer</string>
                        <key>position</key>
                        <string>{{0, 0}}</string>
                        <key>type</key>
                        <string>CALayer</string>
                    </dict>
                </array>
            </dict>
        </dict>
        </plist>
        """
    }

    private static func emptyCAML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>view</key>
            <dict>
                <key>backgroundColor</key>
                <string>0 0 0 0</string>
                <key>drawsAsynchronously</key>
                <false/>
                <key>sublayers</key>
                <array/>
            </dict>
        </dict>
        </plist>
        """
    }

    private static func indexXML(duration: Double) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>assetManifest</key><string>assetManifest.caml</string>
        \t<key>documentHeight</key><real>1565</real>
        \t<key>documentResizesToView</key><true/>
        \t<key>documentWidth</key><real>720</real>
        \t<key>dynamicGuidesEnabled</key><true/>
        \t<key>geometryFlipped</key><false/>
        \t<key>guidesEnabled</key><true/>
        \t<key>interactiveMouseEventsEnabled</key><true/>
        \t<key>interactiveShowsCursor</key><true/>
        \t<key>interactiveTouchEventsEnabled</key><false/>
        \t<key>loopEnd</key><real>\(duration)</real>
        \t<key>loopStart</key><real>0.0</real>
        \t<key>loopingEnabled</key><true/>
        \t<key>multitouchDisablesMouse</key><false/>
        \t<key>multitouchEnabled</key><false/>
        </dict>
        </plist>
        """
    }

    private static func emptyAssetManifest() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict/>
        </plist>
        """
    }
}
