# Fire MCP Server Architecture

## 1. Vision

Fire's MCP server transforms the macOS menu bar from a static strip of icons into a programmable surface that AI agents can read, reason about, and rearrange on the user's behalf. No menu bar manager — not Bartender 6, not Hidden Bar, not upstream Ice — exposes this kind of introspection and control. By shipping an MCP bridge as a first-class binary inside the Fire app bundle, we give every local LLM client (Claude Code, Codex, Cursor, Continue) a structured API into menu bar state that was previously locked behind Accessibility heuristics and manual drag-and-drop. The menu bar becomes the first macOS system area that an AI agent can meaningfully manage.

This positions Fire as the *AI-native* menu bar manager. The bet is that power users increasingly prefer telling an agent what they want — "hide everything except mic and clock for my meeting" — over hand-building settings panes and trigger rules. MCP is the protocol that makes this possible without Fire needing to ship N custom integrations; any MCP-compatible client gets it for free. The tool annotations (readOnly, destructive, idempotent) let agents reason about safety before acting, and the consent gate ensures no rogue client silently reshapes a user's menu bar.

What this unlocks: instant context-aware layouts triggered by natural language, diagnostic queries ("which icon is eating my battery?"), recovery from forgotten hidden items, and auto-generated profiles inferred from bundle IDs. These are capabilities that would each require a separate UI feature in a traditional app — but with MCP, they emerge from a single thin API layer. Fire stops being a utility you configure and becomes a utility you *talk to*.

## 2. Architecture Overview

```
┌──────────────────┐       stdio / HTTP+SSE        ┌──────────────────────┐
│   LLM Client     │◄────────────────────────────►│   IceMCPBridge       │
│  (Claude Code,   │                                │   (MCP Server)       │
│   Codex, Cursor, │                                │                      │
│   Continue)      │                                │  ┌────────────────┐  │
└──────────────────┘                                │  │ Tool handlers  │  │
                                                    │  │ (6 MVP tools)  │  │
                                                    │  └───────┬────────┘  │
                                                    │          │           │
                                                    │  ┌───────▼────────┐  │
                                                    │  │  XPC Client    │  │
                                                    │  │  (Connection)  │  │
                                                    │  └───────┬────────┘  │
┌──────────────────┐   unix domain socket            │          │           │
│   Fire Main App  │◄═══════════════════════════════►│          │           │
│                  │   ~/Library/Application         └──────────┘           │
│ ┌──────────────┐ │   Support/Fire/mcp.sock                              │
│ │  Extended    │ │                                                     │
│ │  MenuBar     │ │   ┌──────────────────────────────────────────┐       │
│ │  ItemService │ │   │  IceMCPBridge is a separate Xcode target │       │
│ │  XPC Listener│ │   │  that embeds MenuBarItemService.Connection│       │
│ │              │ │   │  to talk to the main Fire app over the   │       │
│ └──────┬───────┘ │   │  same XPC channel used by the layout UI. │       │
│        │         │   └──────────────────────────────────────────┘       │
│ ┌──────▼───────┐ │                                                     │
│ │ Accessibility│ │   NOTE: The unix socket is NOT the XPC channel.     │
│ │ / State APIs │ │   XPC uses the macOS service name mechanism.       │
│ └──────────────┘ │   The socket is for MCP clients connecting to      │
└──────────────────┘   IceMCPBridge's stdio transport (local only).     │
                                                                    │
                                                                    │
```

### Component Responsibilities

| Component | Responsibility |
|---|---|
| **LLM Client** | Discovers Fire MCP server via config file; sends tool calls over stdio; receives structured JSON responses. |
| **IceMCPBridge** | Separate Xcode target binary. Implements MCP protocol (initialize, tools/list, tools/call). Validates auth consent before forwarding write operations. Encodes/decodes XPC requests. Manages unix socket listener for local stdio transport. |
| **Extended MenuBarItemService XPC** | Existing XPC listener in the main Fire app, extended with new Request/Response enum cases (`listItems`, `moveItem`, `hideItem`, `showItem`, `applyLayout`, `saveLayout`). Enforces same-team peer requirement. Routes requests to Accessibility/state APIs. |
| **Accessibility/State APIs** | The existing Accessibility-based engine that reads menu bar item windows, positions, and PIDs. Now also serves write operations (moving, hiding, showing items) and layout persistence. |

### XPC Extension Points

