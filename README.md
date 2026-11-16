<p align="center">
  <img src="docs/images/app-icon.png" width="128" alt="Placard app icon">
</p>

# Placard

Browse, create, install, and manage PosterBoard wallpapers on iOS.

- Browse community wallpapers and import `.tendies` packages
- Browse Wallive wallpapers and install them directly (video and stills)
- Create video wallpapers from clips up to 12 seconds
- View and delete installed wallpapers
- English and Simplified Chinese

## Wallive

The Browse tab has a Wallive collection backed by the public list API
at `walllive.18ir.cn/api/get_wallpaper.php`. Wallive serves raw media
(mp4 / images) rather than `.tendies` packages, so installing one
downloads the media on-device, trims clips longer than 12 seconds, and
renders still images into a short looping clip, then installs it through
the same video-wallpaper pipeline as the Create tab. The API mapping
follows [lty5201/wallive-unlock](https://github.com/lty5201/wallive-unlock),
which resolves the same endpoint to direct media links and builds
`.tendies` packages from them.

<p align="center">
  <img src="docs/images/browse-custom.png" width="360" alt="Wallpaper browser">
</p>

## Build

Requires Xcode 26+, iOS 26+, and a physical device compatible with `worse_query`.

Open `placard.xcodeproj`, select your signing team, and enable the App Group `group.$(PRODUCT_BUNDLE_IDENTIFIER)` in your provisioning profile. Build and run on your device.

## Credits

- [Pocket Poster](https://github.com/leminlimez/Pocket-Poster) — wallpaper workflow
- [GestaltEdit](https://github.com/frs0n/GestaltEdit) / [worse_query](https://github.com/forcequitOS/worse_query) — file access
- [nugget-wallpapers](https://github.com/SerStars/nugget-wallpapers) / [wallpapers](https://github.com/CAPlayground/wallpapers) — community catalog
- [NeoSpring](https://github.com/rooootdev/neospring) — SpringBoard refresh
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) — archive handling

Wallpaper artwork belongs to its creators.

## License

[GPL-3.0](LICENSE). Incorporated code retains its upstream license.
