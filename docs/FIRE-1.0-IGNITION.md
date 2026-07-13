# Fire 1.0 “Ignition”

Status: implementation contract for the first Fire release.

## Product thesis

Fire programs the space around the menu bar for the work that is happening
now. A local agent describes the intent; Fire discovers the actual items and
capabilities, presents an exact Fire-authored change for approval, applies it,
and leaves a visible recovery path.

Fire is not “Ice with MCP” and it is not a Dynamic Island clone. Its primary
interface is the local CLI/agent loop. Settings exist for onboarding,
observability, consent, repair, and deliberate manual overrides.

## The 1.0 vertical slice

The release is complete only when both reference contexts work:

1. **Coding** — when Codex becomes the work context, Fireline shows local Codex
   quota status from the existing AI Quotas provider.
2. **Mail** — when Mail becomes frontmost, Fire surfaces the selected
   Fantastical menu bar item without requiring a hand-edited configuration.

The supported agent flow is:

1. run `fire doctor` and discover capabilities;
2. list menu bar items with stable selectors;
3. ask for the user's intent and propose a Context Scene;
4. let Fire render the exact condition, Fireline content, and menu bar moves;
5. install only after Fire's existing sealed approval flow succeeds;
6. verify the installed scene and explain disable/remove/recovery commands.

Codex, Claude Code, and OpenCode use generated adapters from one canonical Fire
skill. They must not carry separate product prompts.

## Compatibility boundaries

The following stay unchanged in 1.0:

- bundle identifier `com.jordanbaird.Ice`;
- on-disk product and executable name `Ice.app` / `Ice`;
- existing `Defaults` keys, status-item autosave names, Keychain services, and
  XPC service names;
- existing Sparkle identity and update continuity;
- existing direct MCP tools and their wire compatibility.

All primary user-visible product language becomes Fire. Ice remains visible
only as an upstream credit in About and in internal compatibility identifiers.
The old `docs/REBRAND_PLAN.md` bundle-ID migration is historical exploration,
not the 1.0 implementation plan.

## Domain contracts

### Stable item selector

`bundleID` alone is not a stable item identity: one application can own several
status items, and macOS 26 can report Control Center as the owner while the
source application differs. The public selector is therefore versioned and
uses the existing menu-bar tag identity:

```text
ItemSelector.v1(namespace, title, sourceBundleID?)
```

`namespace + title` is the exact match. `sourceBundleID` is descriptive and a
safe migration/fallback hint, never permission to select every item from that
application. Legacy bundle-only requests remain accepted only when they resolve
to exactly one manageable item; zero or multiple matches fail with candidates.
Transient `windowID` is returned for observation but never persisted as stable
identity.

### Context Scene

A Context Scene is an approved snapshot, not a mutable named layout:

```text
ContextScene
  id, generation, name, enabled
  condition
  menuBarMoves: exact ItemSelector + destination pairs
  fireline: hidden | quota(provider) | menuBarItem(ItemSelector)
  priority, cooldown, lastActivatedAt
```

The seal binds the canonical condition, exact selectors and destinations, and
the Fireline content. Editing any of them invalidates the grant. Menu bar moves
continue through `MenuBarMutationCoordinator`; Fireline presentation is updated
only after the scene's grant is revalidated at activation time.

The 1.0 engine remains edge-triggered on enter. It does not continuously fight
manual user changes and does not implement false-edge layout reversion.

### Fireline

Fireline evolves the existing Ice Bar panel. It is a light, non-activating
surface directly below the notch when a notch is present, and centered below
the menu bar otherwise. It shows one context payload, not a dashboard:

- current scene and a short activation confirmation;
- one quota widget; or
- one selected menu bar item with the existing click behavior.

The existing hidden-items bar remains available as a manual rescue surface,
but is no longer the product headline.

## Settings information architecture

1. **Home** — setup health, permissions, first working context.
2. **Surfaces** — menu bar, Fireline, appearance, shortcuts.
3. **Contexts** — installed scenes, global off, recent activations, recovery.
4. **Agents** — local MCP/CLI status, Codex/Claude Code/OpenCode setup, doctor.
5. **Advanced** — legacy and diagnostic controls.
6. **About** — Fire version and explicit Ice/upstream credit.

The first 1.0 pass may compose existing controls inside these destinations; it
must not duplicate their storage or behavior.

## Reliability and accessibility gates

- The synchronous XPC path has a bounded failure/recovery behavior for a
  stopped or wedged helper; it cannot leave the agent onboarding call hung.
- Every new control and Fireline payload has a useful accessibility label,
  value where applicable, keyboard focus behavior, and sufficient contrast.
- Item resolution never chooses an ambiguous candidate silently.
- Scene activation never bypasses a sealed grant or the single mutation
  coordinator.
- The live `isMouseInsideMenuBarItem` geometry query remains live; 1.0 must not
  restore the broken cache from fire.10.7.

## Explicit cuts from 1.0

- no calendar, Wi-Fi, Focus mode, cron, or remote trigger source;
- no agent-authored Swift, JavaScript, shell, or arbitrary widget code;
- no network listener, cloud account, telemetry expansion, or public plugin
  marketplace;
- no continuous enforcement or general conflict solver;
- no bundle-ID, target, executable, Defaults-key, Keychain-service, or XPC-name
  migration;
- no broad upstream refactor or internal `Ice*` type rename;
- no attempt to turn Fireline into a full dashboard or notification center.

## Ship / no-ship matrix

| Gate | Ship evidence |
|---|---|
| First value | Fresh/user-reset setup reaches one working reference context in under 3 minutes without editing JSON/TOML. |
| Coding scene | Activating Codex shows its local quota payload in Fireline; unavailable quota data degrades to a useful local diagnostic. |
| Mail scene | Activating Mail surfaces the user-selected Fantastical item; ambiguous or absent items produce candidates/repair, never a wrong move. |
| Consent | The Fire-authored approval shows condition, exact affected items, destinations, and Fireline payload; denial changes nothing. |
| Recovery | Global context off, per-scene disable/remove, and manual menu bar behavior all work after activation. |
| Compatibility | Existing preferences, TCC grants, MCP clients, saved layouts, Sparkle updates, and app installation path survive the update. |
| Reliability | Unit tests, Bridge build, FireLogic tests, unsigned all-target Xcode build, stopped-helper recovery, and signed MCP smoke pass. |
| Accessibility | VoiceOver/Accessibility Inspector pass for onboarding, settings navigation, scene rows, approval, and Fireline. |
| Field health | Clean-install smoke passes and Sentry CLI shows no new release-specific crash/App-Hang regression before appcast publication. |
| Brand | No primary UI says Ice or “Fire from Ice”; About credits upstream Ice and links to the Fire repository. |

Any failed row is no-ship for Fire 1.0. A smaller release may be cut under the
existing `0.11.13-fire.*` line, but must not be called Ignition.

## Rollback

The last known-good release is `v0.11.13-fire.10.7.3` (build 1158). Fire 1.0
does not migrate identities or schemas irreversibly. Rollback is reinstalling
that signed DMG and reverting the appcast commit. Scenes added by 1.0 must be
stored under new keys and ignored by 10.7.3; rollback may leave inert scene data
but must not lose existing menu bar preferences or layouts.