The existing `MenuBarItemService.Request` / `MenuBarItemService.Response` enums are extended with new cases:

```swift
// Added to MenuBarItemService.Request
case listItems                    // Returns all menu bar items with metadata
case moveItem(bundleID: String, to: Int)  // Move item to position
case hideItem(bundleID: String)   // Hide a specific item
case showItem(bundleID: String)  // Show a specific item
case applyLayout(name: String)   // Apply a saved layout
case saveLayout(name: String)    // Save current state as named layout
```

IceMCPBridge reuses the existing `MenuBarItemService.Connection` class (same-team peer guard included) to send these requests synchronously over XPC.

## 3. MVP Toolset

### `list_items`

**Purpose:** Return all menu bar items with their visibility state, position, bundle ID, and display name.

**Input Schema:**
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "section": {
      "type": "string",
      "enum": ["alwaysVisible", "hidden", "alwaysHidden"],
      "description": "Filter to a specific visibility section. Omit to return all items."
    }
  },
  "additionalProperties": false
}
```

**Output Schema:**
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "items": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "bundleID": { "type": "string" },
          "displayName": { "type": "string" },
          "section": { "type": "string", "enum": ["alwaysVisible", "hidden", "alwaysHidden"] },
          "position": { "type": "integer", "description": "0-based index within section" },
          "pid": { "type": "integer" }
        },
        "required": ["bundleID", "displayName", "section", "position"]
      }
    }
  },
  "required": ["items"]
}
```

**Annotations:** `readOnly`, `idempotent`

**Example call:**
```
tools/call  list_items  { "section": "hidden" }
```

---

### `move_item`

**Purpose:** Move a menu bar item to a specific position within its target section.

**Input Schema:**
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "bundleID": {
      "type": "string",
      "description": "Bundle identifier of the item to move"
    },
    "toSection": {
      "type": "string",
      "enum": ["alwaysVisible", "hidden", "alwaysHidden"],
      "description": "Target section"
    },
    "toPosition": {
      "type": "integer",
      "description": "0-based index within the target section. Omit to append at end."
    }
  },
  "required": ["bundleID", "toSection"],
  "additionalProperties": false
}
```

**Output Schema:**
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "success": { "type": "boolean" },
    "item": {
      "type": "object",
      "properties": {
        "bundleID": { "type": "string" },
        "section": { "type": "string" },
        "position": { "type": "integer" }
      }
    },
    "error": { "type": "string" }
  },
  "required": ["success"]
}
```

**Annotations:** `destructive`

**Example call:**
```
tools/call  move_item  { "bundleID": "com.slack.mac", "toSection": "alwaysVisible", "toPosition": 0 }
```

---

### `hide_item`

**Purpose:** Hide a specific menu bar item by moving it to the hidden section.

**Input Schema:**
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "bundleID": {
      "type": "string",
      "description": "Bundle identifier of the item to hide"
    }
  },
  "required": ["bundleID"],
  "additionalProperties": false
}
```

**Output Schema:**
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "success": { "type": "boolean" },
    "error": { "type": "string" }
  },
  "required": ["success"]
}
```

**Annotations:** `destructive`

**Example call:**
```
tools/call  hide_item  { "bundleID": "com.microsoft.teams" }
```

---

### `show_item`

**Purpose:** Show a hidden menu bar item by moving it to the always-visible section.

**Input Schema:**
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "bundleID": {
      "type": "string",
      "description": "Bundle identifier of the item to show"
    }
  },
  "required": ["bundleID"],
  "additionalProperties": false
}
```

**Output Schema:**
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "success": { "type": "boolean" },
    "error": { "type": "string" }
  },
  "required": ["success"]
}
```

**Annotations:** `destructive`

**Example call:**
```
tools/call  show_item  { "bundleID": "com.apple.airport.airport" }
```

---

### `apply_layout`

**Purpose:** Apply a previously saved named layout, restoring item positions and visibility states.

**Input Schema:**
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "name": {
      "type": "string",
      "description": "Name of the saved layout to apply"
    }
  },
  "required": ["name"],
  "additionalProperties": false
}
```

**Output Schema:**
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "success": { "type": "boolean" },
    "appliedItems": {
      "type": "integer",
      "description": "Number of items whose state was restored"
    },
    "error": { "type": "string" }
  },
  "required": ["success"]
}
```

**Annotations:** `destructive`

