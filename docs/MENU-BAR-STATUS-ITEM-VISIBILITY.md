# Menu-bar status-item visibility on macOS 26 — field notes

> Hard-won notes from debugging Fire/Ice's "AI Quotas" readout (an
> `NSStatusItem` that kept landing invisible). Written for the engineer
> fixing the same class of bug in **CodexBar**. Everything here was
> verified empirically on macOS 26 (Tahoe), single 2056×1329 display,
> with Ice running as the menu-bar manager.

---

## TL;DR (if you read nothing else)

1. **A brand-new `NSStatusItem` defaults to a HIGH "preferred position",
   which puts it at the far-LEFT of the status area — where it falls off
   a crowded menu bar or gets swallowed by a menu-bar manager.** The fix
   is to **force a LOW preferred position BEFORE you create the status
   item.** Low = trailing/right edge (next to the clock) = visible.

2. **Setting the position AFTER creation does nothing.** Not via
   `statusItem` properties, not via `defaults write`. It must be written
   to `UserDefaults` *before* `NSStatusBar.system.statusItem(...)`.

3. **Do not "verify" with AX `AXTitle`.** AX returns the title even when
   the item is parked off-screen. I lost hours concluding "it works"
   because the title read fine — while the item sat at x = −9501.
   **Verify the on-screen X via `CGWindowListCopyWindowInfo`.**

4. **Never *delete* the preferred-position key to "reset" it.** macOS
   then assigns a fresh HIGH position → hidden again. *Set* it low.

---

## The mechanism (what actually controls placement)

macOS persists each status item's slot in the host app's `UserDefaults`:

```
key:   "NSStatusItem Preferred Position <autosaveName>"   (a Double/CGFloat)
value: lower  → placed toward the trailing (right / clock-adjacent) edge → visible
       higher → placed toward the leading (left) edge → first to be pushed off
```

Evidence from Ice's own control items (they're always visible because of
this — not by magic):

```
Ice.ControlItem.Visible      preferred 0      renders at minX 1819  (visible, by the clock)
Ice.ControlItem.Hidden       preferred 1
Ice.ControlItem.AlwaysHidden preferred (unset)
AI Quotas (before fix)       preferred 11298  renders at minX -9501 (off-screen left)
AI Quotas (after fix)        preferred 0      renders at minX 1757  (visible) ✅
```

A fresh status item with **no** persisted position gets a high one by
default → leftmost → hidden. That's the whole bug.

### The fix, concretely

```swift
// BEFORE creating the status item:
let key = "NSStatusItem Preferred Position \(autosaveName)"
let current = UserDefaults.standard.object(forKey: key) as? Double
if current == nil || (current ?? 0) > 100 {   // unset, or parked far left
    UserDefaults.standard.set(0.0, forKey: key)
}

// THEN create it:
let item = NSStatusBar.system.statusItem(withLength: .variableLength)
item.autosaveName = autosaveName   // ties the item to that position key
```

This is exactly what Ice does in `ControlItem.preflightSetup` and why its
icon is always visible. (Apple's docs don't spell this out; it's folklore.)

---

## Trap #1 — verify POSITION, not the title

`AXTitle`/`AXValue` are readable on an off-screen item, so they lie about
visibility. Also, **AX `AXPosition` itself is unreliable** for reparented
status items — in one read it reported `x=16937` for an item that
`CGWindowList` correctly placed at `x=1757`.

**Authoritative check** = `CGWindowListCopyWindowInfo([.optionAll], …)`,
find your window by name, read `kCGWindowBounds.X` and
`kCGWindowIsOnscreen`. Drop-in probe:

```swift
// swift probe.swift   — prints your status item's real position
import Cocoa; import CoreGraphics
let want = "CodexBar.StatusItem"   // == your autosaveName / window name
guard let wl = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String:Any]] else { exit(1) }
for w in wl {
    let name = w[kCGWindowName as String] as? String ?? ""
    guard name == want || name.contains("CodexBar") else { continue }
    let b = w[kCGWindowBounds as String] as? [String:CGFloat] ?? [:]
    let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
    print("name='\(name)' owner=\(owner) x=\(Int(b["X"] ?? 0)) w=\(Int(b["Width"] ?? 0)) onscreen=\(w[kCGWindowIsOnscreen as String] as? Bool ?? false)")
}
```

If `x` is negative or `> displayWidth`, you're off-screen — regardless of
what AX says.

---

## Trap #2 — the preferred-position → on-screen-X mapping is NOT linear

When a menu-bar manager is present, its dividers can be enormous (Ice uses
**10 000pt-wide** divider items to push hidden items off-screen). That
warps the coordinate space, so you **cannot** binary-search a "magic"
position value. Observed, non-monotonic, nonsensical:

```
preferred 174   → x 1819   (visible)
preferred 300   → x 15637  (off-screen RIGHT)
preferred 11298 → x -9501  (off-screen LEFT)
```

Don't tune the number. Use `0` (matches the host's own always-visible
control item) and verify with the probe.

