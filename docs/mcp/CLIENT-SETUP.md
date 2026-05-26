# Connecting MCP clients to Fire

Fire exposes a Model Context Protocol (MCP) server so AI assistants can read and modify your menu bar layout via tool calls. The bridge binary ships embedded in Ice.app at `/Applications/Ice.app/Contents/MacOS/IceMCPBridge`. Your MCP client launches it directly via stdio - no daemon or background process to manage.

## Prerequisites

- Ice.app installed in `/Applications` (the bundle name stays `Ice.app`; the user-facing brand is "Fire from Ice")
- Settings → Advanced → "Enable MCP server" toggled ON
- (For write operations) "Allow write operations" toggled ON
- macOS 26 or later

## Claude Desktop

Edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "fire": {
      "command": "/Applications/Ice.app/Contents/MacOS/IceMCPBridge",
      "args": ["--stdio"]
    }
  }
}
```

Restart Claude Desktop. The `fire` tools should appear in the tool drawer.

## Claude Code

Run from your terminal:

```bash
claude mcp add fire /Applications/Ice.app/Contents/MacOS/IceMCPBridge --stdio
```

## Cursor

Edit `~/.cursor/mcp.json` for a global install, or `.cursor/mcp.json` in your project root for a per-project install:

```json
{
  "mcpServers": {
    "fire": {
      "command": "/Applications/Ice.app/Contents/MacOS/IceMCPBridge",
      "args": ["--stdio"]
    }
  }
}
```

Restart Cursor. See [Cursor's MCP docs](https://cursor.com/docs/context/mcp) for additional options (env vars, per-workspace overrides).

## Codex (OpenAI Codex CLI)

Codex uses TOML. Add to `~/.codex/config.toml`:

```toml
[mcp_servers.fire]
command = "/Applications/Ice.app/Contents/MacOS/IceMCPBridge"
args = ["--stdio"]
```

Restart Codex. See [Codex's MCP docs](https://github.com/openai/codex/blob/main/docs/config.md#mcp_servers) for additional options (env vars, transport types).

## Available tools

- `list_items` - read-only - list menu bar items, optionally filtered by section (`alwaysVisible` / `hidden` / `alwaysHidden`)
- `hide_item` - write - move an item to the hidden section by bundle ID
- `show_item` - write - move an item to the alwaysVisible section by bundle ID
- `move_item` - write - move an item to any section at an optional position
- `save_layout` - write - snapshot the current layout under a name
- `apply_layout` - write - restore a previously saved layout

## Privacy

Fire processes all MCP requests locally. No menu bar state, bundle IDs, or layout data leaves your machine via Fire. Your MCP client may send tool call args (e.g., bundle ID strings) to its model provider as part of its normal operation - read your client's privacy docs for details.

## Troubleshooting

If the tools don't appear in your client after configuration:

1. Verify Ice.app is installed at `/Applications/Ice.app` (`ls /Applications/Ice.app/Contents/MacOS/IceMCPBridge` should return the binary).
2. Verify Settings → Advanced → "Enable MCP server" is ON.
3. Restart your MCP client.
4. Check your client's MCP logs (Claude Desktop logs are in `~/Library/Logs/Claude/`).
