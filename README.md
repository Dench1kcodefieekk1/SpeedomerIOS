# Aeris — Ride Tracker for iOS 26

A native cycling speed & ride tracker designed specifically for Apple's
**iOS 26 Liquid Glass** design language. Built entirely with SwiftUI, MapKit,
SwiftData and Swift Charts.

## Highlights

- **Speedometer centerpiece** — an oversized rounded-type speed readout inside
  a subtle arc gauge, a live `GPS • Good` glass status chip, and floating glass
  stat tiles (Distance / Avg / Max / Time).
- **Native Liquid Glass** — uses the real iOS 26 APIs: `glassEffect`,
  `GlassEffectContainer`, `.buttonStyle(.glass)` / `.glassProminent`,
  `glassEffectID` morphing for the Start → Pause/Stop controls, and
  `tabBarMinimizeBehavior`. On earlier releases the app automatically falls
  back to `ultraThinMaterial` surfaces, so it stays stable everywhere.
- **Map** — full-bleed MapKit with a floating live-speed glass chip, a glass
  bottom information panel (live stats while recording, last-ride summary when
  idle) and a glass map-style control. The map stays visible behind every
  control.
- **Ride detail** — large route map as the hero with translucent stat chips
  overlaid, a glass stat grid, and a Swift Charts speed graph on a glass panel.
- **History** — native grouped list with glass row surfaces, month sections,
  swipe-to-delete, and push navigation.
- **Semantic color & motion** — only system colors (`accentColor`, `.secondary`,
  `.red`, …), native springs, and Reduce Motion support throughout.

## Requirements

