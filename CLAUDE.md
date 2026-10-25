# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Product

A native macOS app (Swift, SwiftUI + AppKit; the only third-party code is libwebp) that puts a small **drop zone on the desktop**. Dropping images on it opens an editor window.

- **Built:**
  - crop (free + aspect presets), remove background, resize (percent / pixels)
  - convert to PNG, JPEG, WebP, AVIF, HEIC, TIFF, GIF or BMP
  - Squoosh-style compression: quality/lossless/effort, live before/after split view with the real encoded size, fit to a target size in KB
  - batch-apply edits to every dropped image
  - export next to the original, to a chosen folder, or to the clipboard
  - drop targets near the Dock and under the menu bar that appear while dragging an image from anywhere (each optional)
- **Planned quick actions:** strip metadata, rotate/flip, auto-crop to subject (Vision saliency), trim transparent edges, screenshot beautify (padding/rounded corners/shadow), copy text (OCR), dominant colors, app icon set, grayscale/adjustments
- Exports never overwrite: `OutputNaming` produces `name-edited.ext`, `name-edited-2.ext`, ...

## Commands

Use `make`, not bare `swift`. The Makefile sets `SDKROOT` when only the Command Line Tools are installed (see Toolchain).

```sh
make build                     # debug build
make run                       # run unbundled (agent policy is set in code, so no Dock icon)
make test                      # all tests
make test FILTER=ResizeTests   # one suite or test (passed to `swift test --filter`)
make app                       # release build → build/Dropsmith.app (ad-hoc signed, LSUIElement)
make dmg VERSION=1.2.3         # make app + build/Dropsmith-1.2.3.dmg (VERSION defaults to 0.1.0)
make install                   # make app + copy to /Applications (so Spotlight can relaunch it)
```

**Releases:** pushing a `v*` tag runs `.github/workflows/release.yml` on `macos-26` (Xcode 26, needed for Swift 6.2). It runs the tests, then `make dmg`, then publishes a GitHub release with the DMG. The app is ad-hoc signed and not notarized, so Gatekeeper blocks the first launch. The release notes explain how to open it anyway.

`Launch at Login` (SMAppService) only appears and works in the bundled `.app`, not under `make run`.

The app icon is `Resources/AppIcon.png`, a 1024px master with the standard macOS padding already in it (shape 824px, centered). `scripts/bundle.sh` turns it into `AppIcon.icns` with `sips` + `iconutil`. To replace it, keep that padding, or the icon will look oversized next to other apps.

## Toolchain quirks (Command Line Tools only, no Xcode)

- **macOS 27 SDK + CLT can't compile SwiftUI `@State`.** In that SDK `@State` is a macro whose `SwiftUIMacros` plugin ships only with Xcode. The Makefile builds against `MacOSX26.sdk` instead, and only when `xcode-select -p` is the CLT. Bare `swift build` fails with "plugin for module 'SwiftUIMacros' not found".
- **Swift Testing under CLT** needs the macro plugin path and runtime rpaths. These are set as `unsafeFlags` on the test target in `Package.swift`. Don't remove them. Passing linker flags on the `swift test` command line instead breaks macro resolution.
- SwiftPM uses the new Swift Build backend (`.build/out/...`). `--build-system native` cannot find `Testing` here.
- ImageIO can't encode WebP, so WebP goes through **libwebp** (`SDWebImage/libwebp-Xcode`, pinned `exact: "1.6.0"`). It is compiled from C source and linked statically, so there's no Homebrew dylib dependency. All other formats use ImageIO, and `ImageFormat.writable` filters them by `CGImageDestinationCopyTypeIdentifiers()` (AVIF encoding needs a recent macOS).

## Architecture

Two targets: **`ImageKit`** (pure image pipeline, no UI imports, all unit-tested) and **`Dropsmith`** (the app).

**The "widget" is not WidgetKit.** WidgetKit widgets can't receive drops. `DropZoneController` owns a borderless, non-activating `NSPanel` at `desktopIconWindow + 1` (or `.floating` when "Keep Drop Zone Above Windows" is on), on all Spaces, with its frame autosaved. Menu toggles write `UserDefaults` via `@AppStorage`. The controller watches `UserDefaults.didChangeNotification` and applies them, so the menu and the panel stay decoupled.

