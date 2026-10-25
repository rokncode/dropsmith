<p align="center">
  <img src="Resources/AppIcon.png" width="128" alt="Dropsmith icon">
</p>

<h1 align="center">Dropsmith</h1>

<p align="center">A small drop zone on your Mac desktop. Drop images on it to crop, resize, remove backgrounds, convert and compress them.</p>

## Features

- **Drop zone on the desktop**: a small panel that sits with your desktop icons (or above all windows). Drop one or more images on it to open the editor.
- **Drag targets**: while you drag an image from any app, drop targets appear next to the Dock and under the menu bar icon. Each one can be turned off.
- **Edit**: crop (free or aspect presets), remove background, resize by percent or pixels.
- **Convert**: PNG, JPEG, WebP, AVIF, HEIC, TIFF, GIF, BMP.
- **Compress** (Squoosh-style): quality, lossless and effort settings, a live before/after split view with the real encoded size, and "fit to a target size in KB".
- **Batch**: apply the same edits to every image you dropped.
- **Export** next to the original, to a folder you pick, or to the clipboard. Exports never overwrite: you get `name-edited.png`, `name-edited-2.png`, ...

Planned: strip metadata, rotate/flip, auto-crop to subject, trim transparent edges, screenshot beautify, copy text (OCR), dominant colors, app icon sets, adjustments.

## Install

Download the latest DMG from [Releases](https://github.com/rokncode/dropsmith/releases) and drag Dropsmith to Applications.

Requires **macOS 14** or later. AVIF export needs a macOS version whose ImageIO can encode AVIF.

The app is ad-hoc signed and not notarized, so macOS blocks the first launch. To open it anyway, go to **System Settings → Privacy & Security** and click **Open Anyway**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/Dropsmith.app
```

Dropsmith lives in the menu bar (no Dock icon). If you hide both the menu bar icon and the drop zone, launch the app again (e.g. from Spotlight) to bring them back.

## Build from source

Needs Swift 6.2: Xcode 26, or just the Command Line Tools. Use `make` rather than bare `swift`, since the Makefile handles the Command Line Tools setup.

```sh
make build                     # debug build
make run                       # run without bundling
make test                      # run all tests
make test FILTER=ResizeTests   # run one suite or test
make app                       # release build → build/Dropsmith.app
make dmg VERSION=1.2.3         # app + build/Dropsmith-1.2.3.dmg
make install                   # app + copy to /Applications
```

`Launch at Login` only works in the bundled app (`make app` / `make install`), not under `make run`.

## Project layout

- `Sources/ImageKit`: the image pipeline (operations, rendering, loading, encoding, compression). No UI code, fully unit-tested.
- `Sources/Dropsmith`: the app (drop zone, drag targets, editor).
- `Tests/ImageKitTests`: tests. Test images are generated in code.

To add a quick action, add an `ImageOperation` in `Sources/ImageKit/Operations/` and a button in `InspectorView`. See [CLAUDE.md](CLAUDE.md) for architecture notes.

## License

[MIT](LICENSE). WebP encoding uses [libwebp](https://chromium.googlesource.com/webm/libwebp), which is under the BSD 3-Clause license.