- A Mac with **Xcode 26** (the iOS 26 SDK is required — the Liquid Glass
  symbols don't exist in earlier SDKs).
- iOS 17+ to run. Liquid Glass renders on **iOS 26+**; older versions get the
  material fallbacks.

## Build

### Option A — XcodeGen (recommended)

```bash
brew install xcodegen
cd "<this folder>"
xcodegen generate
open Aeris.xcodeproj
```

The project is described by `project.yml` (bundle id `com.aeris.ride`,
deployment target iOS 17.0, background location mode and permission strings
already configured). Select your signing team, then Run.

### Option B — Manual Xcode project

1. Xcode 26 → File ▸ New ▸ Project ▸ iOS ▸ App, name `Aeris`, Interface:
   SwiftUI.
2. Replace the generated sources with the contents of `Aeris/` and add
   `Assets.xcassets`.
3. Signing & Capabilities → **+ Background Modes** → *Location updates*.
4. Add to Info.plist:
   - `NSLocationWhenInUseUsageDescription`
   - `NSLocationAlwaysAndWhenInUseUsageDescription`
5. Set the deployment target to iOS 17.0+.

## Testing GPS in the Simulator

Run the app, then in the Simulator menu:
**Features ▸ Location ▸ City Bicycle Ride** (or *Freeway Drive*). The
speedometer, map polyline and live stats update in real time. On a real
device, just start riding — recording continues with the screen off
(background location mode is enabled).

## Project layout

```
Aeris/
├── AerisApp.swift                  # App entry, engine + SwiftData container
├── Assets.xcassets/                # Accent color, app icon
├── Core/
│   ├── Location/LocationService.swift # CLLocationManager → AsyncStream bridge
│   ├── RideEngine.swift               # Ride state machine (async consumers)
│   ├── Models/Ride.swift              # SwiftData model + RidePoint samples
│   ├── SpeedUnit.swift                # km/h ↔ mph conversion & formatting
│   └── Formatters.swift               # Dates, durations, month sections
├── DesignSystem/
│   ├── Glass.swift                 # glassSurface / GlassGroup / GlassButton
│   ├── Motion.swift                # Animation.glass (Reduce Motion) + haptics
│   └── Components.swift            # StatTile
└── Features/
    ├── Root/RootView.swift         # TabView (Ride / Map / History / Settings)
    ├── Speedometer/SpeedometerView.swift
    ├── Map/RideMapView.swift
    ├── History/HistoryView.swift
    ├── History/RideDetailView.swift
    ├── History/SpeedChartView.swift
    └── Settings/SettingsView.swift
```

## Design system notes

- **One entry point for glass.** Every translucent surface goes through
  `View.glassSurface(in:tint:interactive:)` (`DesignSystem/Glass.swift`). On
  iOS 26+ it maps to the native `glassEffect` API (with `.tint`/`.interactive`
  variants); below iOS 26 it renders `ultraThinMaterial` with a hairline
  border. Availability is checked at runtime with `#available(iOS 26, *)` so
  the project compiles and runs stably.
- **Grouped glass.** Clusters that morph (the ride controls) are wrapped in
  `GlassGroup`, a thin wrapper over `GlassEffectContainer`, and use
  `glassEffectID` + `@Namespace` so Start literally liquid-morphs into the
  Pause/Stop pair.
- **Buttons.** `GlassButton` wraps the native `.glass` / `.glassProminent`
  button styles with a material capsule fallback.
- **Motion.** All state-change animation goes through `Animation.glass(_:)`,
  which returns `nil` under Reduce Motion — the UI then switches state
  instantly.
- **Accessibility.** The speed cluster is a single VoiceOver element
  ("Current speed, 87 kilometers per hour"); every glass tile combines its
  label and value; all controls have explicit labels; Dynamic Type scales the
  speed display via `@ScaledMetric`; the arc, pulse and digit transitions all
  respect Reduce Motion.

---

# CI/CD — GitHub Actions

The project ships with a complete pipeline in
[`.github/workflows/ios-build.yml`](.github/workflows/ios-build.yml). It runs
on GitHub's macOS runners and builds with **Xcode 26** (latest stable).

## How it works

Because `Aeris.xcodeproj` is generated by XcodeGen (and gitignored), every CI
job first runs `xcodegen generate` — exactly like a fresh local clone would.
There are two jobs:

| Job | What it does | When it runs | Needs secrets? |
|---|---|---|---|
| **build-and-test** | Installs XcodeGen, regenerates the project, picks an available iPhone simulator, runs `xcodebuild clean build` for the iOS Simulator, then `xcodebuild test` (unit tests from the `AerisTests` target). Uploads the simulator `.app` as an artifact, and logs + `.xcresult` on failure. | Every push to `main`, every PR to `main`, and manual runs | **No** |
| **archive-and-export** | Creates a temporary keychain, imports your certificate and provisioning profile from secrets, runs `xcodebuild archive` (Release, generic iOS device), then `xcodebuild -exportArchive` to produce a **signed `.ipa`**, uploaded as an artifact. Cleans up the keychain and profile afterwards. | Manual `workflow_dispatch` runs and pushes of `v*` tags | **Yes** |

Both jobs fail hard (`set -o pipefail` around every `xcodebuild` call), so a
compile error, failing test, or export failure fails the run.

## Triggers

- **Push / Pull request to `main`** — build + unit tests only (no signing).
- **Manual run** — *Actions ▸ iOS CI ▸ Run workflow*, with a dropdown to pick
  the export method:
  - `development` (default) → `.ipa` signed with your *Apple Development*
    certificate + development profile, installable on registered devices.
  - `app-store-connect` → `.ipa` signed with your *Apple Distribution*
    certificate + App Store profile, ready to upload to App Store Connect
    (e.g. via Transporter or `xcrun altool`).
- **Tag push `v*`** (e.g. `git tag v1.0.0 && git push --tags`) — runs the
  archive job with the default `development` method.

## Required secrets (only for the signed `.ipa` job)

Add these under **Settings ▸ Secrets and variables ▸ Actions ▸ Repository
secrets**:

| Secret | Contents |
|---|---|
| `CERTIFICATE_P12_BASE64` | Your **Apple Development** (or Apple Distribution, for App Store exports) signing certificate, exported as a `.p12`, Base64-encoded. |
| `CERTIFICATE_PASSWORD` | The password you set when exporting the `.p12`. |
| `KEYCHAIN_PASSWORD` | Any strong random string — used only for the temporary CI keychain. |
| `PROVISIONING_PROFILE_BASE64` | The provisioning profile (`.mobileprovision`) that matches the app (`com.aeris.ride`) and the certificate, Base64-encoded. |

### How to create these values

1. **Certificate (.p12)** — In Xcode: *Settings ▸ Accounts ▸ your Apple ID ▸
   Manage Certificates ▸ +* (Apple Development). Then open *Keychain Access*,
   find the `Apple Development: …` entry, right-click → *Export…*, choose
   `.p12`, set a password. Base64-encode it:

   ```bash
   base64 -i Certificates.p12 | pbcopy   # paste into the secret
   ```

2. **Provisioning profile** — In the [Apple Developer portal](https://developer.apple.com/account/resources/certificates/list)
   create an *iOS App Development* (or *App Store*) profile for an app with
   bundle id **`com.aeris.ride`**, include your certificate and your test
   devices (development only), download the `.mobileprovision`, then:

   ```bash
   base64 -i Aeris_Dev.mobileprovision | pbcopy
   ```

   The workflow reads the profile's *name*, *UUID* and *Team ID* at run time
   and injects them into `ExportOptions.plist` automatically — the
   `TEAM_ID_PLACEHOLDER` / `PROFILE_NAME_PLACEHOLDER` values in
   [`ExportOptions.plist`](ExportOptions.plist) and
   [`ExportOptions-AppStore.plist`](ExportOptions-AppStore.plist) are just
   placeholders and are always overwritten.

> **Note:** the certificate and profile must match the chosen export method —
> `Apple Development` + development profile for `development`, `Apple
> Distribution` + App Store profile for `app-store-connect`. If the secrets
> are missing when the archive job runs, it fails immediately with a clear
> error message instead of producing an unsigned artifact.

## Artifacts

Every run publishes artifacts under the run's *Summary* page:

- `Aeris-simulator-build` — the Debug `.app` built for the iOS Simulator
  (all runs).
- `Aeris-ipa-development` / `Aeris-ipa-app-store-connect` — the signed
  `.ipa` (archive runs).
- `build-logs` / `archive-logs` — raw `xcodebuild` logs and `.xcresult`
  bundles, only when something fails.

To install the development `.ipa` on a device: download the artifact and
install with `xcrun devicectl device install app --device <UDID> Aeris.ipa`,
via Finder, or Apple Configurator.

## Runner note

The workflow pins `macos-15`. Xcode 26 (with the iOS 26 SDK required by the
Liquid Glass APIs) is selected via `maxim-lobanov/setup-xcode@v1` with
`latest-stable`, so the pipeline picks up new Xcode 26.x point releases
automatically. If you migrate to GitHub's `macos-26` image later, only the
`runs-on` fields need to change.
