# Ice → Fire Rebrand: Technical Plan

> **Archived proposal — do not execute.** Fire intentionally keeps
> `com.jordanbaird.Ice` and `Ice.app` to preserve TCC permissions, Sparkle
> continuity, Sentry releases, and signed XPC identity. Any future bundle-ID
> migration requires a new product decision and release plan.

App: `com.jordanbaird.Ice` → `me.durlej.Fire`. macOS 14+, Xcode project (no SwiftPM manifest), Sparkle + LaunchAtLogin + AXSwift dependencies, XPC service for menu-bar-item rendering on macOS 26.

---

## 0. One-page summary (TL;DR)

**What changes for users.** Display name "Ice" → "Fire". Bundle ID flips. First launch of Fire migrates UserDefaults from the old Ice domain in-place; menu-bar layout, hotkeys, settings, hidden-section state all carry over. **TCC permissions (Accessibility, Screen Recording) must be re-granted once** — macOS keys these on bundle ID and there is no supported way around it. We surface this clearly in an onboarding window that detects "looks like Ice was previously installed" and offers a one-click "Open System Settings" affordance per permission.

**What we ship.**
1. A `LegacyMigration` step that runs once in `applicationWillFinishLaunching` before the existing `MigrationManager`. It copies UserDefaults from `com.jordanbaird.Ice` into the new standard suite, including the `NSStatusItem`-namespaced layout keys, and stamps a sentinel.
2. New `PRODUCT_BUNDLE_IDENTIFIER`, new `INFOPLIST_KEY_CFBundleDisplayName = Fire`, new XPC service ID `me.durlej.Fire.MenuBarItemService`. Info.plist `SUFeedURL` repointed to our appcast.
3. UI strings: "Ice" → "Fire" everywhere a user sees it (window titles, About box, settings labels, menu titles, permission prompts, notification bodies). Setting *keys* and the IceUI Swift type prefix stay — they are internal and renaming churns blame for zero user benefit.
4. "Ice Bar" feature → "Fire Bar" (recommended; cheaper than explaining why the feature has a different name from the app).
5. Sparkle: host our own appcast on GitHub Pages at `pdurlej.github.io/fire-releases/appcast.xml` and ship a new EdDSA key.
6. New AppIcon.appiconset (10 PNGs).
7. Login item: `LaunchAtLogin` re-registers under the new bundle ID on first launch; old registration is best-effort unregistered.
8. Keychain: **Ice does not use Keychain.** No migration needed.

**Risks** (full register in §9): the layout migration is the most delicate piece — NSStatusItem stores `Preferred Position` keys under each control item's autosave name. Those values are CGFloats and must round-trip exactly. Tested by a manual side-by-side install before tagging.

**Ship order** (full sequence in §8): land the migration code dormant first (commit 1), flip the bundle ID + display name in one commit so the migration self-activates (commit 2), rename "Ice Bar" → "Fire Bar" (commit 3), swap icon and appcast URL (commits 4-5), then tag.

---

## 1. Bundle ID and app metadata

### 1.1 Occurrences of `com.jordanbaird.Ice`

| File | Line | Current | Action |
|---|---|---|---|
| `Ice.xcodeproj/project.pbxproj` | 437 | `PRODUCT_BUNDLE_IDENTIFIER = com.jordanbaird.Ice;` (Debug app) | → `me.durlej.Fire` |
| `Ice.xcodeproj/project.pbxproj` | 470 | `PRODUCT_BUNDLE_IDENTIFIER = com.jordanbaird.Ice;` (Release app) | → `me.durlej.Fire` |
| `Ice.xcodeproj/project.pbxproj` | 490 | `PRODUCT_BUNDLE_IDENTIFIER = com.jordanbaird.Ice.MenuBarItemService;` (Debug XPC) | → `me.durlej.Fire.MenuBarItemService` |
| `Ice.xcodeproj/project.pbxproj` | 516 | same (Release XPC) | → `me.durlej.Fire.MenuBarItemService` |
| `Shared/Services/MenuBarItemService.swift` | 9 | `static let name = "com.jordanbaird.Ice.MenuBarItemService"` | → `"me.durlej.Fire.MenuBarItemService"` (must match the XPC bundle ID exactly — this is the Mach service name the host looks up) |
| `Ice/Resources/Info.plist` | 5–6 | `SUFeedURL = https://jordanbaird.github.io/ice-releases/appcast.xml` | → `https://pdurlej.github.io/fire-releases/appcast.xml` (and rotate `SUPublicEDKey` on line 8) |
| `Ice/Settings/SettingsPanes/AboutSettingsPane.swift` | 20 | `URL(string: "https://github.com/jordanbaird/Ice")!` | → `"https://github.com/pdurlej/fire"` (contribute button / issues URL derived from this) |
| `Ice/Settings/SettingsPanes/AboutSettingsPane.swift` | 29 | `URL(string: "https://icemenubar.app/Donate")!` | Keep, replace, or remove the "Support Ice" button. Recommendation: remove the button entirely until we have our own donate destination; do not silently redirect the user's "Support Ice" click to a different project. |

There is **no entitlements file** — both targets set `CODE_SIGN_ENTITLEMENTS = "";` (pbxproj lines 416, 449), so no entitlements changes are needed beyond the bundle ID flip itself.

The XPC service's own `Info.plist` (`MenuBarItemService/Resources/Info.plist`) is just an XPCService dict — it does not need editing; its bundle ID is set via build settings.

### 1.2 Build settings additions