---

## Trap #3 — macOS 26 Control Center reparenting

On Tahoe, status items are reparented under Control Center. Consequences:

- `kCGWindowOwnerName` becomes "Control Center" (localized, e.g. "Centrum
  sterowania") for **everyone** — you can't identify your item by owner.
- Generic items report `kCGWindowName == "Item-0"`. **But** an item that
  set an `autosaveName` keeps that as its `kCGWindowName` (e.g. our item
  showed `name='Ice.ControlItem.AIQuotas'`). So: **set a distinctive
  `autosaveName` and identify your window by name**, not by PID/owner.
- The real creating PID is only recoverable via an AX scan of the app's
  extras menu bar (this is what Ice's `SourcePIDCache` does). Costly;
  avoid if a window-name match suffices.

---

## CodexBar-specific guidance

CodexBar is a **standalone app**, not the owner of the menu-bar strip, so
it can't make itself "native" to a manager the way we did inside Ice. But
most of the win is still available:

1. **Force preferred position low before creating the item** (the snippet
   above). This alone fixes the common case — a crowded bar pushing a
   newly-added item off the left edge. Single biggest lever.

2. **Self-heal on launch + periodically.** Run the CGWindowList probe
   against your own window; if `x` is off-screen (negative or
   `> screen.maxX`), re-write the preferred position to `0`. Don't delete
   the key — set it. (Recreating the `NSStatusItem` after fixing the key
   also works but flickers.)

3. **Keep it ONE item with a stable `autosaveName`.** Codex confirmed
   CodexBar broke even merged (`mergeIcons=1`), so multi-item churn isn't
   the cause — but dynamic create/destroy still resets positions and adds
   variance. Create once, update title/menu in place, never recreate on
   refresh. (We hit this too: recreating per refresh re-rolls the slot.)

4. **Verify with the probe, never with AX title.** Add a debug command
   that prints your item's `CGWindowList` X + onscreen so QA can confirm
   visibility deterministically.

### The honest architectural caveat

If a **menu-bar manager (Ice/Bartender/etc.) is actively running**, a
foreign status item is fundamentally contested — the manager owns the
strip and may relocate/hide it on its own cadence, and preferred-position
becomes a tug-of-war. There's no clean win for a third-party app in that
case. Realistic options, worst-to-best:

- (worst) keep fighting with preferred-position re-asserts — flaky under
  an active manager.
- (pragmatic) detect a known manager is running and surface a hint to the
  user ("CodexBar may be hidden by your menu-bar manager; unhide it
  there"), plus the self-heal for the no-manager case.
- (best, but only if you own the strip) render the readout as the strip
  owner's *own pinned control*. That's the route Fire took: the AI Quotas
  readout is now an Ice-native control item (registered in Ice's control
  set, excluded from third-party management, preferred position 0), so it
  inherits the same visibility guarantee as Ice's own icon. Not available
  to a standalone CodexBar — but it's the gold standard when you do own
  the menu bar.

---

## One-paragraph summary for the PR description

> New status items default to a far-left preferred position and land
> off-screen on crowded bars / under menu-bar managers. Fix: write a low
> `"NSStatusItem Preferred Position <autosaveName>"` to UserDefaults
> *before* creating the item (setting it afterward is a no-op), create the
> item once with a stable `autosaveName`, and self-heal by re-writing the
> key to 0 if a `CGWindowList` check finds the window off-screen. Verify
> visibility via `CGWindowListCopyWindowInfo` bounds, never via the AX
> title (it reads fine while off-screen).
