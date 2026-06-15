# Fire (Ice fork) — Engineering Roadmap

Owner: pdurlej (solo). Repo: github.com/pdurlej/fire-from-ice. Local: `/Users/pd/Developer/fire`. Branch: `fire/main` (based on `upstream/macos-26`).
Status as of 2026-05-24: PR #944 (CompactSlider API fix) cherry-picked, fire/main builds against upstream macos-26 baseline.

> **Update 2026-06-10:** this document is a historical planning snapshot. Much of it shipped: signed/notarized CI DMGs, Sparkle appcast, the MCP server (fire.6–fire.8), AI Quotas (fire.9.x), and trigger conditions — shipped as **AI-Native Automations** in fire.10 (`set_trigger`/`list_triggers`/`remove_trigger` + Settings → Automations). Current state lives in [HANDOFF.md](HANDOFF.md).

---

## 1. Executive Summary

**The bet.** Ship a Tahoe-stable, signed Ice build within ~3 weeks, then absorb 0.12.0 work and the four meaningful community PRs by week 6. After that, rebrand to **Fire** with a real first-launch migration so existing Ice users move over without losing layouts. The differentiator vs. Bartender 6 is **scale**: every original feature (profiles, trigger conditions, sensible new-icon defaults, config import/export) is aimed at people with 25+ menu bar items where Bartender starts dropping items, mis-rendering on multi-display, or just freezing on space switches. Free, open, GPL-3.0.

**The bottleneck.** Owner has macOS 26.5 with command-line tools only — **no full Xcode locally**. Every build, every signing, every notarization happens on GitHub Actions. This forces three disciplines: (a) the CI pipeline IS the build environment, so `build-dmg.yml` is critical-path Phase 0 infrastructure; (b) iteration is slow (5–10 min per CI cycle), so changes go in batches per branch, not commit-by-commit; (c) all "did I break it?" answers come from CI artifacts + user reports, never from a local debugger. Plan accordingly: every phase ends with a tagged pre-release the owner installs and dogfoods for ~48h on their own 25+ item menu bar before declaring done.

**The differentiator.** Bartender 6 is closed-source, $20, no dev presence since the 2024 ownership-change drama, broken on Tahoe for multi-display power users. Fire will be free, GPL, Tahoe-native, and explicitly built for the long-tail of heavy users instead of the median 8-item bar.

---

## 2. Phase 0 — Foundation (current sprint, days 1–4)

**Goal:** prove we can produce a notarized DMG from CI off a tag push, with no dev account, on `fire/main` HEAD.

**Status snapshot:**
- fire/main is rebased on upstream/macos-26 (commit `bdb2884`).
- PR #944 (CompactSlider fix) merged as `0a76e71`.
- FORK.md written and committed.
- Bundle ID still `com.jordanbaird.Ice` (Phase 1 keeps it; Phase 4 changes it).
- Marketing version: `0.11.13-dev.2a`, build `1121` (`Ice.xcodeproj/project.pbxproj` lines 436, 469).
- Sparkle is wired up at `Ice/Main/Updates.swift` pointing at `jordanbaird.github.io/ice-releases/appcast.xml` (`Ice/Resources/Info.plist`).

### 0.1 Extract `build-dmg.yml` from upstream PR #612 (day 1)

PR #612 ("Per-display configuration") includes a `build-dmg.yml` GitHub Actions workflow that the upstream PR author wrote to ship test builds. We want the workflow, not the feature code.

- Fetch the workflow file only: `gh pr view 612 --repo jordanbaird/Ice --json files | jq '.files[] | select(.path | contains("workflows"))'`.
- Save to `/Users/pd/Developer/fire/.github/workflows/build-dmg.yml`.
- Adjust inputs:
  - Trigger on `push: tags: ['v*-fire.*']` and `workflow_dispatch`.
  - `macos-26` runner image (default runner has Xcode 26 from late 2025).
  - Build command: `xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Release -derivedDataPath build` — confirm the scheme exists in `Ice.xcodeproj/xcshareddata/xcschemes/Ice.xcscheme` (it does).
  - Sign step: ad-hoc (`codesign --force --deep --sign -`) for now. Notarization is Phase 4.
  - Package step: `create-dmg` or hdiutil. Upload via `softprops/action-gh-release`.
- Smoke check the YAML with `actionlint` before pushing.

**Decision point — Signing identity.** Three options:
1. **Ad-hoc signed only.** Free. Users must right-click → Open the first time, and on every update Gatekeeper re-prompts. Sparkle updates work but feel scary.
2. **Apple Developer ID ($99/yr).** Required for proper notarization + smooth Sparkle. Real money for a free tool.
3. **Self-signed with downloaded cert install instructions.** Worst UX, skip.

Recommendation: **start with (1) for `0.11.13-fire.0..fire.4`** (Phase 0 + Phase 1). Re-evaluate before rebrand. If the user base hits ~50 active installs by Phase 3, owner buys (2) and rolls it in at the rebrand boundary where TCC re-prompts happen anyway.

### 0.2 Tag `v0.11.13-fire.0` for CI smoke test (day 2)