**Example call:**
```
tools/call  apply_layout  { "name": "meeting-mode" }
```

---

### `save_layout`

**Purpose:** Save the current menu bar state as a named layout for later restoration.

**Input Schema:**
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "name": {
      "type": "string",
      "description": "Name for the layout. Overwrites if name already exists."
    }
  },
  "required": ["name"],
  "additionalProperties": false
}
```

**Output Schema:**
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "success": { "type": "boolean" },
    "savedItems": {
      "type": "integer",
      "description": "Number of items saved in the layout"
    },
    "error": { "type": "string" }
  },
  "required": ["success"]
}
```

**Annotations:** `destructive`, `idempotent`

**Example call:**
```
tools/call  save_layout  { "name": "weekend" }
```

## 4. Auth/Onboarding Flow

### Step-by-Step: First Connection from Unknown LLM Client

1. LLM client starts IceMCPBridge via stdio (launched by the client process).
2. Client sends `initialize` → server responds with capabilities.
3. Client calls a **write tool** (e.g., `hide_item`).
4. IceMCPBridge checks Keychain for a consent entry matching the client's process path.
5. No entry found → IceMCPBridge sends XPC request to main Fire app: `requestConsent(clientPath: "/usr/local/bin/claude", clientName: "Claude Code")`.
6. Fire main app posts a native macOS notification with action buttons.

### Notification UI Mockup

```
┌─────────────────────────────────────────────────────────┐
│  🔥 Fire                                               │
│                                                         │
│  "Claude Code" wants to manage your menu bar.           │
│                                                         │
│  Path: /usr/local/bin/claude                            │
│                                                         │
│  Granting allows this app to rearrange, hide, and       │
│  show menu bar items on your behalf.                    │
│                                                         │
│  [  Deny  ]                [  Allow Write Access  ]      │
└─────────────────────────────────────────────────────────┘
```

### Persisted Consent — Keychain Entry Shape

```
Service:  com.jordanbaird.Fire.mcp-consent
Account:  <SHA-256 of client binary path>
Label:    Fire MCP — <client name>

kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock

Data (JSON):
{
  "clientPath": "/usr/local/bin/claude",
  "clientName": "Claude Code",
  "grantedAt": "2025-07-12T14:30:00Z",
  "scope": "write",          // "write" | "readonly"
  "revoked": false
}
```

Read-only tools (`list_items`) work without any consent entry. Write tools require `scope: "write"` and `revoked: false`.

### Revoke Flow

1. User opens Fire → Settings → Advanced → MCP Connections.
2. UI lists all consented clients from Keychain (query by service name).
3. User selects a client and clicks "Revoke".
4. Keychain entry updated: `revoked: true` (or deleted entirely).
5. Next write-tool call from that client returns an MCP error: `"Client consent revoked. Open Fire settings to re-authorize."`

### Read-Only vs Write Tool Gating

| Category | Tools | Consent Required |
|---|---|---|
| Read-only | `list_items` | None (local process only) |
| Write | `move_item`, `hide_item`, `show_item`, `apply_layout`, `save_layout` | Explicit Keychain consent with `scope: "write"` |

IceMCPBridge checks consent *before* sending the XPC request. If consent is missing or revoked, the tool returns an error immediately — the XPC message is never sent.

## 5. Discovery Configuration

### Claude Code — `~/.claude/mcp.json`

```json
{
  "mcpServers": {
    "fire": {
      "command": "/Applications/Fire.app/Contents/MacOS/IceMCPBridge",
      "args": ["--stdio"]
    }
  }
}
```

### Codex CLI — `~/.codex/config.json`

```json
{
  "mcpServers": {
    "fire": {
      "command": "/Applications/Fire.app/Contents/MacOS/IceMCPBridge",
      "args": ["--stdio"]
    }
  }
}
```

### Cursor — `.cursor/mcp.json`

```json
{
  "mcpServers": {
    "fire": {
      "command": "/Applications/Fire.app/Contents/MacOS/IceMCPBridge",
      "args": ["--stdio"]
    }
  }
}
```

### Continue — `~/.continue/config.json`

```json
{
  "experimental": {
    "mcpServers": {
      "fire": {
        "command": "/Applications/Fire.app/Contents/MacOS/IceMCPBridge",
        "args": ["--stdio"]
      }
    }
  }
}
```

### Generic stdio MCP client

