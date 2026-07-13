# IceMCPBridge

This directory is the scaffold for the **Fire MCP Server** (Phase 4.5 of
the FORK.md roadmap). Tracked in [Issue #1](https://github.com/pdurlej/fire-from-ice/issues/1).
Architecture doc: [`docs/mcp/ARCHITECTURE.md`](../docs/mcp/ARCHITECTURE.md).

## Status: scaffolded, not yet implemented

The Swift Package dependency on
[`modelcontextprotocol/swift-sdk`](https://github.com/modelcontextprotocol/swift-sdk)
is already added at the project level. The next focused work session needs to:

1. **Create the `IceMCPBridge` Xcode target** (separate CLI binary, embedded
   in Ice.app's `MacOS/` alongside the main `Ice` binary, or as a separate
   helper). Must link `modelcontextprotocol/swift-sdk` + the shared
   `MenuBarItemService` types.

2. **Implement `main.swift`** as the MCP server entry point (stdio
   transport). Roughly:
   ```swift
   import MCP
   import Foundation

   let server = MCPServer(name: "IceMCPBridge", version: "0.1.0")
   // register 6 tools — see docs/mcp/ARCHITECTURE.md §3
   try server.run()
   ```

3. **Extend `MenuBarItemService.Request` / `Response` enums** with the 6
   new cases (`listItems`, `moveItem`, `hideItem`, `showItem`,
   `applyLayout`, `saveLayout`).

4. **Implement tool handlers** that translate MCP tool calls → XPC
   requests via the existing `MenuBarItemService.Connection`.

5. **Add the consent/auth flow** — Keychain-scoped per-client-binary
   consent with SHA-256 anti-impersonation, notification UI in the main
   Ice app.

6. **Add the onboarding UI** — Advanced Settings → "MCP Server" subpane
   with copy-paste configs for Claude Code / Codex / Cursor / Continue.

7. **Undo remains deferred** — do not advertise an undo token or tool unless a
   real implementation, consent analysis, and end-to-end verification land.

## Effort estimate

~14 hours / 1.5–2 focused dev days. Decisions for all 9 open questions
are already captured in `docs/mcp/ARCHITECTURE.md` §10. No more design
work needed before implementation starts.

## Files expected in this directory after MVP

- `main.swift` — MCP server entry, MCPServer setup, tool registration
- `Tools/ListItems.swift` — tool handler
- `Tools/MoveItem.swift`
- `Tools/HideItem.swift`
- `Tools/ShowItem.swift`
- `Tools/ApplyLayout.swift`
- `Tools/SaveLayout.swift`
- `Auth/Consent.swift` — Keychain-scoped per-client-binary consent
- `Auth/BinaryHasher.swift` — SHA-256 hash + verification
- `XPCClient.swift` — wraps `MenuBarItemService.Connection` for tool use

## Why this scaffold exists now (and not the implementation)

The user invoked `/swarmheart` with intent: "na bugi, a potem na mcp,
Ollama Pro czeka na Ciebie królu ostrzy!". Today we shipped the XPC bug
class evangelism (10 comments + 1 PR + Sentry crash reporting in
fire.5) and prepared the MCP work surface so the next focused session
can start coding immediately without setup friction.