`Info.plist` is generated (`GENERATE_INFOPLIST_FILE = YES`). Display name comes from `INFOPLIST_KEY_CFBundleDisplayName` / `INFOPLIST_KEY_CFBundleName`, neither of which is set today, so the bundle inherits `PRODUCT_NAME = $(TARGET_NAME)` = "Ice". To rename without renaming the target (which would touch hundreds of pbxproj entries), add to both Debug + Release configs of the app target:

```
INFOPLIST_KEY_CFBundleDisplayName = Fire;
INFOPLIST_KEY_CFBundleName = Fire;
INFOPLIST_KEY_NSHumanReadableCopyright = "Copyright © 2024 Jordan Baird. © 2026 Paweł Durlej. GPL-3.0.";
```

The bundle's *executable* and the on-disk `.app` will still be `Ice.app` until we rename the target. We can either:
- **A.** Leave the target named `Ice` and ship `Ice.app` with display name "Fire". Trade-off: confusing during dev only; users see "Fire" everywhere (Finder/Dock/menu bar use `CFBundleDisplayName`). Lowest risk.
- **B.** Rename target to `Fire`. Touches ~30 pbxproj entries, the scheme, and every `// Ice` file header. High churn, more diff conflicts when pulling from upstream.

**Recommendation: A** for the initial rebrand release. We can do B in a follow-up after the dust settles. The Xcode-project rename is purely cosmetic given (1) is already done.

### 1.3 User-visible "Ice" strings to rename → "Fire"

(All Swift files under `/Users/pd/Developer/fire/Ice/`.)

| File | Line | Current | New |
|---|---|---|---|
| `Settings/SettingsPanes/AboutSettingsPane.swift` | 88 | `Text("Ice")` (huge wordmark in About) | `Text("Fire")` |
| `Settings/SettingsPanes/AboutSettingsPane.swift` | 148 | `Button("Quit Ice")` | `Button("Quit Fire")` |
| `Settings/SettingsPanes/AboutSettingsPane.swift` | 161 | `Button("Support Ice", …)` | Remove button (see §1.1) |
| `Settings/SettingsView.swift` | 77 | `Text("Ice")` (sidebar header) | `Text("Fire")` |
| `UI/IceUI/IceWindow.swift` | 94 | `case .settings: "Ice"` (window title) | `case .settings: "Fire"` |
| `MenuBar/MenuBarManager.swift` | 276 | `NSMenu(title: "Ice")` (secondary context menu) | `NSMenu(title: "Fire")` |
| `MenuBar/MenuBarManager.swift` | 289 | `title: "Ice Settings…"` | `"Fire Settings…"` |
| `MenuBar/ControlItem/ControlItem.swift` | 503 | `NSMenu(title: "Ice")` (primary context menu) | `NSMenu(title: "Fire")` |
| `MenuBar/ControlItem/ControlItem.swift` | 506 | `title: "Ice Settings…"` | `"Fire Settings…"` |
| `Permissions/PermissionsView.swift` | 65 | `Text("Ice needs your permission to manage the menu bar.")` | `"Fire needs your permission to manage the menu bar."` |
| `Permissions/PermissionsView.swift` | 138 | `Text("Ice needs this to:")` | `"Fire needs this to:"` |
| `Permissions/PermissionsView.swift` | 170 | `CalloutBox("Ice can work in a limited mode without this permission.")` | replace `Ice`→`Fire` |
| `MenuBar/IceBar/IceBar.swift` | 33 | `self.title = "Ice Bar"` | `"Fire Bar"` (see §1.5) |
| `MenuBar/IceBar/IceBar.swift` | 347 | `"The Ice Bar requires screen recording permissions."` | `"Fire Bar"` |
| `MenuBar/IceBar/IceBar.swift` | 355 | `"Open Ice Settings"` | `"Open Fire Settings"` |
| `MenuBar/IceBar/IceBar.swift` | 362 | `"Ice cannot display…"` | `"Fire cannot display…"` |
| `MenuBar/Appearance/MenuBarAppearanceEditor/MenuBarAppearanceEditor.swift` | 49 | `"Ice cannot edit the appearance…"` | `"Fire cannot edit…"` |
| `Settings/SettingsPanes/MenuBarLayoutSettingsPane.swift` | 62 | `"Ice cannot arrange menu bar items…"` | `"Fire cannot arrange…"` |
| `Settings/SettingsPanes/GeneralSettingsPane.swift` | 78 | `Toggle("Show Ice icon", …)` | `"Show Fire icon"` |
| `Settings/SettingsPanes/GeneralSettingsPane.swift` | 84 | `LocalizedStringKey("Ice icon")` | `"Fire icon"` |
| `Settings/SettingsPanes/GeneralSettingsPane.swift` | 185 | `Toggle("Use Ice Bar", …)` | `"Use Fire Bar"` |
| `Settings/SettingsPanes/GeneralSettingsPane.swift` | 199–203 | "The Ice Bar's location changes…" / "…centered below the Ice icon" | `Ice → Fire` |
| `Settings/SettingsPanes/HotkeysSettingsPane.swift` | 40 | `Text("Enable the Ice Bar")` | `"Enable the Fire Bar"` |
| `MenuBar/IceBar/IceBarLocation.swift` | 26 | `case .iceIcon: "Ice icon"` | `"Fire icon"` (display string only; the enum case stays `.iceIcon`) |

Doc comments containing "Ice icon" / "Ice Bar" can be updated opportunistically — they are not user-visible but the inconsistency will be confusing to future readers. Suggest one cleanup pass after the rebrand commit lands.

**Log messages** (`Logger.error("Error decoding Ice icon: …")` in `Settings/Models/GeneralSettings.swift:112,144`) are user-visible in Console.app. Update them.