```json
{
  "fire": {
    "command": "/Applications/Fire.app/Contents/MacOS/IceMCPBridge",
    "args": ["--stdio"]
  }
}
```

Fire's Advanced settings pane will render these snippets with a copy button, auto-detecting the installed path.

## 6. Integration with FORK.md Roadmap

### Proposed: Phase 4.5 — MCP Server

| Phase | Description | Status |
|---|---|---|
| 1 | Tahoe stability | DONE |
| 2 | 0.12.0 merge | PENDING |
| 3 | Feature merges (per-display, auto Ice Bar, notch-aware) | PENDING |
| 4 | **Rebrand to Fire** (new bundle ID + icon + migration) | PENDING |
| **4.5** | **MCP Server (IceMCPBridge + XPC extension + auth)** | **NEW** |
| 5 | Original features (profiles, trigger conditions, etc.) | PENDING |

### Justification for Phase 4.5 Positioning

**Must come after Phase 4 (rebrand):** The MCP socket path and XPC service name both embed the bundle ID. After rebrand, the socket lives at `~/Library/Application Support/Fire/mcp.sock` and the XPC service becomes `com.jordanbaird.Fire.MenuBarItemService`. Shipping MCP before rebrand would bake the old `Ice` paths into user config files, requiring a migration step. Post-rebrand, the paths are stable.

**Must come before Phase 5 (original features):** Phase 5 introduces profiles and trigger conditions — exactly the features that should be *exposed as MCP tools* (`list_profiles`, `create_profile_from_current`, `find_item`). If MCP ships first, Phase 5 features can be added as new tool handlers without architectural changes. If profiles ship first, they'll need a separate API surface that MCP later wraps — doubling the integration work.

**Low risk insertion:** IceMCPBridge is a separate binary target with no changes to existing Fire UI codepaths beyond extending the XPC Request/Response enums. It can be feature-flagged behind an Advanced setting with zero impact on users who don't enable it.

## 7. Risks + Anti-Goals

### What This Is NOT

- **NOT a remote control surface.** IceMCPBridge listens on stdio (local process only). There is no TCP listener, no network-facing endpoint. Remote access requires the user to explicitly set up SSH tunneling or similar — that is outside our scope.
- **NOT for non-local clients without explicit user setup.** We do not ship a network transport. If a user wants to control Fire from a remote machine, they configure that themselves.
- **NOT a Bartender API replacement.** We are not building a general-purpose menu bar automation API for arbitrary third-party apps. This is an MCP interface for *Fire's own state*, exposed to local AI agents.
- **NOT a replacement for Fire's GUI.** The settings panes remain the primary interface. MCP is a power-user escape hatch, not the default interaction model.

### Security Risks

- **Rogue MCP client gaining persistent layout control.** Mitigated by: (1) Keychain-scoped consent per client binary path, (2) write tools require explicit user approval via notification, (3) revocation is instant (Keychain update checked on every call), (4) same-team XPC peer requirement prevents unsigned processes from injecting XPC messages.
- **Process impersonation.** A malicious process could rename itself to match an approved client path. Mitigated by: Keychain entry stores SHA-256 of the binary at consent time; IceMCPBridge re-hashes on each write call and rejects mismatches.
- **Consent notification spoofing.** The notification is posted by the Fire main app, not by IceMCPBridge, so a compromised bridge binary cannot bypass the UI.

### Performance

- **XPC overhead per call.** Each tool call requires an XPC round-trip. The existing `sendSync` path measures ~2ms for `sourcePID`. Layout operations may take 5–15ms due to Accessibility API calls. This is acceptable for LLM-driven workflows (latency budget is seconds, not milliseconds). Batch operations should be considered for Phase 5 (e.g., `apply_layout` is already atomic at the XPC level).
- **Cold start.** IceMCPBridge launches with the LLM client. First XPC connection setup adds ~50ms. Subsequent calls reuse the session.

### Apple App Sandbox Compatibility

- IceMCPBridge runs *outside* the App Sandbox (it is a CLI binary, not sandboxed). The main Fire app is also unsandboxed (required for Accessibility API access). This is consistent with the existing architecture.
- If Fire ever distributes via the Mac App Store with sandboxing, IceMCPBridge would need to be re-architected as an XPC service within the app group. This is a future concern, not a blocker for Phase 4.5.
- Keychain access from IceMCPBridge requires the `com.jordanbaird.Fire.mcp-consent` service to be in the same access group. This works today with the same-team signing requirement.

