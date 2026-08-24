# WebGLScreenSaver

A SwiftUI macOS app that turns a Shadertoy Image shader into an **`.appex` screen saver extension**. It is based on Guillaume Louel's [AppexSaverMinimal](https://github.com/AerialScreensaver/AppexSaverMinimal) project.

Use this as a starting point for your own Appex screensaver. The companion project [ScreenSaverMinimal](https://github.com/AerialScreensaver/ScreenSaverMinimal) covers the legacy `.saver` plug-in format for comparison.

## What this sample shows

- A complete host app + `.appex` extension wired up to build, sign, and install
- A WebGL2 Shadertoy-compatible Image shader runtime hosted by `WKWebView`
- A side-by-side GLSL editor and live preview with compile-before-apply behavior
- Shared App Group settings for draft source, applied source, and animation speed
- Programmatic registration via `pluginkit` and activation via [PaperSaver](https://github.com/AerialScreensaver/PaperSaver)
- Shared rendering code between the screensaver and an in-app preview window
- The bundled Seascape shader as the initial screen saver

The extension creates one `WKWebView` per display from ScreenSaver.framework's
animation lifecycle. It uses `startAnimation()` as the primary startup signal
and keeps the framework's 30 fps animation timer enabled so `animateOneFrame()`
can start displays that miss that callback. A visibly attached AppKit window is
also accepted as a startup signal for previews.

The shader normally uses `requestAnimationFrame`. Remote screen-saver windows
can be reported as hidden to WebKit even while their pixels are on screen, so
the extension detects a hidden or stalled page and switches only that display
to explicit WebGL draws from `animateOneFrame()`. It also disables WebKit
window-occlusion detection for the screen saver view hierarchy. That selector
is private and therefore needs review before Mac App Store distribution. The
runtime is torn down on `stopAnimation()` or window detachment, and navigation
outside the bundled runtime remains blocked by the navigation delegate.

See [BACKGROUND.md](BACKGROUND.md) for detailed technical notes on the Appex screensaver architecture.

## Building and Installation

### Prerequisites

- Xcode 26 or newer
- macOS 26.0 or newer
- An Apple Developer Team ID if you want to distribute the screensaver to other machines

### Getting Started

1. **Clone the repository:**

   ```bash
   git clone https://github.com/AerialScreensaver/AppexSaverMinimal.git
   cd AppexSaverMinimal
   ```

2. **Open the project in Xcode:**

   ```bash
   open WebGLScreenSaver.xcodeproj
   ```

3. **Set your own Team ID:** open the project settings, select the `WebGLScreenSaver` target, and under **Signing & Capabilities** set your **Team**. Repeat for the `WebGLScreenSaverExtension` target. The project ships with `DEVELOPMENT_TEAM = ""` so you must add yours before signing kicks in.

### Project Targets

This project contains two targets:

- **WebGLScreenSaver** — A SwiftUI host application that bundles and registers the screensaver extension. Run this in Xcode (⌘R) to drive install / uninstall and preview from a normal app window.
- **WebGLScreenSaverExtension** — The screensaver itself, packaged as an `.appex` and embedded inside the host app's `Contents/PlugIns/`.

### Building

```bash
xcodebuild -project WebGLScreenSaver.xcodeproj -scheme AppexSaverMinimal -configuration Debug build
```

### Installing

Most of the time you don't need to register the extension explicitly: macOS scans known locations (such as the Xcode build folder and `/Applications/`) and picks up new appex screensavers automatically shortly after they're built. After a build, opening **System Settings → Screen Saver** is usually enough — **WebGLScreenSaver** will be in the list.

If it doesn't appear, you can nudge `pluginkit`:

1. **From the host app** — run the host app and click **Install**. This calls `pluginkit -a` on the embedded `.appex`.
2. **Manually with pluginkit:**

   ```bash
   pluginkit -a ~/Library/Developer/Xcode/DerivedData/WebGLScreenSaver-*/Build/Products/Debug/WebGLScreenSaver.app/Contents/PlugIns/WebGLScreenSaverExtension.appex
   ```

Then pick **WebGLScreenSaver** in System Settings, or use the **Enable as Screensaver** button in the host app (powered by [PaperSaver](https://github.com/AerialScreensaver/PaperSaver) 0.2.0+).

While developing, restart `WallpaperAgent` after rebuilding or re-registering
the `.appex` so macOS does not launch a cached extension UUID:

```bash
killall WallpaperAgent
```

The process restarts automatically. Running this briefly resets the desktop and
wallpaper presentation, so do it immediately before the next screen saver test.

#### Important: pick ONE location per machine

`pluginkit` keeps a cache of where it found each extension, and it appears to hardcode a preference for `/Applications/`. If you build the app in DerivedData **and** also install a copy in `/Applications/`, macOS will keep loading the `/Applications/` copy regardless of which one you most recently built — and `pluginkit` will refuse to register a second copy from somewhere else.

Pick one location and stick with it on a given machine:

- **Always use DerivedData** — develop in Xcode, never copy to `/Applications/`. Simplest while iterating.
- **Always use `/Applications/`** — add a build phase or post-build script that copies `WebGLScreenSaver.app` into `/Applications/` (replacing any previous copy) before you trigger the screensaver. Closer to the user-install experience.

If you've already mixed both, remove the `/Applications/` copy and re-register the DerivedData one (or vice versa) to clear the cache. For full isolation between development and release-build testing, use a separate VM.

### Distribution

To distribute a signed and notarized build to others:

1. **Archive** in Xcode (Product → Archive), then export from the Organizer.
2. **Notarize via command line:**

   ```bash
   xcrun notarytool submit "AppexSaverMinimal.app.zip" \
     --keychain-profile "AC_PASSWORD" \
     --wait

   xcrun stapler staple "AppexSaverMinimal.app"
   xcrun stapler validate "AppexSaverMinimal.app"
   ```

   You need a keychain profile set up first:

   ```bash
   xcrun notarytool store-credentials "AC_PASSWORD" \
     --apple-id "your@email.com" \
     --team-id "TEAMID" \
     --password "app-specific-password"
   ```

## Logs via Console.app

Both the host app and the extension log to a single subsystem so you can watch their lifecycles side-by-side.

1. Open **Console.app**.
2. Filter by subsystem:

   ```
   subsystem:kosei.haruyama.WebGLScreenSaver
   ```

3. Trigger the screensaver:

   ```bash
   open -a ScreenSaverEngine
   ```

   You'll see log lines from three processes: the host app (when previewing), the extension (when rendering), and `legacyScreenSaver` / `ScreenSaverEngine` lifecycle events.

You can also stream logs from the command line:

```bash
log stream --predicate 'subsystem == "kosei.haruyama.WebGLScreenSaver"' --level debug
```

## Project Structure

```
WebGLScreenSaver/                             Host app and shared renderer
├── WebGLScreenSaverApp.swift                 @main SwiftUI app entry
├── WindowMainView.swift                      GLSL editor and extension controls
├── CoreView.swift                            SwiftUI wrapper for the preview WKWebView
├── ShaderRuntimeController.swift             WKWebView lifecycle and JS bridge
├── ShaderSourceStore.swift                   Draft/apply persistence flow
├── SharedSettings.swift                      App Group UserDefaults
├── PluginManager.swift                       pluginkit + PaperSaver wrappers
└── Resources/
    ├── ShaderRuntime.html                    WebGL2 Shadertoy runtime
    └── DefaultShader.glsl                    Bundled Seascape shader

WebGLScreenSaverExtension/                    Screen saver appex
├── WebGLScreenSaverExtension.swift           Principal class
├── WebGLScreenSaverViewController.swift      ScreenSaverViewController
├── WebGLScreenSaverView.swift                Direct WKWebView screen saver host
└── WebGLScreenSaverConfigurationViewController.swift
```

## Comparison to the legacy `.saver` format

If you need to target older macOS versions that don't support Appex screensavers, see the companion repo [ScreenSaverMinimal](https://github.com/AerialScreensaver/ScreenSaverMinimal). The two projects intentionally share the same rainbow fallback look so you can read them as a pair.

| | `.appex` (this repo) | `.saver` ([companion](https://github.com/AerialScreensaver/ScreenSaverMinimal)) |
|---|---|---|
| **Bundle type** | `XPC!` (ExtensionKit) | `BNDL` (NSBundle plug-in) |
| **Process** | Separate sandboxed process | In-process with `legacyScreenSaver.appex` |
| **Min macOS** | 26.0 for this WebView-based project | All supported macOS |
| **Distribution** | Embedded in a `.app` | Standalone `.saver` file |
| **System Settings entry** | Listed alongside Apple's first-party savers | Listed under a separate "Other" group |

## License

[MIT](LICENSE) © 2026 Guillaume Louel
