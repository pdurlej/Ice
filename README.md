<div align="center">
    <img src="Resources/Banner.png" alt="Fire from Ice — ice cube with inner flame on a blue-to-ember gradient">
    <h1>Fire from Ice 🔥🧊</h1>
    <p><em>Maintained continuation of <a href="https://github.com/jordanbaird/Ice">jordanbaird/Ice</a> with macOS 26 Tahoe support + signed/notarized DMGs</em></p>
</div>

> [!IMPORTANT]
> Upstream Ice received its last code commit on **2025-06-06** and its last stable release (`0.11.12`) predates macOS Sequoia and Tahoe. Multiple Tahoe-only bugs are reported but unaddressed upstream — most visibly the **menu bar items not loading** regression (upstream issues [#744](https://github.com/jordanbaird/Ice/issues/744), [#891](https://github.com/jordanbaird/Ice/issues/891), [#913](https://github.com/jordanbaird/Ice/issues/913); ~80 reactions combined). This fork ships those fixes as proper signed, notarized DMG releases.
>
> If you're on macOS 26 Tahoe and upstream Ice's Menu Bar Layout pane is empty for you, this fork fixes it.

Ice is a powerful menu bar management tool for macOS. While its primary function is hiding and showing menu bar items, it covers many additional features that make it one of the most versatile menu bar tools available.

![Banner](https://github.com/user-attachments/assets/4423085c-4e4b-4f3d-ad0f-90a217c03470)

[![Download](https://img.shields.io/github/v/release/pdurlej/Ice?label=Download%20latest%20DMG&style=flat-square&color=brightgreen)](https://github.com/pdurlej/Ice/releases/latest)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue?style=flat-square)
![Signed](https://img.shields.io/badge/Developer%20ID-signed%20%2B%20notarized-success?style=flat-square)
[![License](https://img.shields.io/github/license/pdurlej/Ice?style=flat-square)](LICENSE)

## What this fork fixes

| Symptom | Upstream issue | Fixed in |
|---|---|---|
| Menu Bar Layout pane shows empty rows on macOS 26 | [#744](https://github.com/jordanbaird/Ice/issues/744), [#891](https://github.com/jordanbaird/Ice/issues/891), [#913](https://github.com/jordanbaird/Ice/issues/913) | `fire.2` + `fire.3` — `MenuBarItemService` XPC peer-requirement guard |
| TCC permissions reset on every new ad-hoc build | n/a (Apple Developer Program required) | `fire.4` — Developer ID signed + Apple-notarized DMG |
| `Node.js 20` deprecation warnings in CI | n/a | `fire.4` workflow — bumped all actions to Node 24 majors |

## Install

### Download the signed DMG

1. Grab the latest `Ice-v0.11.13-fire.X.dmg` from [Releases](https://github.com/pdurlej/Ice/releases/latest).
2. Open the DMG. Drag **Ice.app** to your `Applications` folder.
3. Launch from `/Applications`. On first run, macOS may prompt for **Accessibility** and **Screen Recording** — grant both.

The DMG is **signed** with `Developer ID Application: Piotr Durlej (R47JTHX25P)` and **stapled** with an offline notarization ticket. First launch works without an internet round-trip; Gatekeeper accepts on macOS 14 (Sonoma) and later, including Tahoe 26.x.

### Verify the download (optional)

```sh
shasum -a 256 Ice-v0.11.13-fire.4.dmg
# expected: 231cbd038fb41242d7a298cdb7d46ac5f0f7c8a05ccef633668a13147a4b0e09

spctl -avv --type install Ice-v0.11.13-fire.4.dmg
# expected: accepted, source=Notarized Developer ID, origin=Developer ID Application: Piotr Durlej (R47JTHX25P)
```

### Upgrading from upstream Ice, or from any Fire ad-hoc build (fire.0/.1/.2/.3)

**One-time** TCC reset is needed after the first install of a signed Fire build over any ad-hoc-signed predecessor — the cryptographic signature anchor changes, so existing TCC grants silently fail to match:

```sh
tccutil reset All com.jordanbaird.Ice
tccutil reset All com.jordanbaird.Ice.MenuBarItemService
osascript -e 'tell application "Ice" to quit'
open /Applications/Ice.app
# then re-grant Accessibility (and Screen Recording if used) in System Settings
```

All subsequent Fire updates (`fire.5+`, signed under the same Team ID) preserve permissions automatically — no further reset needed.

## Auto-updates (Sparkle)

Fire ships with **Sparkle 2.9.2** wired to a custom appcast at <https://pdurlej.github.io/fire-releases/appcast.xml>. After installing Ice, **Check for Updates** (Ice menu → Check for Updates) will auto-discover new Fire releases.

The appcast is signed with **EdDSA** — the public key is embedded in the app's `Info.plist` (`SUPublicEDKey`), and the matching private key lives only in the maintainer's macOS Keychain. A network attacker who tampers with the GitHub Pages feed cannot inject a malicious update.

## Bundle ID & upstream compatibility

This fork keeps the upstream bundle ID `com.jordanbaird.Ice`, so it is a **drop-in replacement** for upstream Ice. Your existing Ice settings (`~/Library/Preferences/com.jordanbaird.Ice.plist`), hotkeys, and menu bar layout persist on upgrade.

When Fire moves to Phase 4 of the [roadmap](FORK.md#phasing) (proper "Fire" rebrand with a new bundle ID and icon), a first-launch migration will copy your settings across so no state is lost.

## Building from source

```sh
git clone https://github.com/pdurlej/Ice.git
cd Ice
xcodebuild -scheme Ice -configuration Release \
    CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO
```

The resulting `Ice.app` is unsigned (`ad-hoc`) and will need `tccutil reset` on every rebuild on Tahoe. For signed local builds, the full sign + notarize + staple pipeline is in [`.github/workflows/build-dmg.yml`](.github/workflows/build-dmg.yml).

## MCP Server

Fire ships an embedded MCP server so you can ask an AI assistant to manage your menu bar. Wire Claude Desktop, Claude Code, Cursor, or Continue to `/Applications/Ice.app/Contents/MacOS/IceMCPBridge` and the 6 tools (`list_items`, `hide_item`, `show_item`, `move_item`, `save_layout`, `apply_layout`) become available. See [docs/mcp/CLIENT-SETUP.md](docs/mcp/CLIENT-SETUP.md) for setup.

## Privacy & Diagnostics

Fire ships with **opt-in crash reporting** via Sentry. **Default: OFF** — no data leaves your machine until you explicitly enable it in **Advanced Settings → Privacy & Diagnostics**.

When you opt in, Fire sends crash reports only — stack trace, thread state, macOS version, CPU architecture, and Fire version. That is what a maintainer needs to debug a crash and nothing more.

**What is never sent**, even when you opt in:

- Hostname or IP address
- Menu bar item contents (icons, titles, bundle IDs of running apps)
- Screenshots or view hierarchy
- Click/interaction breadcrumbs
- Network requests or fetched URLs
- Any usage analytics or telemetry

The Sentry SDK is only initialized at app launch if the toggle is on. When the toggle is off, no Sentry code runs, no data is collected, and no network connections are opened to Sentry's servers. You can flip it back off at any time; the change takes effect on the next app launch.

This is a Fire-fork-specific addition; upstream Ice has no crash reporting because it predates the maintainer's Apple Developer Program enrollment.

## Features (inherited from upstream Ice)

### Menu bar item management

- [x] Hide menu bar items
- [x] "Always-hidden" menu bar section
- [x] Show hidden menu bar items when hovering over the menu bar
- [x] Show hidden menu bar items when an empty area in the menu bar is clicked
- [x] Show hidden menu bar items by scrolling or swiping in the menu bar
- [x] Automatically rehide menu bar items
- [x] Hide application menus when they overlap with shown menu bar items
- [x] Drag and drop interface to arrange individual menu bar items
- [x] Display hidden menu bar items in a separate bar (e.g. for MacBooks with the notch)
- [x] Search menu bar items
- [x] Menu bar item spacing (BETA)

### Menu bar appearance

- [x] Menu bar tint (solid and gradient)
- [x] Menu bar shadow
- [x] Menu bar border
- [x] Custom menu bar shapes (rounded and/or split)

### Hotkeys

- [x] Toggle individual menu bar sections
- [x] Show the search panel
- [x] Enable/disable the Ice Bar
- [x] Show/hide section divider icons
- [x] Toggle application menus

See [ROADMAP.md](ROADMAP.md) for fork-specific planned features (profiles, trigger conditions, layout import/export, sensible defaults for new-icon placement, per-display configuration).

## Contributing

- **Bugs specific to this fork** (not present in upstream Ice `0.11.12`): file in [this repo's Issues](https://github.com/pdurlej/Ice/issues).
- **Bugs present in upstream too**: please file [upstream](https://github.com/jordanbaird/Ice/issues) first so they show in the canonical tracker. Cross-link from this repo if relevant.
- **Pull requests**: open against `fire/main`. Both `lint.yml` (SwiftLint, runs on every push touching `**/*.swift`) and `build-dmg.yml` (full signed+notarized build, runs on tag push `v*`) must stay green.

## Credits

- **Original Ice** by [Jordan Baird](https://github.com/jordanbaird) — every line of upstream code remains his copyright under GPL-3.0.
- **Fire fork** maintained by [Piotr Durlej](https://github.com/pdurlej). Fork-specific changes are also GPL-3.0.
- The fork is **independent and unofficial** — please do not file fork-specific issues on the upstream tracker.

## License

[GPL-3.0](LICENSE) — unchanged from upstream.