## 8. Effort Estimate

| Component | Estimate | Notes |
|---|---|---|
| MCP server scaffold (IceMCPBridge target, stdio transport, MCP protocol handlers) | 3 hours | Use Swift MCP SDK or port from reference impl |
| XPC extension (new Request/Response cases, handler in Listener.swift) | 2 hours | Extending existing pattern; 6 new cases |
| 6 tool implementations (input validation → XPC call → response formatting) | 3 hours | Mostly mechanical; `list_items` is the most complex |
| Auth/consent flow (Keychain read/write, consent request XPC, notification UI) | 3 hours | Keychain wrapper + notification action handler |
| Onboarding UI (Advanced settings pane with copy-paste snippets, client list, revoke) | 2 hours | SwiftUI settings pane |
| Docs + config snippets (this document, README, per-client examples) | 1 hour | Mostly written already |
| **Total** | **~14 hours (1.5–2 dev days)** | |

## 9. Open Questions

1. **MCP SDK choice:** Build the MCP protocol layer from scratch in Swift, or wrap the TypeScript reference implementation via a bundled Node runtime? A native Swift implementation is cleaner but more upfront work; Node wrapping adds a dependency.

2. **Layout storage format:** Should saved layouts be stored in the existing Ice plist, or in a separate JSON file that IceMCPBridge can read without XPC? Separate file is simpler but creates a sync problem.

3. **Consent granularity:** Should users be able to grant consent per-tool (e.g., "allow `hide_item` but not `move_item`") or is read-only vs. write sufficient for MVP? Per-tool is more secure but adds UI complexity.

4. **IceMCPBridge lifecycle:** Should Fire auto-launch IceMCPBridge as a launch agent, or should LLM clients be responsible for launching it? The stdio transport assumes client-managed lifecycle, but a socket transport would need Fire to manage the process.

5. **Bundle ID transition:** Should the XPC service name include a version marker (`com.jordanbaird.Fire.MenuBarItemService.v1`) to allow future protocol changes without breaking older IceMCPBridge binaries?

6. **Concurrent client handling:** Can multiple LLM clients connect simultaneously? The current XPC `sendSync` model serializes requests. Should IceMCPBridge queue concurrent tool calls, or should the XPC layer support async responses?

7. **Undo support:** Should `move_item` / `hide_item` / `show_item` return an undo token that lets the LLM reverse the operation? This would make destructive tools safer but adds state tracking complexity.

---

## 10. Resolved Decisions (2026-05-26, operator review)

Each open question now has a binding decision plus rationale. Where the decision was based on new research (e.g., discovering an existing SDK), the finding is captured here so future maintainers can re-evaluate if the landscape shifts.

### Q1 → Use official `modelcontextprotocol/swift-sdk` as Swift Package dependency

**Decision:** Import the [official Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) (1392⭐, Anthropic-sanctioned) via Swift Package Manager. Do NOT write our own MCP protocol layer.

**Rationale:** The official SDK already exists, is actively maintained, and is the canonical Swift implementation of the spec. Wrapping Node.js was a fallback if no good Swift option existed — it does. Building from scratch would duplicate work and create a long tail of spec-compliance bugs.

**Alternative SDKs evaluated:** `Cocoanetics/SwiftMCP` (155⭐, community), `Compiler-Inc/SwiftMCP` (49⭐), `DePasqualeOrg/swift-mcp` (23⭐). The official SDK has the biggest community + Anthropic backing, so it's the safe default.

### Q2 → Store layouts in the existing Ice plist

**Decision:** Saved layouts go in `~/Library/Preferences/com.jordanbaird.Ice.plist` (post-rebrand: `com.jordanbaird.Fire.plist`) alongside other Ice settings. No separate JSON file.

**Rationale:** Single source of truth. Sync problems from a separate JSON would be more painful than the indirection cost of going through XPC for layout reads. The XPC overhead is already in our budget.

### Q3 → Read-vs-write consent granularity for MVP

**Decision:** Two consent levels: `read-only` (auto-grant after first run) and `write` (explicit notification approval per client). No per-tool granularity in MVP.

**Rationale:** Simpler UX, faster MVP ship. Per-tool gating adds significant UI complexity for marginal security gain. Can be added as a Phase 5+ "Advanced privacy" setting if users ask for it.

### Q4 → Client-managed lifecycle (standard MCP stdio model)

