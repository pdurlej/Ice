//
//  main.swift
//  MCPBackend
//
//  Entry point for the MCP backend XPC service. Spawned by launchd
//  when a client (the IceMCPBridge binary that MCP clients launch)
//  connects to `com.jordanbaird.Ice.MCPBackend`. Runs in its own
//  subprocess - same pattern as MenuBarItemService.xpc.
//
//  Unlike Option D (which tried to host this listener inside Ice
//  main app's process, but launchd refused MachServices registration
//  for non-LaunchAgent GUI apps - documented in HANDOFF), this is
//  an embedded .xpc bundle. macOS's standard supported pattern.
//
//  Cross-process state implications: this subprocess doesn't share
//  state with Ice main app. Each tool call does a fresh AX snapshot
//  via Bridging + WindowInfo (read path), and posts CGEvent drag
//  events directly (write path - implemented in W2 from a lean port
//  of MenuBarItemManager's drag-event logic).
//

import Foundation

// SourcePIDCache observes NSWorkspace.runningApplications and lazily
// fills its (windowID -> sourcePID) map via AX scans. Without start()
// the observer cancellable is never instantiated, so updates miss and
// every lookup falls back to ownerPID -- which on macOS 26 collapses
// to com.apple.controlcenter for every reparented item. MenuBarItemService
// already does this in its own main.swift; MCPBackend needs the same.
SourcePIDCache.shared.start()

Listener.shared.activate()
RunLoop.current.run()
