//
//  main.swift
//  IceMCPBridge — Swift Package executable.
//
//  Phase 2 placeholder body. Worker A (Wave 2) replaces this with the
//  full MCP server: Server(name:version:capabilities:) + ListTools +
//  CallTool handlers + StdioTransport + XPCSession client that dispatches
//  to MenuBarItemService.
//
//  This file lives at /Users/pd/Developer/fire/IceMCPBridge/Sources/IceMCPBridge/main.swift
//  per Swift Package convention. The sibling MenuBarItemService.swift is
//  a symlink to ../../../Shared/Services/MenuBarItemService.swift — the
//  single source of truth for the XPC wire contract.
//
//  Build:
//    cd IceMCPBridge && swift build -c release
//  Output:
//    IceMCPBridge/.build/release/IceMCPBridge
//

import Foundation
import MCP

// Top-level entry — `main.swift` is implicit @main, so no @main attr.
let xpcServiceName: String = MenuBarItemService.name
let supportedSections = MenuBarItemService.ItemSection.allCases

FileHandle.standardError.write(Data("""
IceMCPBridge scaffold — Phase 2 / Option B (SwiftPM).
XPC service target: \(xpcServiceName)
Supported sections: \(supportedSections.map(\.rawValue).joined(separator: ", "))
MCP Server type: \(Server.self)
Worker A (Wave 2) fills in real server + tool handlers.
""".data(using: .utf8) ?? Data()))

