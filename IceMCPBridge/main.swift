//
//  main.swift
//  IceMCPBridge
//
//  Entry point for the Fire MCP Server (Phase 4.5, Phase 2 scaffold).
//
//  This file is intentionally minimal at Phase 2. It serves two
//  purposes only:
//
//    1. Verify the IceMCPBridge target builds.
//    2. Verify the `Shared` group is reachable, so
//       `MenuBarItemService.Request` / `.Response` / `.ItemSection` /
//       `.ItemInfo` types from
//       `Shared/Services/MenuBarItemService.swift` can be referenced.
//
//  KNOWN PHASE-2 LIMITATION — MCP SDK not yet imported:
//
//  Adding `import MCP` here triggers Xcode's transitive Swift Package
//  dependency resolution bug: the IceMCPBridge target builds against
//  the `MCP` library but Xcode fails to propagate MCP's transitive
//  deps (`swift-nio` → `swift-collections.DequeModule`,
//  `swift-atomics.Atomics`) to this target's compile environment.
//  Errors look like:
//      error: unable to resolve module dependency: 'DequeModule'
//      error: unable to resolve module dependency: 'Atomics'
//
//  Three options to resolve in Phase 3, in order of preference:
//
//    A) Explicitly add `XCRemoteSwiftPackageReference` entries for
//       `swift-collections` and `swift-atomics` to the project, then
//       create `XCSwiftPackageProductDependency` entries linking
//       `Collections` / `Atomics` / `NIOCore` to this target.
//       Standard SPM-in-Xcode workaround.
//
//    B) Switch IceMCPBridge from an Xcode target to a `swift build`
//       executable target hosted in a sibling `Package.swift`, then
//       embed the produced binary into Ice.app via a Copy Files build
//       phase. Cleanest from a Swift PM correctness perspective but
//       requires reworking the build pipeline.
//
//    C) Use a Swift MCP implementation without an NIO dependency
//       (e.g., a hand-rolled stdio transport). Reduces dep weight but
//       loses the official SDK's protocol compliance maintenance.
//
//  Phase 3 starts by resolving this. The first-cut MCP server logic
//  from a Swarmheart worker is saved alongside as
//  `main.swift.proposal.phase3` — review-but-don't-trust shape only
//  (it guesses MCP SDK API names and uses NSXPCConnection where we
//  use XPCSession).
//

import Foundation

// Compile-time witness that the Shared/ group is linked into this
// target. If it isn't, the type references below fail to resolve and
// the build fails — exactly the signal we want at Phase 2.
private let xpcServiceName: String = MenuBarItemService.name
private let supportedSections = MenuBarItemService.ItemSection.allCases

print("IceMCPBridge scaffold — Phase 2.")
print("XPC service target: \(xpcServiceName)")
print("Supported sections: \(supportedSections.map(\.rawValue).joined(separator: ", "))")
print("MCP SDK linkage deferred to Phase 3 (transitive-dep resolution).")
print("Next session: see header comment of this file for the three options.")
