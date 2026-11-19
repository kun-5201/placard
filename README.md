<p align="center">
  <img src="docs/images/app-icon.png" width="128" alt="Placard app icon">
</p>

# Placard

Browse, create, install, and manage PosterBoard wallpapers on iOS.

- Browse community wallpapers and import `.tendies` packages
- Create video wallpapers from clips up to 12 seconds
- View and delete installed wallpapers
- English and Simplified Chinese

## Support section

The support section is the user's own now: the developer row links
to the user's X ([king9527ya](https://x.com/king9527ya)) and GitHub
([kun-5201](https://github.com/kun-5201)) — no Douyin link — and the
developer avatar is the user's photo. The donation row reads
"感谢 kun - 赞赏码" and shows the user's Alipay QR (generated from
their Alipay collection link, same as Lizi's sponsor row); tapping
the code opens Alipay directly. The old SUSS WeChat donation code
is gone.

## kun

The Browse tab has a kun collection: the full 壁纸匣 catalog from
[zylovehh/wallive-catalog](https://github.com/zylovehh/wallive-catalog)
(`catalog.json`, 186 items: 174 iPhone + 12 iPad), plus 4 files present
in [zylovehh/win97](https://github.com/zylovehh/win97)'s `wallpapers/`
but in neither catalog (aurora-snow, mist-forest, night-mountains,
sunset-sea) — 190 items in total. All of them are direct `.tendies`
downloads, installed through Placard's `.tendies` installer like any
other collection. The catalog is fetched fresh every time the kun tab
opens (with a timestamp cache-buster, the same trick the 壁纸匣 app
uses), so new wallpapers the author adds to the catalog show up in
Placard without an app update. Note the catalog packages are
WALLIVE1-encrypted (HKDF + AES-GCM, see `Wallive1Crypto.swift`, ported
from zylovehh/win97), not plain ZIPs: Placard decrypts them on download
before installing, so they install like any other `.tendies` package.
The catalog also carries a preview video (mp4) for most items: the
detail page plays it muted on a loop over the still thumbnail, so you
see the wallpaper move before installing (items without a preview
video just show the still).

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