**Decision:** LLM clients launch IceMCPBridge on demand via stdio. Fire does NOT auto-start it as a launch agent.

**Rationale:** This is the standard MCP transport model — every other MCP server works this way. Auto-launching from Fire would create zombie processes when LLM clients exit. Client-managed lifecycle keeps process count predictable.

### Q5 → YES: include `.v1` version marker in XPC service name — with caution

**Decision:** XPC service name is `com.jordanbaird.Fire.MenuBarItemService.v1` (post-rebrand). All MCP-extended Request/Response cases live behind this version.

**Caveat:** Existing layout UI XPC calls (the `sourcePID` path) must NOT break when we add `.v1`. Keep the existing service name running alongside `.v1`, OR migrate both atomically. Pre-rebrand testing must confirm fire.X builds still resolve menu bar items after the rename.

**Rationale:** Future protocol changes (e.g., extending Response with new fields) would silently corrupt old IceMCPBridge binaries without versioning. The cost of adding `.v1` now is one extra string — the cost of skipping it is breaking-change pain later.

### Q6 → Serialize concurrent client requests for MVP — accept conflict as edge case

**Decision:** XPC `sendSync` model stays. If two LLM clients connect at the same time, requests queue. We ignore the rare race condition where two clients try to move the same item simultaneously.

**Rationale:** Edge case. Realistically one user is using one LLM client at a time. Building async XPC + queue management would triple the implementation work for a scenario almost no one hits. Document the limitation, move on.

### Q7 → YES: undo tokens, with auto-expiration (e.g., 1 hour)

**Decision:** Destructive tools (`move_item`, `hide_item`, `show_item`, `apply_layout`) return an `undo_token` field in their response. A separate `undo(token)` tool reverts the operation. **Tokens expire automatically after 1 hour and the undo log is rotated to keep storage bounded** — no infinite scroll of every action ever taken.

**Rationale:** One of the strongest safety nets against LLM mistakes. Cheap to implement (a small ring buffer of last N operations with timestamps). Auto-expiration keeps the storage tiny and avoids the "1GB log of every move I've ever made" problem.

### Q8 → Ignore Mac App Store / sandbox concerns for now

**Decision:** Phase 4.5 ships outside the App Sandbox, same as Fire today. No re-architecture for MAS compatibility.

**Rationale:** Accessibility API access is required for Fire's core value proposition (reading + manipulating menu bar items). App Sandbox blocks Accessibility outside narrowly-defined entitlements that don't cover our use case. MAS distribution is not viable without giving up the core value, so designing around it would be premature optimization.

### Q9 → Full strict tool annotations (`readOnly`, `destructive`, `idempotent`)

**Decision:** Every MCP tool gets complete, accurate annotations. `list_items` → `readOnly`. `move_item` → `destructive` + `idempotent` (moving to same position is no-op). `hide_item`/`show_item` → `destructive` + `idempotent`. `apply_layout` → `destructive`. `save_layout` → `readOnly` from menu bar state, `destructive` to layout storage.

**Rationale:** Annotations are NOT about defensive safety — they're about giving the LLM richer context to reason about side effects. A model that knows `move_item` is idempotent can retry safely; a model that knows `apply_layout` is destructive can ask for confirmation. Ten extra minutes of annotation work pays back every time an LLM makes a smarter call.

---

## 11. Effort Estimate — Revised After Decisions

| Component | Estimate | Notes |
|---|---|---|
| Add `modelcontextprotocol/swift-sdk` as Swift Package dependency, IceMCPBridge Xcode target scaffold | **1 hour** (was 3 — SDK does the protocol) | |
| XPC extension (6 new Request/Response cases + handlers) | 2 hours | |
| 6 tool implementations | 3 hours | |
| Undo token mechanism (ring buffer, 1h auto-expire, undo tool) | **+1.5 hours** (new, was 0) | |
| Tool annotations (readOnly/destructive/idempotent per tool) | **+0.5 hours** | |
| Auth/consent flow (read-only auto-grant + write notification) | 2 hours (was 3 — simpler granularity) | |
| Onboarding UI (Advanced settings pane) | 2 hours | |
| Docs + config snippets | 1 hour | |
| `.v1` service name migration testing | **+1 hour** (new) | |
| **Total** | **~14 hours (1.5–2 dev days)** | Net same — Q1 savings absorbed by Q7+Q9 additions |