**Drag targets** (`DragTargetsController`): a global `.leftMouseDragged` monitor (no Accessibility permission needed) watches `NSPasteboard(name: .drag).changeCount`. When a new drag carries images, it shows `.popUpMenu`-level capsule panels next to the Dock (side found from `visibleFrame` vs `frame`) and under the menu bar icon (found via the `NSStatusBarWindow`, since `MenuBarExtra` hides its `NSStatusItem`). The drag loop runs in the source app, so release is detected by polling `NSEvent.pressedMouseButtons`, then the panels hide after 400 ms so a drop can land. Toggles: `dragTargetNearDock`, `dragTargetUnderMenuBar`. Both targets and the drop zone share the `onImageDrop` modifier.

**Staying reachable:**
- The menu bar icon can be hidden (`MenuBarExtra(isInserted:)`, key `menuBarIconVisible`).
- `AppMenu` is shared by the icon and the drop zone's right-click menu, so settings and Quit always have a home.
- If both are hidden, `applicationShouldHandleReopen` restores them when the app is launched again. Visibility changes go through `AppDelegate.setMenuBarIconVisible` / `setDropZoneVisible`, which show the how-to-get-back alert.
- From a shell: `defaults write dev.dropsmith.Dropsmith menuBarIconVisible -bool true`, then relaunch.

**Drop → editor flow:**

1. `DropLoader` turns `NSItemProvider`s into `SourceImage`s. Raw image data (e.g. from a browser) is written to a temp file first, so everything downstream works from a file URL.
2. `EditorWindowManager` opens one window per drop, each with its own `EditSession`.

**`ImageOperation`** (`apply(to: CIImage) async throws -> CIImage`, `Sendable` value types) is the extension point. To add a quick action, add a type in `Sources/ImageKit/Operations/` and a button in `InspectorView`. Conventions:

- Return images normalized to a (0, 0) origin (`CIImage.normalized`).
- `Crop` takes a **normalized, top-left-origin** rect, the same space as the SwiftUI `CropOverlay`. That makes one crop apply proportionally across a batch. The drag math lives in `CropGeometry` (ImageKit) so it's testable.
- Resize with "keep aspect" uses `.fit`, not `.exact`, so batch images with other shapes aren't stretched.

**`EditSession`** (`@MainActor @Observable`) keeps two parallel stacks:

- `operations`: the recipe
- `history`: a rendered `CGImage` after each step, for the selected image only

Applying an op renders from the last baked `CGImage`, so undo is a pop and Vision never reruns. Switching images in a batch replays the recipe (`renderSteps`). Batch export re-runs `Pipeline` per source but reuses the baked image for the selected one. Heavy work runs in `@concurrent nonisolated static` helpers.

Compare mode (`CompareView`) shows the current image next to the same image decoded from the actual encoded bytes. `EditorView` runs `.task(id: session.compressionKey)`. The key covers the compare flag, format, options and a `revision` counter that bumps on every `history` change. That task cancels and restarts on each change, and the 250 ms sleep in `refreshComparison` doubles as a slider debounce. The "Original file" size reads the source file with symlinks resolved.

**Rendering/IO:**

- One shared `Renderer.context` (`CIContext`) renders to RGBA8 and falls back to sRGB for non-RGB sources.
- `ImageLoader` applies EXIF orientation.
- `ImageExporter` works in two stages:
  - `prepare` renders once, flattening onto white for formats without alpha (JPEG/BMP)
  - `encode(CGImage, format, EncodeOptions)` is called repeatedly for previews and size fitting
  - metadata is **not** carried over
- `WebPEncoder` uses libwebp's advanced API (`method` = effort). libwebp needs *straight* RGBA, so it draws premultiplied via CGContext and divides alpha out by hand. Core Image's `unpremultiplyingAlpha()` does **not** work for this: CI re-premultiplies bitmap output. A lossless round-trip test guards it.
- `Compressor.fit` binary-searches quality for a max byte count and returns nil when even quality 0 is too big. Size ranges differ a lot per encoder (WebP's is narrow on noisy images).
- `RemoveBackground` uses `VNGenerateForegroundInstanceMaskRequest` + `CIBlendWithMask`, which is why the minimum is macOS 14. Applying it auto-switches a non-alpha export format to PNG.

**Tests** generate images in code (`Tests/ImageKitTests/Helpers.swift`). The background-removal test uses `/Library/User Pictures/Animals/Parrot.heic` and is skipped if that file is missing.

**Not sandboxed**, because exporting next to the original requires it. Sandboxing later means security-scoped bookmarks or `NSSavePanel`.
