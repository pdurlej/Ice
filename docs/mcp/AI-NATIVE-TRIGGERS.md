# Fire — AI-Native Triggers (design spec)

> Status: DESIGN (2026-06-05). Target: fire.10.x.
> One line: **Bartender makes you build trigger rules in GUI panels; Fire lets
> you (or an AI agent) set them up by talking, and lets an agent reason about
> them.**

## 1. Why

Bartender 6's headline feature is **Triggers**: "apply a preset / show a set of
items automatically when conditions are met." It's powerful — and entirely
manual: you assemble conditions in preference panes.

Fire's wedge is **AI-native**. Everything Bartender makes you click, Fire
exposes over MCP so an agent can do it conversationally:

> "Show my VPN icon only when I'm on untrusted Wi-Fi."
> "Hide everything except mic and clock whenever I'm in a meeting."
> "When my battery drops below 20%, reveal the battery item."

The user states intent in natural language; the agent translates it into a
structured Trigger via `set_trigger`. No panels.

Triggers are also the **synthesis** of threads Fire already has:
- The cross-MCP demo (Fantastical → `apply_layout`) → a *calendar-condition* trigger.
- The deferred `/schedule` automation → a *time-condition* trigger.
- AI Quotas (a first-party widget) → seeds the *widget registry* (GPT-5.5 Pro's
  review recommended exactly this; see `~/.oracle/.../fire-arch-review-9-7`).

So Triggers aren't a bolt-on; they unify what's already here.

## 2. The model

A **Trigger** is `{ name, when: Condition, do: Action, enabled }`.

### Conditions (what fires it)
| kind | params | fires when |
|---|---|---|
| `appFocus` | `bundleID`, `state: active\|inactive` | app becomes / stops being frontmost |
| `batteryLevel` | `below: Int` (percent) | battery crosses below threshold |
| `wifiSSID` | `ssid: String`, `match: is\|isNot` | joined / left a network |
| `focusMode` | `mode: String` (e.g. "Do Not Disturb") | a macOS Focus turns on/off |
| `calendarBusy` | (via calendar MCP) | an event is in progress |
| `schedule` | `cron` or `start`/`end` time-of-day | inside the time window |
| `manual` | `id` | an agent / hotkey explicitly fires it |

A condition is a *predicate that becomes true or false over time*. Triggers can
react to both edges (becomes-true → apply; becomes-false → optionally revert).

### Actions (what happens)
| kind | params | effect |
|---|---|---|
| `applyLayout` | `name` | reuse existing `apply_layout` |
| `setSection` | `items: [bundleID]`, `section` | move a set to a section |
| `peek` | `items: [bundleID]` | reveal while condition holds, restore when false |
| `notify` | `text` | post a notification (P3) |

MVP supports `applyLayout` and `setSection`. `peek` (auto-revert) is P3.

## 3. MCP surface (the AI-native part)

```jsonc
set_trigger {
  "name": "meeting-focus",
  "when": { "kind": "calendarBusy" },
  "do":   { "kind": "applyLayout", "name": "Meeting" },
  "enabled": true
}
list_triggers {}            // → [{name, when, do, enabled, lastFiredAt}]
remove_trigger { "name" }   // delete
set_trigger_enabled { "name", "enabled" }
```

The agent owns NL → structured translation. Fire validates and stores.

## 4. Architecture

```text
LLM client ──MCP──▶ IceMCPBridge ──▶ Fire main app
                                      ├─ TriggerStore (persisted)
                                      ├─ TriggerEngine  (evaluates conditions)
                                      └─ executes Action via itemManager / apply_layout
```

- **TriggerEngine** lives in the **main app** (it holds the AX grant and runs
  continuously). It subscribes to the relevant event sources per registered
  condition:
  - `appFocus` → `NSWorkspace.didActivateApplicationNotification`
  - `batteryLevel` → IOPowerSources / `NSProcessInfo` power notifications
  - `wifiSSID` → CoreWLAN / network-change notifications
  - `focusMode` → DoNotDisturb / Focus status (NSWorkspace / private but
    detectable; degrade gracefully if unavailable)
  - `schedule` → a timer / the existing cron path
  - `calendarBusy` → polled via the calendar MCP (cross-MCP), or a cached feed
  - `manual` → fired by an MCP call
- On a condition edge, the engine runs the Action through the SAME
  `MCPWriteCommandHandler` / `itemManager.move` path used today — i.e. it reuses
  the proven write path, it does not add a second one.
- Keep it ONE evaluator on the main actor (no second source of truth), echoing
  GPT-5.5 Pro's "every mutation through exactly one actor" invariant.

## 5. Consent & security (ties to fire.9.8)

Auto-firing triggers re-raise the confused-deputy question: a trigger fires and
moves items with no prompt. Resolution:

- **Consent at creation, not per-fire.** `set_trigger` is a privileged write →
  it MUST pass the fire.9.8 main-app consent gate (`MCPWriteAuthorization`).
  The prompt is trigger-specific: *"Allow Fire to automatically apply 'Meeting'
  whenever you're in a meeting?"* Approving the rule pre-authorizes its
  auto-actions.
- Auto-fires then run without a per-fire prompt (the user already consented to
  the rule). This is the right trade: human-in-the-loop at rule install, smooth
  thereafter — and it's how unattended automation becomes possible *safely*,
  which the bare file channel could not offer.
- Triggers are stored where a rogue process can't silently add one without the
  gate firing. Removing/disabling a trigger is also gated.

## 6. Persistence

`TriggerStore` → Ice defaults key `Triggers` (a dict keyed by name), mirroring
`MCPLayouts`. Codable structs for `Trigger`, `Condition`, `Action`. Versioned
with a `schemaVersion` for forward-compat (per GPT-5.5 Pro: prefer a protocol
version field over service-name versioning).

## 7. MVP (Phase 1) scope

Ship the loop end-to-end with a small, high-value condition set:

- `TriggerStore` + Codable model + `Triggers` persistence.
- `TriggerEngine` (main app) wired to: **`appFocus`**, **`batteryLevel`**,
  **`manual`** (3 conditions — covers the most-demoed cases without the harder
  system hooks).
- Actions: **`applyLayout`**, **`setSection`**.
- MCP tools: `set_trigger`, `list_triggers`, `remove_trigger`,
  `set_trigger_enabled`.
- Consent at set-time via `MCPWriteAuthorization` (fire.9.8).
- Minimal UI: read-only list of active triggers in Settings → MCP (with a
  delete/disable toggle). Creation stays agent-driven — that's the point.

### Phasing
- **P1 (MVP):** above.
- **P2:** `wifiSSID`, `focusMode`, `schedule`/time, `calendarBusy` (cross-MCP).
- **P3:** `peek` auto-revert semantics; `notify`/agent-prompt actions; a small
  NL→trigger helper so even non-MCP users get a "describe a rule" box.

## 8. Open questions

1. Edge vs level semantics per condition — do all conditions support
   becomes-false reversion, or only `peek`?
2. Conflict resolution when two triggers fire at once (priority? last-wins?
   layered?). Keep simple in P1 (apply in registration order); revisit.
3. `focusMode` detection on macOS 26 — public API coverage; degrade gracefully.
4. Should `manual` triggers be exposed as their own MCP `fire_trigger(name)` so
   an agent can compose them? (Likely yes in P2.)
5. Calendar condition: poll the calendar MCP from the engine, or have an agent
   push state in? (Cross-MCP design — defer to P2.)