**Menu bar item image set:** `MenuBar/ControlItem/ControlItemImageSet.swift:16` has `case iceCube = "Ice Cube"`. This is a choosable icon style ("Ice Cube" is one of several built-in icon sets the user can pick for the menu-bar control item). Keep the case name; either keep the display string "Ice Cube" (it's a cute name and unambiguous in context) or rename to something fire-themed. **Recommendation: keep "Ice Cube" as a built-in icon name; it's a nice nod to the original.** No code-only change.

### 1.4 Internal class/file names containing "Ice"

`IceApp.swift`, `IceBar.swift`, `IceBarColorManager.swift`, `IceBarLocation.swift`, `IceWindow.swift`, `IceForm.swift`, `IceGradientPicker.swift`, `IceGroupBox.swift`, `IceMenu.swift`, `IcePicker.swift`, `IceSection.swift`, `IceSlider.swift`, `IceGradient.swift`, `IceColor.swift`, plus types: `IceWindowIdentifier`, `IceBarPanel`, `IceBarColorManager`, etc.

**Recommendation: leave them.** They are an internal naming convention ("Ice-prefixed UI primitives"). Renaming churns git blame on ~14 files, every callsite, and the pbxproj `PBXFileReference` section, for zero user-facing benefit. The names will read as charmingly anachronistic — like a `WebKit` class still being named `NSURL`-something — and that's fine.

Three exceptions worth doing in the rebrand commit because they are visible in logs or window identifiers:
- `IceWindowIdentifier.settings` raw value is `"settings"` — already neutral, no change.
- `Logger(category: "…")` calls — search for any with literal "Ice" (none found in this audit).
- `NSStatusItem.autosaveName` is `controlItem.identifier.rawValue` = `"Ice.ControlItem.Visible"` etc. (`MenuBar/ControlItem/ControlItem.swift:17–21`). These strings are the *autosave keys* — see §2.2 for why we must not rename them.

`MenuBar/MenuBarItems/MenuBarItemTag.swift:226` defines `static let ice = string(Constants.bundleIdentifier)`. `Constants.bundleIdentifier` becomes the new bundle ID automatically. The Swift identifier `ice` should stay — it's a namespace constant for "our own process's items," and changing it is a 1-LOC win not worth the renames at every call site. **Optional follow-up: rename `.ice` → `.app` or `.fire` in a cleanup PR.**

### 1.5 "Ice Bar" feature naming recommendation

**Rename to "Fire Bar."** Pros: consistent user vocabulary, easier docs, easier support, no "why is this called Ice when the app is Fire" question. Cons: ~6 string edits — already in the table above. Cost is minimal, benefit is real. Internal types (`IceBar`, `IceBarPanel`, `IceBarLocation`) can keep their Swift names.

### 1.6 Recommended rename order within the rebrand commit

1. `project.pbxproj` build settings (bundle IDs, display name keys).
2. `Info.plist` SUFeedURL + EDKey.
3. `Shared/Services/MenuBarItemService.swift` service name constant — must match the new XPC bundle ID or the host can't talk to the service.
4. UI strings (the table in §1.3).
5. AboutSettingsPane GitHub URL.

All in one commit so the build is consistent. Migration code lands separately, *before* this commit (see §8).

---

## 2. UserDefaults migration

### 2.1 What Ice persists

Ice has **no app group, no shared suite, no `UserDefaults(suiteName:)`, no `@AppStorage`**. Everything goes through `UserDefaults.standard`, which on a non-sandboxed app reads/writes the plist at `~/Library/Preferences/<bundle-id>.plist`. There are three classes of keys:

**(a) `Defaults.Key` enum** (`Ice/Utilities/Defaults.swift:139–196`). 30 keys, all UpperCamelCase string values (`ShowIceIcon`, `IceIcon`, `Hotkeys`, `MenuBarAppearanceConfigurationV2`, …) plus migration sentinels (`hasMigrated0_8_0` … `hasMigrated0_11_13_1`) and deprecated keys still present for cleanup. Values are: `Bool`, `Int`, `Double`, `String`, `[String: Any]`, `Data` (NSKeyedArchiver-encoded structs for icons, JSON-encoded structs for `MenuBarAppearanceConfigurationV2` and `Hotkeys`).

**(b) `ControlItemDefaults`** (`Ice/MenuBar/ControlItem/ControlItem.swift:611–699`). Reads/writes raw keys of the form `NSStatusItem Preferred Position <autosaveName>`, `NSStatusItem Visible <autosaveName>`, `NSStatusItem VisibleCC <autosaveName>`. The autosave name is the ControlItem identifier raw value: **`"Ice.ControlItem.Visible"`, `"Ice.ControlItem.Hidden"`, `"Ice.ControlItem.AlwaysHidden"`**. These keys store the **menu-bar layout** — the X position of each section divider, which is the data that lets a user's existing arrangement carry over. Values are `CGFloat` (position) and `Bool` (visible).

**(c) NSStatusItem's own private bookkeeping.** AppKit may write its own `NSStatusItem`-prefixed keys (length, etc.) under the same autosave names. We can't enumerate these; safest path is to copy *every* key in the source domain.

### 2.2 The autosave-name landmine

The control item identifier raw values (`"Ice.ControlItem.Visible"` etc.) are **stable strings used as part of UserDefaults keys**. If we rename them to `"Fire.ControlItem.Visible"`, every existing menu-bar layout breaks even for Ice users with no migration involved, because the post-rename app would look up the wrong key.

**Decision: do not rename the `ControlItem.Identifier` raw values.** They are not user-visible — they only appear in `~/Library/Preferences/<bundle>.plist` keys. The `Ice.` prefix is an implementation detail.

This also means: the migration in §2.3 must copy these `NSStatusItem … Ice.ControlItem.…` keys verbatim. A naïve "rename all keys" pass would corrupt the layout.

### 2.3 Migration algorithm

Run **once**, in `applicationWillFinishLaunching` (`Ice/Main/AppDelegate.swift:16`), *before* the existing `MigrationManager(appState:).migrateAll()` call. The existing manager assumes its keys live in `UserDefaults.standard`; we must have already populated them.

Sentinel: a new key `LegacyIceMigrationCompleted: Bool` in the *new* (Fire) domain. Never read or write this in the old domain — that would re-write the old plist for no reason and confuse a user who reinstalls Ice later.

```swift
// Ice/Utilities/LegacyMigration.swift  (NEW FILE)

import Foundation
import OSLog

enum LegacyMigration {
    private static let legacyBundleID = "com.jordanbaird.Ice"
    private static let sentinelKey = "LegacyIceMigrationCompleted"
    private static let logger = Logger(subsystem: "me.durlej.Fire", category: "LegacyMigration")

    /// Copies UserDefaults from the legacy `com.jordanbaird.Ice` domain into the
    /// current app's standard defaults. Runs at most once per Fire install.
    ///
    /// Safe to call unconditionally on every launch; bails out after the first run.
    static func runIfNeeded() {
        let std = UserDefaults.standard

        // Already migrated, or running under the legacy bundle ID itself
        // (defensive: avoids self-copy if someone manually re-flips the bundle ID).
        guard !std.bool(forKey: sentinelKey) else { return }
        guard Bundle.main.bundleIdentifier != legacyBundleID else {
            std.set(true, forKey: sentinelKey)
            return
        }

        // CFPreferences-level read: pulls the on-disk plist for the source
        // bundle without instantiating a UserDefaults that would also pick up
        // the global domain on top. We want only what's actually in that plist.
        guard let source = CFPreferencesCopyMultiple(
            nil,  // all keys
            legacyBundleID as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? [String: Any] else {
            logger.info("No legacy Ice preferences found; marking migration complete")
            std.set(true, forKey: sentinelKey)
            return
        }

        guard !source.isEmpty else {
            logger.info("Legacy Ice preferences empty; marking migration complete")
            std.set(true, forKey: sentinelKey)
            return
        }

        logger.info("Migrating \(source.count, privacy: .public) keys from \(legacyBundleID, privacy: .public)")

        // Copy verbatim. Includes the `NSStatusItem …` layout keys and the
        // Ice-era `hasMigrated0_8_0`…`hasMigrated0_11_13_1` sentinels — we want
        // those, otherwise MigrationManager.migrateAll() will re-run old
        // migrations against already-migrated data.
        for (key, value) in source {
            // Don't overwrite anything Fire itself has already written this
            // launch (notification authorization records, etc.). In practice
            // the standard suite is empty on first launch, so this is a no-op
            // safety net.
            guard std.object(forKey: key) == nil else { continue }
            std.set(value, forKey: key)
        }

        std.set(true, forKey: sentinelKey)
        logger.info("Legacy Ice migration complete")
    }
}
```

In `AppDelegate.applicationWillFinishLaunching`:

```swift
func applicationWillFinishLaunching(_ notification: Notification) {
    NSSplitViewItem.swizzle()
    LegacyMigration.runIfNeeded()           // ← NEW: must run before MigrationManager
    MigrationManager(appState: appState).migrateAll()
}
```

### 2.4 Why `CFPreferencesCopyMultiple` and not `UserDefaults(suiteName:)`

`UserDefaults(suiteName: "com.jordanbaird.Ice")` returns a suite that also reflects the global domain (`NSGlobalDomain`, registration domain, argument domain). Iterating its `dictionaryRepresentation()` would pull in dozens of `AppleLanguages`, `NSGlobalDomain` keys we don't want. `CFPreferencesCopyMultiple(nil, bundleID, currentUser, anyHost)` reads the persistent on-disk plist for exactly that bundle, nothing else. This is what we want.

(`currentHost` vs `anyHost`: Ice writes preferences with the default scope, which is `anyHost`. `MenuBarItemSpacingManager` uses `defaults … -currentHost -globalDomain` for separate NSStatusItem-spacing keys that live in the *global* domain — those are not affected by either the bundle-ID change or our migration. They stay where they are.)

### 2.5 Edge cases handled

| Case | Behaviour |
|---|---|
| Fresh install (no Ice ever installed) | `CFPreferencesCopyMultiple` returns nil. Sentinel set; no work. |
| Ice still installed alongside Fire | Migration runs once based on Ice's plist *at the moment Fire first launches*. If the user then uses Ice more and reconfigures, Fire does NOT re-sync. Documented as expected behaviour: Fire is a one-time clone of Ice's state, not a live mirror. |
| `Data` blobs (NSKeyedArchiver-encoded icons, JSONEncoder-encoded `MenuBarAppearanceConfigurationV2`, `Hotkeys`) | `CFPreferencesCopyMultiple` returns them as `Data`. `UserDefaults.set(_:forKey:)` stores them verbatim. Works. |
| Nested dicts / arrays of dicts (e.g. `Hotkeys` is stored as JSON-encoded `Data`, not a top-level dict — so this isn't actually a recursion case) | Copied as-is. |
| Pre-existing migration sentinels (`hasMigrated0_8_0` etc.) | Copied. Critical — without them, `MigrationManager.migrateAll()` would re-run 0.8.0 hotkey migration against already-modern data. |
| Layout keys (`NSStatusItem Preferred Position Ice.ControlItem.Visible` etc.) | Copied verbatim. `ControlItem` reads them by the same key on next launch and the layout reappears. |
| `MenuBarItemSpacingManager` settings | Live in `NSGlobalDomain -currentHost` (see `MenuBarItemSpacingManager.swift:67–72`), not in our bundle's plist. Not touched by bundle-ID change. No migration needed. |
| User had Ice's `hasMigrated…` sentinels missing for some reason | `MigrationManager` runs its own migrations after ours — correct behaviour. |

### 2.6 Verification before tag

1. Install Ice 0.11.x, configure 25+ menu bar items into hidden / always-hidden, set a custom Ice icon, bind two hotkeys.
2. Quit Ice. `defaults read com.jordanbaird.Ice > /tmp/ice-before.plist`.
3. Install Fire (different bundle ID). Launch. Onboarding shows TCC re-prompt.
4. After granting TCC, settings window should show the same hotkeys, custom icon, appearance config. Menu bar layout should match.
5. `defaults read me.durlej.Fire > /tmp/fire-after.plist`. Diff: only differences should be the sentinel `LegacyIceMigrationCompleted: 1` and any keys Fire wrote during onboarding.
6. Quit Fire, relaunch. Sentinel prevents re-migration; layout stable.

---

## 3. Keychain migration

**Ice does not use Keychain.** Grep across the entire repo for `Keychain`, `kSecAttrService`, `SecKeychain`, `kSecClass` returns zero matches in Swift source. Sparkle itself does not store credentials in Keychain (only EdDSA verifies updates, no auth). LaunchAtLogin uses `SMAppService` registration, not Keychain.

**No migration needed.** Document this in the migration code as a comment so future readers don't wonder why Keychain isn't covered.

---

## 4. TCC permissions

### 4.1 Why they re-prompt

The TCC database (`/Library/Application Support/com.apple.TCC/TCC.db` and `~/Library/Application Support/com.apple.TCC/TCC.db`) keys grants on the responsible bundle ID and the code signing identity. A new bundle ID is treated as a new app for TCC purposes, regardless of code signature, hardened runtime, or Team ID. There is no Apple-supported API to inherit TCC grants from another bundle ID.

Ice currently requests:
- **Accessibility** (`AXHelpers.isProcessTrusted(prompt: true)` in `Ice/Permissions/Permission.swift:135`) — required for `axuielement` queries of the menu bar.
- **Screen Recording** (`ScreenCapture.requestPermissions()` in `Ice/Permissions/Permission.swift:157`) — required to capture menu bar item images; optional ("limited mode" exists without it).

Fire will prompt for both anew on first launch.

### 4.2 Pre-detecting "this user had Ice"

We *can* heuristically detect "Ice has been installed on this machine" — the same signal we use for UserDefaults migration: a non-empty plist at `~/Library/Preferences/com.jordanbaird.Ice.plist`. We surface this to make the onboarding window friendlier:

```swift
var likelyMigratingFromIce: Bool {
    let path = ("~/Library/Preferences/com.jordanbaird.Ice.plist" as NSString)
        .expandingTildeInPath
    return FileManager.default.fileExists(atPath: path)
}
```

We **cannot** detect whether Ice had TCC permissions granted (TCC.db is SIP-protected). We can only assume that a user who configured Ice deeply (non-empty plist with custom hotkeys etc.) probably did grant them.

### 4.3 First-launch UX

The existing `PermissionsView` (`Ice/Permissions/PermissionsView.swift`) already handles "you need to grant these permissions" with a Quit button and a Continue button. **Augment it with a top banner shown only when `likelyMigratingFromIce` is true**, before the per-permission boxes.

```
┌──────────────────────────────────────────────────────────┐
│  Welcome to Fire                                         │
│                                                          │
│  Fire is the successor to Ice. Your settings, hotkeys,   │
│  and menu bar layout have been carried over.             │
│                                                          │
│  One thing macOS can't carry over: Fire needs its own    │
│  Accessibility and Screen Recording permissions, because │
│  macOS treats it as a brand-new app. Grant them below,   │
│  then quit Ice from its menu bar so the two don't fight  │
│  over your menu bar items.                               │
└──────────────────────────────────────────────────────────┘
```

The existing per-permission boxes (`PermissionsView.permissionBox`) already have "Grant Permission" buttons that open the right System Settings pane. No new code needed there.

Wording for the user-facing copy in the prompt itself (Apple's TCC dialog uses the app's `NSAccessibilityUsageDescription` / equivalent purpose strings — but for Accessibility and Screen Recording there is no purpose-string Info.plist key on macOS as of Sonoma+; the system uses a generic prompt. We do not need to edit the Info.plist for purpose strings.) The educational text lives in our own banner and in the existing `Permission.details` array, which already says e.g. "Get real-time information about the menu bar" — these don't need Fire-specific changes.

### 4.4 Detecting "Ice is still running"

`NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.jordanbaird.Ice" }` will find it. If present at first launch of Fire, show an additional warning: "Ice is currently running. Quit it before continuing, or both apps will try to control your menu bar." Optionally provide a "Quit Ice" button that calls `runningApp.terminate()`.

### 4.5 Disabling Ice's Login Item before Fire registers its own

If Ice's `LaunchAtLogin` was enabled, the user has an `SMAppService.mainApp` registration under `com.jordanbaird.Ice` (which will reboot Ice on next login even after Fire is installed). Fire cannot directly unregister another app's service. Best we can do:
- Detect Ice's app at `/Applications/Ice.app` (`FileManager.fileExists`).
- Show a one-time card in the onboarding window: "Ice was set to launch at login. We can't unregister it from Fire — open Ice once and disable its 'Launch at Login' toggle, then delete Ice.app." Provide buttons for both.

This is a minor cleanup, not a blocker. If both apps launch at login, the user sees two menu bar icons until they remove Ice.

---

## 5. Sparkle / auto-updates

### 5.1 Current state

`Ice/Resources/Info.plist:5–8` has `SUFeedURL = https://jordanbaird.github.io/ice-releases/appcast.xml` and `SUPublicEDKey = 3nfIGMOD8DALPE8vIdFo2tUOIVc2MVbzhc+2J9JLn+Q=`. `Ice/Main/Updates.swift` instantiates an `SPUStandardUpdaterController` and uses Sparkle's standard XPC-less in-process update flow. No app-side opt-outs.

### 5.2 Why we cannot piggyback Ice's feed

`https://jordanbaird.github.io/ice-releases/` is upstream's GitHub Pages site; we don't control it. The EdDSA public key in our Info.plist will reject any update signed by anyone other than upstream's private key. Even if upstream resumed shipping, those builds use Ice's bundle ID and would not be a valid replacement for Fire. **We must change SUFeedURL and rotate SUPublicEDKey.**

### 5.3 Options

**(a) Disable Sparkle, send users to GitHub Releases.** Pros: zero infra. Cons: no auto-update, no notification of new versions, breaks the existing "Automatically check for updates" toggle in About settings; users on 0.11.13 are stranded unless they happen to visit GitHub.

**(b) Host our own appcast on GitHub Pages.** Create `pdurlej/fire-releases` repo, enable Pages from `main`, ship a static `appcast.xml` updated by CI from `gh release` events using `generate_appcast` from Sparkle. URL: `https://pdurlej.github.io/fire-releases/appcast.xml`. Cost: free; CI script is ~30 lines.

**(c) Use Sparkle's GitHub Releases support.** Sparkle has no official first-party GitHub Releases integration. Third-party adapters exist (e.g. `feedparser`-style shims) but are unmaintained. Not recommended.

**Recommendation: (b).** Concrete steps:
1. Generate a new EdDSA keypair: `./bin/generate_keys` from the Sparkle distribution. Store the private key in 1Password; commit the public key to Info.plist.
2. Create `pdurlej/fire-releases` repo with a single `appcast.xml` stub.
3. Enable GitHub Pages from `main`, root.
4. Add a release-tag GitHub Action to `pdurlej/fire` that, on a new release, runs Sparkle's `generate_appcast` against the release artifacts, signs with the private key (read from repo secret), and commits the updated `appcast.xml` to `pdurlej/fire-releases`.
5. Update `Ice/Resources/Info.plist`:
   ```xml
   <key>SUFeedURL</key>
   <string>https://pdurlej.github.io/fire-releases/appcast.xml</string>
   <key>SUPublicEDKey</key>
   <string>NEW_KEY_HERE</string>
   ```

Existing Ice 0.11.x users (still on the upstream appcast) will not be auto-updated to Fire — they have to download Fire manually once. That is the inherent cost of changing bundle ID; nothing we can do about it without shipping a final Ice release through upstream's appcast that points users to Fire, which we don't control.

---

## 6. App icon

`Ice/Resources/Assets.xcassets/AppIcon.appiconset/` contains 10 PNGs:

```
icon_16x16.png       icon_16x16@2x.png
icon_32x32.png       icon_32x32@2x.png
icon_128x128.png     icon_128x128@2x.png
icon_256x256.png     icon_256x256@2x.png
icon_512x512.png     icon_512x512@2x.png
```

Plus `Contents.json` mapping size+scale → filename. Replacement is a straight drop-in: same 10 filenames, same dimensions (16/32/128/256/512 at 1x and 2x = 32/64/256/512/1024 px effective). No `Contents.json` edit needed if filenames are preserved.

The Asset Catalog reference is `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` (pbxproj lines 414, 447). No rename needed.

Out of scope for this plan: actual icon artwork (separate brief).

---

## 7. Launch agent / LSUIElement / login item

### 7.1 LSUIElement

Both Debug + Release configs set `INFOPLIST_KEY_LSUIElement = YES` (pbxproj lines 431, 464). This makes Ice a menu-bar-only app with no Dock icon. Same setting carries over for Fire automatically (it's a build-setting key, not a bundle-ID-keyed one). No change needed.

### 7.2 Launch agent / SMAppService

Ice uses Sindre Sorhus's [`LaunchAtLogin`](https://github.com/sindresorhus/LaunchAtLogin-Modern) library (`Ice/Settings/SettingsPanes/GeneralSettingsPane.swift:6,63`), which under the hood uses `SMAppService.mainApp.register()` (macOS 13+). `SMAppService.mainApp` keys on the calling app's bundle ID, so:
- Fire's first registration is a fresh entry under `me.durlej.Fire` — no conflict.
- Ice's previous registration under `com.jordanbaird.Ice` persists in launchd until either Ice runs again and unregisters it, or the user manually removes it from System Settings → General → Login Items.

We cannot unregister another app's `SMAppService` entry from Fire (sandbox semantics — even our non-sandboxed app has no API to do this).

**What we do:** during first-launch onboarding, if `FileManager.default.fileExists(atPath: "/Applications/Ice.app")`, show a card:

> "We found Ice on your system. Drag it to Trash to stop it from launching at login, or open Ice and turn off its 'Launch at Login' toggle. (Fire's own Launch at Login setting is on by default — toggle it in General if you don't want that.)"

Set Fire's `LaunchAtLogin` default to **the value Ice had**. We can detect that: `SMAppService.mainApp.status` only reports the *current* app's status. There is no API to query another bundle's status. But we already migrated UserDefaults, and `LaunchAtLogin-Modern` does *not* store its state in UserDefaults — it queries `SMAppService` directly. So Fire's `LaunchAtLogin` defaults to its library default (off) on first launch. **Decision: leave it off, mention in the onboarding card that they can re-enable in General settings.** Better than silently auto-enabling.

### 7.3 XPC service

`MenuBarItemService.xpc` is an embedded XPC service inside the app bundle. Its bundle ID (`com.jordanbaird.Ice.MenuBarItemService` → `me.durlej.Fire.MenuBarItemService`) and its Mach service name (`MenuBarItemService.name` constant in `Shared/Services/MenuBarItemService.swift:9`) must match. The XPC service is loaded on-demand by the host app via `NSXPCConnection(serviceName:)` — it doesn't register with launchd globally, so there's no stale-launchd-entry concern. No migration needed; just the bundle-ID + constant change in §1.

---

## 8. Sequence of commits

Each commit must build and not break existing Ice users (until commit 2, which is the explicit cut-over). Each commit message starts with a `fire/` prefix for the rebrand series.

### Commit 1 — `fire/migration: add dormant legacy UserDefaults migration`

- Add `Ice/Utilities/LegacyMigration.swift` exactly as in §2.3.
- Add the `LegacyMigration.runIfNeeded()` call to `AppDelegate.applicationWillFinishLaunching` before `MigrationManager(...).migrateAll()`.
- Bundle ID is still `com.jordanbaird.Ice`. The migration's `guard Bundle.main.bundleIdentifier != legacyBundleID else { ...; return }` short-circuits and marks the sentinel as done. No behavior change for existing Ice users.
- Why land this first: lets us ship a `0.11.13-fire.X` build with the migration code path *exercised* (sentinel set) on every existing Ice install. When commit 2 flips the bundle ID, those installs become Fire installs — but the standard suite is now a new file (different bundle ID = different plist), the sentinel is gone, and the migration runs against the now-old `com.jordanbaird.Ice.plist`. Exactly the flow we want.
- Test: build, run, verify nothing changes for existing users, verify `defaults read com.jordanbaird.Ice LegacyIceMigrationCompleted` returns 1.

### Commit 2 — `fire/rebrand: flip bundle identifier and display name`

Single commit, must land atomically:
- `Ice.xcodeproj/project.pbxproj`:
  - `PRODUCT_BUNDLE_IDENTIFIER = me.durlej.Fire;` (both configs, app target)
  - `PRODUCT_BUNDLE_IDENTIFIER = me.durlej.Fire.MenuBarItemService;` (both configs, XPC target)
  - Add `INFOPLIST_KEY_CFBundleDisplayName = Fire;` and `INFOPLIST_KEY_CFBundleName = Fire;` to both app-target configs.
  - Update `INFOPLIST_KEY_NSHumanReadableCopyright` to "Copyright © 2024 Jordan Baird. © 2026 Paweł Durlej. GPL-3.0." per §1.2.
- `Shared/Services/MenuBarItemService.swift:9`: `static let name = "me.durlej.Fire.MenuBarItemService"`.
- All UI string changes from §1.3 (Ice → Fire wherever user-visible). This is one large diff but mostly mechanical; review carefully for false positives ("Ice Cube" stays).
- `Ice/Settings/SettingsPanes/AboutSettingsPane.swift:20` GitHub URL → `pdurlej/fire`.
- Remove the donate button (line 161–163) per §1.1.
- Update `Ice/Permissions/PermissionsView.swift` with the §4.3 banner shown only when `likelyMigratingFromIce`. Add helper for the detection logic.
- Add the "Ice is running" warning and "Ice.app is installed" card to PermissionsView per §4.4 and §7.2.
- Test: build and run on a clean Mac with no Ice ever installed (should look like fresh Fire). Then run on a Mac with a pre-existing Ice install (should migrate, show the onboarding banner, re-prompt for TCC).

### Commit 3 — `fire/rebrand: rename Ice Bar feature to Fire Bar`

Already included in Commit 2's string edits (§1.3 covers Ice Bar strings). If we want to land it separately for cleaner review, split out:
- `Ice/MenuBar/IceBar/IceBar.swift` lines 33, 347, 355, 362.
- `Ice/MenuBar/IceBar/IceBarLocation.swift:26`.
- `Ice/Settings/SettingsPanes/GeneralSettingsPane.swift:185, 199–203`.
- `Ice/Settings/SettingsPanes/HotkeysSettingsPane.swift:40`.

**Recommendation: keep with Commit 2.** Splitting fragments the user-visible rebrand across two release tags, which is worse.

### Commit 4 — `fire/icon: replace AppIcon.appiconset with Fire artwork`

Drop 10 new PNGs into `Ice/Resources/Assets.xcassets/AppIcon.appiconset/` overwriting the existing files. No code change. Verify with `xcrun actool` that the iconset is valid.

### Commit 5 — `fire/updates: point Sparkle at our own appcast`

- `Ice/Resources/Info.plist`:
  - `SUFeedURL` → `https://pdurlej.github.io/fire-releases/appcast.xml`
  - `SUPublicEDKey` → new public key
- Set up `pdurlej/fire-releases` repo + Pages + release-tag CI (§5.3). This is out-of-tree work but must be done before tagging the first Fire release; otherwise the auto-updater hits a 404.

### Commit 6 — `fire/docs: update README, FORK.md, frequent issues`

`README.md`, `FORK.md`, `FREQUENT_ISSUES.md` all have `jordanbaird/Ice` references. Update README to mention "Fire (formerly Ice)" with the migration story; keep FORK.md's history but add a "Phase 4 complete: rebrand shipped in 0.11.13-fire.4" entry; update download URLs.

### Commit 7 — `fire/release: bump version, write release notes`

- `MARKETING_VERSION = "0.11.13-fire.4"` (or whatever; pick the next available tag in our scheme) in pbxproj.
- Write release notes covering: rebrand, migration of layout/settings/hotkeys, TCC re-prompt, optional Ice cleanup steps.
- Tag `v0.11.13-fire.4`, build, notarize, upload to GitHub Releases. The release-tag CI builds the appcast automatically.

---

## 9. Risk register

| # | Risk | Likelihood | Impact | Mitigation / Test |
|---|---|---|---|---|
| R1 | Layout corruption after migration: `NSStatusItem Preferred Position Ice.ControlItem.…` keys don't round-trip cleanly (e.g. type loss CGFloat→Double) | Low | High — user sees menu bar reset to defaults | `CFPreferencesCopyMultiple` returns `Any` (CFNumber), `UserDefaults.set` accepts and re-serialises as the same type. Manual side-by-side test (§2.6). |
| R2 | TCC re-prompt confuses users, they think Fire is malware | Med | Med — bad reviews, drop-off | Onboarding banner (§4.3) explains *why*. README and release notes call it out. |
| R3 | Both Ice and Fire run simultaneously, fight over menu bar items | Med | Med | Detect Ice in runningApplications, show warning + "Quit Ice" button (§4.4). |
| R4 | Ice's login-item registration persists, Ice keeps relaunching after Fire is installed | Med | Low — visible but recoverable | Onboarding card explains how to remove (§7.2). |
| R5 | `MigrationManager.migrateAll()` re-runs against already-migrated data because we forgot to copy the `hasMigrated…` sentinels | Low | High — data shape gets mangled | Covered: §2.3 copies *all* keys including sentinels. Test: post-migration `defaults read me.durlej.Fire hasMigrated0_11_13_1` should be 1. |
| R6 | EdDSA key in Info.plist rejects valid update because we forgot to ship the matching private key in CI | Low | High — auto-update never works | CI test: dry-run `generate_appcast` against a test build, verify Sparkle accepts the signature. |
| R7 | XPC service ID mismatch between bundle ID and Mach service name → menu-bar items don't render on macOS 26 | Low | High — broken core feature on Tahoe | Covered: §1.1 calls out the three places that must match (pbxproj × 2 + MenuBarItemService.name). Build-time grep check in CI. |
| R8 | User had Ice's icon set to a custom image; the encoded `Data` references a file path that no longer exists | Low | Low — falls back to default | Existing code in `GeneralSettings.swift` already logs decode errors and falls back. No action. |
| R9 | Apple Notarization rejects new bundle ID because of Team ID change | Low | High — can't ship | Notarize from same Apple Developer account as Ice fork's existing tags. Smoke-notarize a `0.11.13-fire.4-rc1` build a week before tag. |
| R10 | A future Ice release (if upstream revives) under bundle ID `com.jordanbaird.Ice` would not be detected as a conflict, and our migration would run again only if user removed `LegacyIceMigrationCompleted` sentinel | Low | Low | Document. Sentinel is the one-shot guard by design. |
| R11 | Ice "Ice Cube" image set option is renamed and user has it selected → falls back to default | Low | Low | Per §1.3, **don't rename** the case or its display string. No action. |
| R12 | `MenuBarItemTag.Namespace.ice` constant points to the new bundle ID after rebrand, breaking item-identity for any item the user tagged before rebrand under the old `com.jordanbaird.Ice` namespace | Med | Med — user's custom tags on menu bar items might forget which app the item belongs to | Investigate before tagging: read `MenuBarItemTag` encode/decode and check whether tags are persisted with the bundle ID baked in. If yes, add a tag-migration pass to LegacyMigration that rewrites `com.jordanbaird.Ice` → `me.durlej.Fire` inside any persisted tag data. (Not yet audited — flagged.) |

### Pre-tag verification checklist

- [ ] §2.6 layout migration test passes with a 25-item Ice install.
- [ ] R3: launch Fire while Ice is running, confirm warning appears.
- [ ] R6: appcast.xml generates and validates, test Mac with Fire 0.11.13-fire.3 picks up a fake 0.11.13-fire.4-rc1 update.
- [ ] R7: `nm -m /Applications/Fire.app/Contents/MacOS/Ice | grep -i menubaritemservice` references the new ID.
- [ ] R9: notarization round-trip on the candidate build.
- [ ] R12: read `MenuBarItemTag.swift` end-to-end, decide if tag rewrite is needed.
- [ ] Sanity: launch Fire on a Mac that has never had Ice, confirm normal first-launch flow (no migration banner, fresh permissions prompt, default layout).
- [ ] Sanity: launch Fire on a Mac that has Ice with default settings (empty hotkeys, default appearance), confirm migration is a no-op visually and the user still has to grant TCC.

---

## 10. Open questions for the user

1. **App-store-style donate destination.** What URL replaces `https://icemenubar.app/Donate`? If "none for now," confirm the button removal in §1.1.
2. **Apple Developer Team ID.** The notarization step assumes Fire is signed with the same Team ID as the most recent `0.11.13-fire.X` build. Confirm; if different, R9 changes.
3. **Where the Sparkle EdDSA private key lives.** Recommend a 1Password vault entry shared with the release-CI role.
4. **AppIcon brief timing.** Commit 4 needs the artwork; if it's not ready, we ship commits 1–3 + 5–7 first and the icon arrives in a follow-up `0.11.13-fire.5`. The display name "Fire" with the old Ice icon is OK as a stopgap.