- Bump `MARKETING_VERSION` in `Ice.xcodeproj/project.pbxproj` from `0.11.13-dev.2a` → `0.11.13-fire.0`. Bump `CURRENT_PROJECT_VERSION` from 1121 → 1122.
- One commit: "Bump version to 0.11.13-fire.0 for CI smoke test".
- `git tag v0.11.13-fire.0 && git push origin v0.11.13-fire.0`.
- Watch the run. Expected failures: missing `DEVELOPMENT_TEAM` (it's `K2ATHQPJDP` from upstream — change to empty string for ad-hoc); `CODE_SIGN_STYLE = Automatic` won't work in CI without team — switch to `Manual` with `-` identity.
- DoD: a `.dmg` artifact appears on the GitHub release page; owner downloads, opens, launches Ice, grants permissions, sees menu bar items.

### 0.3 Sparkle update strategy decision (day 3)

**Decision point — three options:**
1. **Disable Sparkle entirely for the fork.** Remove `SUFeedURL` from `Ice/Resources/Info.plist`, gate `UpdatesManager.performSetup` with `#if false` or `Bundle.main.bundleIdentifier == "com.jordanbaird.Ice"` check that yields no-op for our builds later. Releases go through GitHub-only; users update by re-downloading.
2. **Repoint Sparkle to our own appcast.** Host `appcast.xml` on `pdurlej.github.io/fire-releases/appcast.xml` (GitHub Pages, free). Generate a new EdDSA keypair, replace `SUPublicEDKey` in Info.plist, keep the private key in a GitHub Actions secret (`SPARKLE_PRIVATE_KEY`). Each release run signs the DMG with `Sparkle/bin/sign_update`, writes a new `<item>` to appcast.xml, commits + pushes Pages.
3. **Leave Sparkle pointed at jordanbaird's appcast.** Wrong. We'd push fake "updates" by accident or get downgraded when upstream uploads.

Recommendation: **(2) appcast, set up in Phase 0 day 3–4.** It's the only one consistent with "this is a real fork that ships releases." Cost is one afternoon and one ed25519 keypair. The CI workflow can grow a `release-appcast` job that runs after the DMG step.

Concrete tasks:
- Generate keys: `sparkle/bin/generate_keys` → public goes to `Ice/Resources/Info.plist`, private goes to GH secret.
- Create `pdurlej/fire-releases` repo with `appcast.xml` skeleton and Pages enabled.
- Add `release-appcast.yml` (or extend `build-dmg.yml`) that, on `v*-fire.*` tag, generates the `<item>` block (version, length, ed-signature, release-notes-link) and pushes to `fire-releases`.
- Sparkle config in `Updates.swift` stays as-is — only the URL and key change.

### 0.4 Sprint deliverables checklist

- [ ] `.github/workflows/build-dmg.yml` committed, green run on tag push.
- [ ] `.github/workflows/release-appcast.yml` (or merged into build-dmg) green.
- [ ] `Info.plist` SUFeedURL/SUPublicEDKey updated.
- [ ] `pdurlej/fire-releases` repo exists with empty appcast.
- [ ] `v0.11.13-fire.0` tag published; DMG installable; ad-hoc signed; Sparkle "check for updates" no-ops cleanly against empty appcast.
- [ ] Owner has installed it on real machine for 24h, files any regressions vs. `0.11.13-dev.2`.

---

## 3. Phase 1 — Tahoe Stability (week 2, 3–5 days)

**Goal:** ship `v0.11.13-fire.1` as a real "stable on Tahoe" release that closes upstream issue #760 in spirit (we can't close it, but we point sufferers at our DMG).

### Cherry-pick order (engineered around conflict topology)

Three known conflict clusters:
- **Cluster A: MenuBarItemManager** — #903 and #941 both touch `Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift`.
- **Cluster B: General settings pane** — #612 and #795 both add toggles to `Ice/Settings/SettingsPanes/GeneralSettingsPane.swift` (and #612 also restructures Model in `GeneralSettings.swift`).
- **Cluster C: EventManager / HIDEventManager** — #612 and #667 both touch event handling. Note that on `macos-26` baseline this file was renamed `EventManager → HIDEventManager` (commit `f8828cd`). PRs filed against older bases will fail to apply cleanly; we rewrite the patches against the new filename.

Pick order (small → large, isolate clusters):

1. **#928** (smallest, isolated bug fix — confirm scope via `gh pr view 928 --repo jordanbaird/Ice`). Branch: `merge/pr-928-shortdesc`. Cherry-pick, push, CI green, merge to fire/main.
2. **#922** (also isolated). Same flow.
3. **#804** (utility/quality). Same flow.
4. **#945** (also small). Same flow.
5. **#903** (Cluster A first half — Tahoe-specific MenuBarItemManager fix). Sole owner of MenuBarItemManager edits in this batch. Land. CI.
6. **#941** (Cluster A second half — notch-aware auto-hide). Now rebased on top of #903. Will likely conflict in MenuBarItemManager around the same hunks. Resolve manually: read both PRs, decide composition. **This is the biggest manual integration cost in Phase 1.**

We deliberately do NOT include in Phase 1: #612 (large feature, Phase 3), #795 (depends on #612 General settings restructure, Phase 3), #667 (Cluster C with #612, Phase 3).

### Per-PR sprint motion

For each PR:
```
git fetch upstream pull/NNN/head:merge/pr-NNN-short
git checkout fire/main
git checkout -b integrate/pr-NNN
git merge --no-ff merge/pr-NNN-short      # or cherry-pick if PR is single-commit
# resolve conflicts; run swiftlint locally if possible
git push origin integrate/pr-NNN
gh pr create --base fire/main --head integrate/pr-NNN  # self-merge for trail
# wait for CI green
gh pr merge --squash --delete-branch
```

The self-PR is overhead but creates a record (with the upstream PR # in the title) that makes attribution and bisecting later trivial.

### Sprint deliverables

- [ ] All six PRs merged into `fire/main`.
- [ ] `MARKETING_VERSION` → `0.11.13-fire.1`, build → 1123.
- [ ] Tag `v0.11.13-fire.1`, CI green, DMG published, appcast updated.
- [ ] Owner dogfoods 48h. Smoke tests: enable/disable hide, IceBar on each display, restart Mac, switch spaces, multi-monitor with notch.
- [ ] Release notes on GitHub linking back to each cherry-picked upstream PR with credit to original author.
- [ ] Post once in upstream #760 thread: "If you want a Tahoe-stable build today, this fork is shipping releases. Not affiliated with @jordanbaird." Keep it short; don't evangelize, just inform.

---

## 4. Phase 2 — 0.12.0 Convergence (week 3, 2–4 days)

**Revised understanding from local analysis.** Per `git cherry fire/main upstream/0.12.0` the commits are patch-equivalent (because `macos-26` already merged 0.12.0 work in via `f24e08a`), but `git diff --name-only upstream/0.12.0 fire/main` shows 216 files differ with ~12k inserted lines, including these files **unique to 0.12.0** (missing in fire/main):

- `Ice/MenuBar/Search/MenuBarSearchModel.swift`
- `Ice/MenuBar/Search/MenuBarSearchPanel.swift`
- `Ice/MenuBar/Appearance/MenuBarAppearanceEditor/MenuBarAppearanceEditorPanel.swift`
- `Ice/MenuBar/Appearance/MenuBarOverlayPanel.swift`

So Phase 2 is NOT 37 commits; it is **importing the search-panel feature and the appearance-editor refactor** from `upstream/0.12.0` onto our macos-26-derived baseline. Smaller than originally feared.

### Strategy: merge commit, not rebase

Rationale: `fire/main` has already diverged with our own work (FORK.md, PR #944, version bumps, the six PR merges from Phase 1). Rebasing onto 0.12.0 would re-write all those commits and lose the cherry-pick trail. A merge commit preserves history and gives one bisect point if something breaks.

```
git checkout fire/main
git checkout -b integrate/0.12.0-merge
git merge upstream/0.12.0
# expect conflicts in: Ice/MenuBar/IceBar/IceBar.swift,
#   Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift,
#   Ice/MenuBar/LayoutBar/LayoutBarPaddingView.swift,
#   Settings panes that #803 and 0.12.0 both touched
# resolve, keeping fire/main as "ours" for project.pbxproj version fields
```

### Specific conflict areas to expect

- **`Ice.xcodeproj/project.pbxproj`** — version + build number lines. Always take ours.
- **`Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift`** — 0.12.0 did a refactor; we've layered Phase 1 PRs #903 and #941 on top. Merge manually with a brief comment per hunk.
- **`Ice/MenuBar/Search/`** — entire new files; take 0.12.0 wholesale.
- **`Ice/MenuBar/Appearance/`** — refactor + new files; take 0.12.0 with care that nothing in `MenuBarAppearance.swift` references symbols we removed.
- **`.github/workflows/lint.yml`** — we may have edited it; manual merge.
- **`.swiftlint.yml`** — same.

### Definition of done

- [ ] Branch `integrate/0.12.0-merge` builds in CI.
- [ ] Manual test: search panel opens with hotkey, appearance editor renders correctly.
- [ ] Merged via merge commit to fire/main.
- [ ] Bump to `0.12.0-fire.1` (note version family change).
- [ ] Tag, DMG, appcast.
- [ ] Owner dogfoods 48h.

### Decision point — `upstream/profiles` branch

`upstream/profiles` (last commit `517b7df Merge branch '0.12.0' into profiles`) was the never-finished profiles work for upstream issue #26. It is based on 0.12.0. Decision: **do not pull it in Phase 2**. Evaluate in Phase 5 as a starting point for our own profiles work — likely we cherry-pick the data-model commits and rewrite the UI.

---

## 5. Phase 3 — Community Feature PRs (weeks 4–6, per-PR sprints)

Each PR gets its own short sprint (2–4 days), its own integration branch, its own tagged pre-release (`0.12.0-fire.2`, `.3`, `.4`, `.5`).

### 5.1 PR #795 — Auto IceBar by screen width (sprint, 2 days)

What it does: when active screen width is below a configurable threshold, IceBar opens instead of expanding the menu bar inline. Useful on laptops + external 4K mixed setups.

Files touched: `Ice/Settings/SettingsPanes/GeneralSettingsPane.swift`, `Ice/Settings/Models/GeneralSettings.swift`, `Ice/MenuBar/IceBar/IceBar.swift`.

Risk: low. Standalone feature, conflicts only with Phase 1 work in GeneralSettings. Likely needs trivial rebase since we now have 0.12.0's restructured settings views.

DoD: Tag `0.12.0-fire.2`. Manually toggle threshold on a 13" MacBook + 32" external, verify behavior.

### 5.2 PR #612 — Per-display configuration (sprint, 4 days — largest)

What it does: configuration is keyed per-display (so the layout you set on a 32" external doesn't get re-applied when you undock). Closes upstream #223 ("Ice Bar only on built-in display").

Files touched: large — GeneralSettings + new per-display data model + IceBar display detection + EventManager (now HIDEventManager for us). This is the PR we extracted `build-dmg.yml` from in Phase 0.

**Conflict expected against #795** (we just landed). Both add settings UI; both add per-display considerations. Land #612 second precisely because #795 is smaller — rebase #612's branch on the post-#795 tree, hand-merge the GeneralSettingsPane hunks.

Risk: medium-high. UserDefaults schema changes. Existing user configs may need a migration shim:
- Detect old schema: top-level `iceBarLocation: String` instead of `iceBarLocations: [String: String]` keyed by display UUID.
- On first launch with new build: read old key, write under "main display" UUID, leave old key for one release in case of downgrade.

Concrete file: add `Ice/Settings/Models/SettingsMigration.swift` (new) called from `AppDelegate.applicationDidFinishLaunching` before `AppState.performSetup`.

DoD: Tag `0.12.0-fire.3`. Dogfood with at least one undock-and-redock cycle.

### 5.3 PR #941 — Notch-aware auto-hide (sprint, 2 days)

Already partially handled if we landed #941 in Phase 1. If we deferred (the conflict with #903 was too messy), this is the sprint to land it cleanly atop the post-#612 tree.

DoD: Tag `0.12.0-fire.4`. Test on actual notched MacBook.

### 5.4 PR #667 — Multimonitor single space fix (sprint, 2 days)

What it does: fixes IceBar appearing on the wrong display when "displays have separate spaces" is off in System Settings.

Files touched: HIDEventManager (Cluster C), IceBar window placement.

Conflict expected with #612's per-display work — both touch display-identity code. Resolve by treating #612's per-display abstraction as canonical and rewriting #667's logic to use the new APIs.

DoD: Tag `0.12.0-fire.5`. Final Phase 3 release.

### 5.5 At end of Phase 3

We have a Tahoe-stable, feature-rich Ice fork shipping under the **original bundle ID** `com.jordanbaird.Ice`. Anyone with upstream Ice installed has been auto-updated through Sparkle's normal path the whole time (assuming they're pointed at our appcast — which we have to think about; this is the appcast-takeover decision below).

**Decision point — appcast targeting upstream users.** Two options:
1. **Our appcast only.** Existing upstream-installed users never find us unless they manually download our DMG. Slow adoption, but no "we hijacked your update channel" optics.
2. **Promote via upstream issue #760 + #823 only.** Same as (1) effectively, plus we make our existence known.

We do NOT (a) somehow redirect upstream's appcast to ours — that would require write access we don't have. (b) ship a build that silently rewrites `SUFeedURL` of existing installs — that would be hostile.

Recommendation: (2). Be loud but honest. Post in upstream threads, link to releases page, let users opt in.

---

## 6. Phase 4 — Rebrand to Fire (weeks 7–8, 5–8 days — most complex)

This is the highest-risk phase because it touches identity, permissions, and update channels simultaneously. Plan it as **one branch, one PR, one tag**: do not partially rebrand.

### 6.1 Inventory of identity touch-points (day 1)

Grep results from local repo (verified):
- `Ice.xcodeproj/project.pbxproj` lines 437, 470: `PRODUCT_BUNDLE_IDENTIFIER = com.jordanbaird.Ice` → `me.durlej.Fire`.
- `Ice.xcodeproj/project.pbxproj` lines 490, 516: `com.jordanbaird.Ice.MenuBarItemService` → `me.durlej.Fire.MenuBarItemService`.
- `Shared/Services/MenuBarItemService.swift:9`: `static let name = "com.jordanbaird.Ice.MenuBarItemService"` → `"me.durlej.Fire.MenuBarItemService"`.
- `Ice/Settings/SettingsPanes/AboutSettingsPane.swift`: "Ice" string literals — rename to "Fire".
- `Ice.xcodeproj/project.pbxproj` MARKETING_VERSION → `1.0.0-fire.0` (start fresh in Fire's own version line, drop the `0.12.0-fire.N` chain).
- `Ice.xcodeproj/project.pbxproj` PRODUCT_NAME → `Fire`. **This renames the binary and the .app bundle on disk.**
- Info.plist `CFBundleName`, `CFBundleDisplayName` if present → `Fire`.
- Info.plist `SUFeedURL` → `https://pdurlej.github.io/fire-releases/appcast-fire.xml` (different filename to keep Ice and Fire appcasts separate during transition).
- Info.plist `SUPublicEDKey` → new keypair if you want clean separation, or keep same.
- Scheme name `Ice.xcscheme` → `Fire.xcscheme` and update `build-dmg.yml` matrix.
- `MenuBarItemService.xcscheme` if it embeds the binary name.

### 6.2 Icon (day 2)

Theme: red/black dragon, "Balerion" from ASOIAF. Practical execution:
- Generate at 1024x1024 PNG. Use `iconutil` or `Asset Catalog Compiler` to produce the `.icns` and `.appiconset` variants (16, 32, 128, 256, 512 + @2x).
- Replace `Ice/Resources/Assets.xcassets/AppIcon.appiconset/` contents.
- Also commit a marketing 1024x1024 for the README and the website.
- Sanity check Light/Dark Mode menu-bar control icons (`ControlItemImages` colorset) — those probably stay as they are (abstract shapes), but consider whether a flame variant fits.

**Decision point — do we replace ControlItem images?** Bartender's signature is the customizable status item. If we keep Ice's three default control items unchanged, the menu bar still "looks like Ice". Recommend: ship Phase 4 with original ControlItem images, address in a Phase 5 polish sprint with optional flame/dragon variants users can pick.

### 6.3 First-launch migration (days 3–5, the hard part)

Create `Ice/Main/FireMigration.swift` (new). Responsibilities:

1. **Detect prior Ice installation.** Check `~/Library/Preferences/com.jordanbaird.Ice.plist` exists.
2. **Detect "already migrated"** marker. Write `me.durlej.Fire.didMigrateFromIce = true` (UserDefaults Bool) on success. Bail if true.
3. **Copy UserDefaults.** Read all keys from `UserDefaults(suiteName: "com.jordanbaird.Ice")` (well, the standard domain — Ice doesn't use a suite). Iterate `dictionaryRepresentation()`, write each to our standard defaults under our keys. Schema: assume identical for now since we haven't changed the schema in fire — `MenuBarItemSettings`, `GeneralSettings`, `MenuBarAppearance`, etc.
4. **Copy Keychain.** Ice stores hotkeys / no — Ice stores nothing in Keychain itself, but check: `security find-generic-password -s "com.jordanbaird.Ice"` on a populated machine; if anything, copy with service name updated. (Owner: confirm before coding.)
5. **Show migration UI.** First launch only: a modal sheet, "Welcome to Fire — we found your Ice settings and brought them over. macOS will ask you to re-grant Accessibility and Screen Recording permissions because Fire is a new app to it. [Open System Settings]". Use SwiftUI sheet pattern from existing onboarding code.
6. **Trigger TCC re-prompts intentionally.** Call `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` and the screen capture equivalent once user dismisses the migration sheet. This is the **one-time UX cost** — own it, don't hide it.

**Decision point — what about the old Ice still on disk?**
- We can't uninstall it.
- We CAN check if it's running (`NSRunningApplication.runningApplications(withBundleIdentifier: "com.jordanbaird.Ice")`) and offer "Quit Ice now" button in the migration sheet.
- We CAN remind the user to drag it to the Trash.
- We do NOT attempt to delete `/Applications/Ice.app` ourselves — that requires authorization prompts and is too aggressive for first-launch.

### 6.4 Appcast cutover (day 6)

- Stand up `appcast-fire.xml` on `pdurlej/fire-releases` alongside the existing `appcast.xml`.
- Last Ice-named release (`0.12.0-fire.5`) gets a final appcast entry that points to a "Fire 1.0.0 is here, please download manually" notice. Sparkle CAN'T self-migrate to a new bundle ID through its normal flow (Sparkle assumes same bundle). So this is a manual hop for existing users.
- Update `build-dmg.yml` to write to `appcast-fire.xml` after Phase 4 lands.

### 6.5 README, website (day 7, optional)

- README: rewrite header to "Fire is a maintained, Tahoe-stable fork of Ice". Keep attribution prominent.
- Decision point: do we want `fire.durlej.me` or just GitHub Pages? Recommend: stand up `pdurlej.github.io/fire` (free) with download button + screenshots + migration FAQ. One Saturday.
- Add `MIGRATION.md` at repo root with the user-facing "what to expect when you switch from Ice".

### 6.6 Tag and ship (day 8)

- `v1.0.0-fire.0` (or `v1.0.0-rc.1` if owner wants a release-candidate cycle first — recommended given the migration risk).
- One week of `1.0.0-rc.N` cycle. Push fixes for migration bugs reported by early adopters.
- Cut `v1.0.0` when migration regressions = 0 for 7 days.

### Phase 4 DoD

- [ ] Owner's own machine migrated from Ice to Fire with all 25+ items preserved.
- [ ] Three other testers (recruit from upstream #823 thread) report clean migrations.
- [ ] TCC permissions cleanly re-granted via the in-app flow.
- [ ] Appcast-fire delivers updates to Fire installs.
- [ ] Old Ice installs continue to receive `0.12.0-fire.5` from old appcast but no further updates.

---

## 7. Phase 5 — Original Features for Heavy Users (weeks 9–16+)

Each as a separate sprint with its own pre-release. Order chosen by user-impact-per-day-of-work.

### 7.1 Sprint: Layout-empty bug investigation (#744, #891, #802) — 3–5 days

**Land this first.** It's a bug, not a feature; it kills user trust; and fixing it informs the data model for everything else in Phase 5.

Symptoms reported in those issues: opening Settings → Layout shows an empty list even when items exist; sometimes after a restart, sometimes after a permission re-grant, sometimes randomly. Reproduces for users with 25+ items more reliably than for users with 8.

Investigation plan:
1. Search the codebase for the Layout pane data source. Expected files: `Ice/Settings/SettingsPanes/MenuBarLayoutSettingsPane.swift` (or similar), backed by `MenuBarItemManager`. Code-graph: `codegraph_search` for `LayoutSettings`, then `codegraph_callers` on the data binding.
2. Hypotheses to test:
   - Race condition: pane opens before MenuBarItemManager finishes its initial scan. Fix: gate UI on a `Published` "didCompleteInitialScan" flag.
   - Filter bug: ItemManager returns items but the pane's filter (system items, alwaysHidden, etc.) excludes all of them. Fix: log the filter steps; add a "Show All" debug toggle.
   - Stale cache: ItemManager has a cached snapshot that becomes empty after some event and never refreshes. Fix: trace cache invalidation.
3. Add structured logging to the Layout pane init path (existing `Logging.swift` in `Shared/Utilities/`). Ship as a `1.0.1-fire.0` with logging on, ask three reporters from those issues to run it and send logs.
4. Fix based on logs. Ship `1.0.1`.

DoD: at least two of the three issue reporters confirm the empty-state no longer reproduces.

### 7.2 Sprint: Config export / import (#326) — 3 days

Lowest-complexity high-value feature. Foundational for profiles later.

- Add `Ice/Main/ConfigExport.swift`: serialize all relevant UserDefaults keys to a JSON file. Use a versioned envelope: `{ "fireConfigVersion": 1, "exportedAt": "...", "settings": {...} }`.
- Settings UI: Advanced pane → "Export Settings…" and "Import Settings…" buttons.
- Import: validate version, prompt before overwrite, show diff if reasonable, write back, restart prompt.
- DoD: round-trip on the owner's machine, on a fresh install, import owner's config, all items reappear identically.

This sprint creates the migration-format we'll reuse for profiles.

### 7.3 Sprint: Sensible defaults for new-icon placement (#6) — 2 days

Tiny feature, massive user-perceived quality jump. Currently new menu bar items appear at the leftmost visible position (or wherever the app puts them). Owner's experience: every Zoom install, every Slack reinstall, every new app shoves itself into "always visible" and breaks the user's curated layout.

- Add `Ice/Settings/Models/NewItemPlacement.swift` with enum `{ alwaysVisible, hidden, alwaysHidden, askMe }`.
- Default to `hidden` (the "smart move" for a 25+ item user).
- Detection: hook `MenuBarItemManager`'s "new item detected" event, route through the placement policy.
- `askMe` mode: brief NSAlert offering the three placements with "remember for this app" checkbox.

DoD: install a fresh app while Fire is running, watch the new icon go to the hidden section without intervention.

### 7.4 Sprint: Trigger conditions (#62) — 5–8 days

Major feature. "Show hidden items when X" where X is one of: app frontmost (e.g., always show Slack icon when Slack is foreground), keyboard modifier held, screen recording active, mic active, time of day, on AC power, etc.

Data model: `TriggerCondition` enum + `TriggerRule { condition: TriggerCondition, action: .showItem(ID) | .hideItem(ID) | .showSection(.hidden) }`.

Engine: a `TriggerManager` running on AppState that subscribes to relevant system signals (NSWorkspace activation notifications, distributed notifications for mic/screen recording, NSEvent monitor for modifiers) and toggles items via existing MenuBarItemManager APIs.

UI: new Settings pane "Triggers" with rule editor.

This is the biggest single feature in Phase 5. Decompose into:
- Sprint 5.4a (3 days): data model + engine for the three highest-value conditions (frontmost app, modifier held, mic active).
- Sprint 5.4b (3 days): UI rule editor.
- Sprint 5.4c (2 days): extend conditions list, polish, persistence.

DoD per phase. Tag `1.2.0-fire.0` at the end of 5.4c.

### 7.5 Sprint: Profiles (#26) — 8–12 days, the marquee feature

Multiple named layout configurations the user can switch between. "Work" vs "Stream" vs "Travel" profiles.

Salvage assessment of `upstream/profiles` (commit `517b7df`):
- Last commit is a merge from 0.12.0, suggesting work stalled mid-integration.
- Quick `git log upstream/profiles ^upstream/0.12.0` to see unique commits.
- Decision: take the data-model commits (likely 2–3 commits) as a starting point if they're clean; rewrite the UI on top of our current 0.12.0+rebrand foundation. **Do not merge the branch wholesale.**

Architecture:
- `Profile` model: `{ id, name, settingsSnapshot }` where `settingsSnapshot` is the same envelope as 7.2's export format. Profiles are just named saved exports + a switcher.
- Storage: `~/Library/Application Support/me.durlej.Fire/Profiles/<uuid>.json`.
- Switching: applies the snapshot via the import path; restart not needed (re-apply UserDefaults + nudge MenuBarItemManager to rescan).
- UI: menu-bar dropdown "Active Profile: Work ▾", Settings pane "Profiles" with create/duplicate/delete/edit.

Reuses 7.2's export/import code. That's why 7.2 lands first.

Sprint deliverables: tag `1.3.0-fire.0`.

### 7.6 Polish sprints (ongoing)

After 1.3.0, the roadmap becomes reactive: fix what users file. Reserve every fourth week for "bug bash" — clear out reported issues, no new features.

---

## 8. Cross-cutting Concerns

### 8.1 CI/release pipeline maturity (continuous)

- Phase 0 ships ad-hoc `build-dmg.yml`. Phase 1 should add `lint-on-pr.yml` enforcing swiftlint.
- Phase 2: add `swift-test.yml` if the project gains tests (it currently has none meaningful).
- Phase 4: introduce notarization workflow IF owner buys Developer ID. Workflow handles `xcrun notarytool submit --wait` + `stapler staple`.
- Sparkle release-notes: write per-tag `release-notes/v<tag>.html` in the `fire-releases` repo, link from appcast `<sparkle:releaseNotesLink>`.

### 8.2 README and docs (Phase 1 and Phase 4)

- Phase 1: update `README.md` header to "Maintained fork — Tahoe stable". Add "Differences from upstream" section. Keep attribution at top.
- Phase 4: total rewrite for Fire identity. Move old Ice-specific README to `README-ICE.md` for history.
- `FREQUENT_ISSUES.md` already exists; keep updating it.

### 8.3 Community engagement plan

- **Don't drown the upstream tracker.** One post in #760 after Phase 1 lands. One post in #823 ("is it dead?") with the same message. Then silence on upstream — let users find us organically.
- **Open a Fire-specific Discussions board** on `pdurlej/fire-from-ice` repo (currently disabled by default). Phase 0 deliverable: enable Discussions, pin a "Welcome / what is this fork" thread.
- **Issue triage cadence:** weekly, 1 hour, Sundays. Label new issues as `bug | feature | upstream-applies | wontfix`. Close anything that's actually upstream's problem with a polite link.
- **Don't take credit for upstream work.** Every cherry-picked PR's commit message preserves the original author. Release notes credit by `@handle`.

### 8.4 Licensing reminders

- GPL-3.0, unchanged. Mentioned in FORK.md, mention again in Phase 4 README rewrite.
- Acknowledgements.pdf/.rtf in `Ice/Resources/` — update after Phase 4 to add Fire's contributors. Generated by Xcode (`legalInfo` or similar). When CI builds, this needs to either be regenerated or be a tracked file. **Decision point: track as static file and update manually each release, OR regenerate in CI. Recommend: static file, update each minor release.**
- Don't strip "Ice" or "Jordan Baird" from anywhere except where rebranding semantically demands it (e.g., About pane app name yes; copyright line stays "© Jordan Baird 2022–2025, © Paweł Durlej 2026").

---

## 9. Risks Register

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| 1 | **Apple notarization gated by paid dev account.** Owner has CLI tools, no $99/yr account. Ad-hoc-signed DMGs spook users; Gatekeeper warning on every install. | Certain | Medium | Phase 0–3: accept it, document in README ("right-click → Open the first time"). Phase 4 boundary: re-evaluate; if active install base > 50, buy Developer ID and notarize from then on. |
| 2 | **Sparkle/appcast hosting cost or breakage.** GitHub Pages free tier limits, repo push race on tag-trigger workflows. | Low | Low–Medium | GH Pages has 100GB/month bandwidth; a 5MB DMG x 1000 downloads = 5GB. Comfortable. Workflow concurrency: `concurrency: { group: appcast, cancel-in-progress: false }` to serialize. |
| 3 | **TCC re-prompt scares users away at rebrand.** Users see "Fire wants to control your Mac via Accessibility" right after install and assume it's malware. | High | High | (a) In-app migration sheet pre-warns and includes screenshots. (b) Signed README + MIGRATION.md before rebrand release. (c) Pre-announce in Discussions one week ahead. (d) Don't auto-quit Ice; let user keep both during transition. |
| 4 | **Upstream resurrects.** jordanbaird starts committing again post-2026-06 and ships an actual Tahoe-stable Ice. | Medium | Medium | Honest framing: "If upstream resumes, we'll celebrate and consider retiring Fire or staying as the heavy-user fork." Don't burn bridges in upstream issue threads. Keep `main` branch tracking upstream so re-converging is technically possible. |
| 5 | **0.12.0 merge breaks something subtle in MenuBarItemManager.** The merged refactor introduces a regression that fire-specific Phase 1 PRs (#903, #941) didn't anticipate. | Medium | High | (a) Phase 2 ships as a separate tag, dogfood 48h before declaring done. (b) Keep `0.11.13-fire.1` available so users can downgrade. (c) Heavy logging in MenuBarItemManager around scan / cache / item events for Phase 2 + 3 releases. |
| 6 | **First-launch migration corrupts user settings.** Bug in `FireMigration.swift` writes garbage to UserDefaults, user's curated layout lost. | Medium | Very High | (a) Migration writes a `me.durlej.Fire.preMigrationBackup.plist` copy of the source defaults BEFORE any transformation. (b) Migration UI offers "Roll back" if user notices something off in first session. (c) Ship Phase 4 as `1.0.0-rc.1..rc.N` for at least 1 week of soak. |
| 7 | **Solo maintainer burnout.** Roadmap is ~16 weeks of nights/weekends. | High | Existential | (a) Hard cap: 6h/week. If a phase slips, slip it. (b) Don't promise dates publicly. (c) Phase boundaries are natural stopping points — fire/main is always shippable from a tag, so partial completion is fine. (d) Enable Issues + Discussions; let users self-help. Do NOT enable issue notifications to email. |
| 8 | **Apple changes private API used by Ice.** macOS 27 ships, breaks `_CGSGetWindowSpace` or whatever's underneath Bridging.swift. | Inevitable, timing unknown | High | Watch macOS 27 beta in 2026-06 dev cycle. Reserve a phase-zero-style sprint when needed. Bridging changes go in their own branch, never in a feature branch. |
| 9 | **GPL-3.0 obligations on the rebrand.** Some user thinks renaming = obscuring origin and gets noisy. | Low | Low | Attribution is preserved in FORK.md, README, About pane, every commit. GPL allows forking and renaming. Be ready with the link to FORK.md if anyone asks. |
| 10 | **MenuBarItemService XPC bundle ID change breaks helper.** Phase 4 rebrand renames the embedded XPC service; if `Shared/Services/MenuBarItemService.swift:9` and the project.pbxproj are not perfectly in sync, the main app can't talk to the helper. | High at the rebrand boundary | High | Phase 4 day 1 inventory: grep for `com.jordanbaird.Ice.MenuBarItemService` exhaustively, rename atomically, do a clean build, verify via Console.app that the service registers under the new name. |

---

## 10. Gantt-Style Summary

| Phase | Sprint | Tag | Days | DoD | Unlocks |
|---|---|---|---|---|---|
| 0 | Extract build-dmg.yml | — | 1 | YAML in repo, lints clean | CI builds |
| 0 | Sparkle/appcast decision + setup | — | 1 | `fire-releases` repo exists, keys in secrets | Auto-updates |
| 0 | Smoke-test CI | `v0.11.13-fire.0` | 1–2 | DMG on releases page, installs on owner's Mac | Phase 1 |
| 1 | Cherry-pick #928, #922, #804, #945 | — | 1–2 | All four merged, CI green | — |
| 1 | Cluster A: #903 then #941 | — | 2 | MenuBarItemManager clean, no regressions | Tahoe stable |
| 1 | Tag & dogfood | `v0.11.13-fire.1` | 1 | 48h dogfooding clean | Public "Tahoe-stable" claim |
| 2 | 0.12.0 merge commit | — | 2–3 | Search panel + appearance editor land, no MenuBarItemManager regressions | Modern UX baseline |
| 2 | Tag & dogfood | `v0.12.0-fire.1` | 1 | 48h clean | Phase 3 |
| 3 | PR #795 (auto IceBar by width) | `v0.12.0-fire.2` | 2 | Toggles on laptop+ext setup | — |
| 3 | PR #612 (per-display config) | `v0.12.0-fire.3` | 4 | UserDefaults migration shim works | Closes upstream #223 |
| 3 | PR #941 (if not in Phase 1) | `v0.12.0-fire.4` | 2 | Notch behavior correct | — |
| 3 | PR #667 (multimonitor single space) | `v0.12.0-fire.5` | 2 | IceBar lands on correct display | — |
| 4 | Identity rename + icon | — | 2 | Builds as Fire, ad-hoc signed | — |
| 4 | FireMigration.swift | — | 3 | Owner's machine migrates clean | — |
| 4 | Appcast cutover + RC cycle | `v1.0.0-rc.N` | 2 | 3 external testers report clean migration | — |
| 4 | Tag stable | `v1.0.0` | 1 | 7 days no migration regressions | Public rebrand done |
| 5 | Layout-empty bug | `v1.0.1-fire.N` | 3–5 | Two of three #744/#891/#802 reporters confirm fix | User trust |
| 5 | Config export/import | `v1.1.0-fire.0` | 3 | Round-trips on owner + fresh install | Profiles infra |
| 5 | New-icon placement defaults | `v1.1.1-fire.0` | 2 | Fresh install hides itself | Quality of life |
| 5 | Trigger conditions (data + engine) | — | 3 | Three conditions work in code, no UI | — |
| 5 | Trigger conditions (UI) | `v1.2.0-fire.0` | 3 | Users can author rules | — |
| 5 | Trigger conditions (extend + polish) | `v1.2.x` | 2 | Eight conditions, persistence solid | — |
| 5 | Profiles | `v1.3.0-fire.0` | 8–12 | Three profiles switchable on owner's bar | Marquee shipped |

**Total scheduled work:** ~60 working days across ~16 weeks at 6h/week sustainable pace. First public-facing "we're real" moment: end of Phase 1 (~week 2). First marquee feature: end of Phase 5.5 (~week 14–16).

**Always-true invariant:** `fire/main` builds, lints, runs. Any work-in-progress lives on a branch. No tag goes to the appcast until owner has run it for 48h on their own machine.
