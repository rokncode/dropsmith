# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Product

A native macOS app (Swift, SwiftUI + AppKit, no third-party image libraries) that puts a small **drop zone on the desktop**. Dropping images on it opens an editor window.

- **Built:** crop (free + aspect presets), remove background, resize (percent / pixels), convert format, batch-apply edits to every dropped image, export next to the original, to a chosen folder, or to the clipboard
- **Planned quick actions:** compress to target size, strip metadata, rotate/flip, auto-crop to subject (Vision saliency), trim transparent edges, screenshot beautify (padding/rounded corners/shadow), copy text (OCR), dominant colors, app icon set, grayscale/adjustments
- Exports never overwrite: `OutputNaming` produces `name-edited.ext`, `name-edited-2.ext`, ...

## Commands

Use `make`, not bare `swift`. The Makefile sets `SDKROOT` when only the Command Line Tools are installed (see Toolchain).

```sh
make build                     # debug build
make run                       # run unbundled (agent policy is set in code, so no Dock icon)
make test                      # all tests
make test FILTER=ResizeTests   # one suite or test (passed to `swift test --filter`)
make app                       # release build → build/DesktopEdit.app (ad-hoc signed, LSUIElement)
```

`Launch at Login` (SMAppService) only appears and works in the bundled `.app`, not under `make run`.

## Toolchain quirks (Command Line Tools only, no Xcode)

- **macOS 27 SDK + CLT can't compile SwiftUI `@State`.** In that SDK `@State` is a macro whose `SwiftUIMacros` plugin ships only with Xcode. The Makefile builds against `MacOSX26.sdk` instead, and only when `xcode-select -p` is the CLT. Bare `swift build` fails with "plugin for module 'SwiftUIMacros' not found".
- **Swift Testing under CLT** needs the macro plugin path and runtime rpaths. These are set as `unsafeFlags` on the test target in `Package.swift`. Don't remove them. Passing linker flags on the `swift test` command line instead breaks macro resolution.
- SwiftPM uses the new Swift Build backend (`.build/out/...`). `--build-system native` cannot find `Testing` here.
- ImageIO on this machine cannot encode WebP. `ImageFormat.writable` filters by `CGImageDestinationCopyTypeIdentifiers()`, so the UI only offers formats that work.

## Architecture

Two targets: **`ImageKit`** (pure image pipeline, no UI imports, all unit-tested) and **`DesktopEdit`** (the app).

**The "widget" is not WidgetKit.** WidgetKit widgets can't receive drops. `DropZoneController` owns a borderless, non-activating `NSPanel` at `desktopIconWindow + 1` (or `.floating` when "Keep Drop Zone Above Windows" is on), on all Spaces, with its frame autosaved. Menu toggles write `UserDefaults` via `@AppStorage`. The controller watches `UserDefaults.didChangeNotification` and applies them, so the menu and the panel stay decoupled.

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

**Rendering/IO:**

- One shared `Renderer.context` (`CIContext`) renders to RGBA8 and falls back to sRGB for non-RGB sources.
- `ImageLoader` applies EXIF orientation.
- `ImageExporter` flattens onto white for formats without alpha (JPEG/BMP) and does **not** carry over metadata.
- `RemoveBackground` uses `VNGenerateForegroundInstanceMaskRequest` + `CIBlendWithMask`, which is why the minimum is macOS 14. Applying it auto-switches a non-alpha export format to PNG.

**Tests** generate images in code (`Tests/ImageKitTests/Helpers.swift`). The background-removal test uses `/Library/User Pictures/Animals/Parrot.heic` and is skipped if that file is missing.

**Not sandboxed**, because exporting next to the original requires it. Sandboxing later means security-scoped bookmarks or `NSSavePanel`.
