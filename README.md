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
and keeps the framework's animation timer enabled so `animateOneFrame()`
can start displays that miss that callback. A visibly attached AppKit window is
also accepted as a startup signal for previews.

The shader uses `requestAnimationFrame`. Remote screen-saver windows can be
reported as hidden to WebKit even while their pixels are on screen, so the
extension disables WebKit window-occlusion detection for the screen saver view
hierarchy. That selector is private and therefore needs review before Mac App
Store distribution. The runtime is torn down on `stopAnimation()` or window
detachment, and navigation outside the bundled runtime remains blocked by the
navigation delegate.

See [BACKGROUND.md](BACKGROUND.md) for detailed technical notes on the Appex screensaver architecture.

## Building and Installation

### Prerequisites

- Xcode 26 or newer
- macOS 26.0 or newer
- An Apple Developer Team ID for Developer ID distribution; the experimental CI builds need no certificate

### Getting Started

1. **Clone the repository:**

   ```bash
   git clone https://github.com/Harumaru169/WebGLScreenSaver.git
   cd WebGLScreenSaver
   ```

2. **Open the project in Xcode:**

   ```bash
   open WebGLScreenSaver.xcodeproj
   ```

3. **Set your own Team ID:** open the project settings, select the `WebGLScreenSaver` target, and under **Signing & Capabilities** set your **Team**. Repeat for the `WebGLScreenSaverExtension` target. The project currently contains a local development Team ID. Replace it with yours for normal Xcode development; the experimental build script overrides it with an empty value.

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

### Experimental Homebrew distribution

This distribution targets **Apple Silicon and macOS 26 or later**. The app and
its embedded extension are ad-hoc signed without an Apple account, certificate,
or provisioning profile. They are **not notarized by Apple**. The experimental
Cask removes quarantine from this app, bypassing the normal Gatekeeper check.
Signature verification alone does not establish that the screen saver starts
or that App Group settings are shared correctly; test both on a clean Mac.

#### CI and draft releases

- `.github/workflows/ci.yml` builds branches, pull requests, and manual runs.
- `.github/workflows/release.yml` builds tags of the form `vX.Y.Z` and creates
  an experimental **Draft Release** in `Harumaru169/WebGLScreenSaver`.
- Both use the `macos-26` arm64 runner with Xcode 26.6 explicitly selected.
- Neither uses development credentials. CI skips automatic extension
  registration, SwiftLint auto-fixes, and the scheme's timestamp build number.
- Dependencies are pinned by `Package.resolved`. The release version comes
  from the tag, and the build number comes from the Actions run number.

The release attaches `WebGLScreenSaver-arm64.zip`, `SHA256SUMS`,
`build-info.json`, and a ready-to-copy `webgl-screen-saver.rb`. Build information
records the source commit, dirty state, toolchain, runner image, dependency
versions, and workflow URL. An Artifact Attestation binds the exact ZIP to its
GitHub Actions build; it does not replace Developer ID signing or notarization.
The Release stays a draft until manually published. Published releases are
never overwritten by the workflow; reruns may refresh an existing draft.

Use a public GitHub repository with Actions enabled and permission for the
workflow to write Releases and attestations. No Apple secrets or Tap token are
needed. After committing and pushing the desired source revision, push a tag,
for example `v1.0.0`. Every subsequent distributed build needs a new version/tag.

#### Local build

With Xcode 26 or newer selected:

```bash
bash scripts/build-release.sh 1.0.0
```

This produces the same artifact structure under the ignored `dist/` directory.
It signs inside out, preserving the app and extension entitlements, then checks
the signature, bundle versions, arm64 architecture, resources, and entitlements
again after extracting the ZIP. Build scripts must not change tracked source.
If `dist/` already contains a ZIP, move that directory elsewhere before another
build. Local build information may report `source_dirty: true`; such a ZIP has
no GitHub attestation and its hash will differ from the CI release ZIP.

The template lives in `homebrew/webgl-screen-saver.rb.in`. Generate the actual
Cask from the **exact ZIP you intend to publish**, including into a local Tap:

```bash
python3 scripts/generate-cask.py 1.0.0 /path/to/WebGLScreenSaver-arm64.zip \
  /Users/kharuyama/Developer/tap/Casks/webgl-screen-saver.rb
```

The Cask URL always points to the tagged GitHub Release. A Cask generated from a
local test ZIP is only a draft: replace it with the CI-generated Cask before
publishing the Tap. Draft Release assets are not publicly downloadable.

#### Validate, publish, and update the Tap

1. Download the exact ZIP and checksum file from the Draft Release. Verify:

   ```bash
   shasum -a 256 -c SHA256SUMS
   gh attestation verify WebGLScreenSaver-arm64.zip --repo Harumaru169/WebGLScreenSaver
   ```

2. On a clean macOS 26+ VM with no existing app, install that ZIP in
   `/Applications`. For this experimental test, remove quarantine only from
   that app, matching the Cask's behavior:

   ```bash
   xattr -rd com.apple.quarantine /Applications/WebGLScreenSaver.app
   ```

   Launch the host, click Install if needed, and confirm registration with
   `pluginkit -m -v -p com.apple.screensaver`. Check System Settings preview and
   full-screen rendering. Change shader and speed, quit the host, and confirm
   settings after restarting the extension, logging in again, and rebooting.
   If settings do not propagate or every launch needs permission, the current
   App Group design has not passed the distribution experiment.

3. On an Apple Silicon Mac, check continuous rendering, sleep/wake, repeated
   starts/stops, and multiple displays. Keep a single installed app copy to
   avoid cached extension paths. Record OS, ZIP checksum, dialogs, and results.

4. Publish the Draft Release manually. Copy its attached Cask to
   `Harumaru169/tap/Casks/webgl-screen-saver.rb`, check its style and download,
   then commit and push the Tap separately. Do not regenerate the Cask from a
   different local ZIP after the CI ZIP has been published.

   ```bash
   brew style /Users/kharuyama/Developer/tap/Casks/webgl-screen-saver.rb
   brew install --cask harumaru169/tap/webgl-screen-saver
   ```

5. On a clean VM, verify the actual Cask install, first launch, and settings.
   For subsequent versions, repeat validation before updating the Tap, then:

   ```bash
   brew update
   brew upgrade --cask harumaru169/tap/webgl-screen-saver
   ```

   Confirm the new bundle/version is registered and existing settings remain.
   Stop the screen saver and select another before uninstalling:

   ```bash
   brew uninstall --cask harumaru169/tap/webgl-screen-saver
   ```

The Cask quits the host and unregisters the embedded extension during removal.
It does not auto-enable the screen saver, restart WallpaperAgent, re-sign the
app, or delete user settings. Extension startup and App Group sharing remain
manual acceptance checks; a green CI build verifies packaging, not these checks.

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
