// swift-tools-version:5.9
//
//  IceMCPBridge — Swift Package executable.
//
//  Lives in `Bridge/` (NOT `IceMCPBridge/`) on purpose. Xcode 26's
//  SwiftPM bridge cannot resolve swift-nio's transitive module deps
//  (DequeModule, Atomics) when the host is a tool-product target —
//  every variation of Option A (explicit XCRemoteSwiftPackageReference
//  + XCSwiftPackageProductDependency + PBXBuildFile + project
//  packageReferences) hits the same `unable to resolve module
//  dependency: 'DequeModule'` error from NIOCore's compile phase.
//
//  The exact same package graph builds clean with vanilla SwiftPM
//  (`cd Bridge && swift build` — 335 modules, ~30s). Documented bug:
//  https://forums.swift.org/t/xcode-26-unable-to-find-module-dependency/80516
//
//  Keeping `Bridge/` outside `IceMCPBridge/` also keeps it outside the
//  Xcode IceMCPBridge target's fileSystemSynchronizedGroup, so Xcode
//  ignores Package.swift / Sources / .build entirely.
//
//  Build flow (intended after Wave 1 plumbing finishes):
//    1. `cd Bridge && swift build -c release` produces
//       `Bridge/.build/release/IceMCPBridge`.
//    2. Ice.xcodeproj's Ice target has a Run Script phase that invokes
//       (1) and a Copy Files phase that embeds the binary into
//       `Ice.app/Contents/MacOS/IceMCPBridge`.
//    3. The old Xcode-side IceMCPBridge target stays as a no-op
//       placeholder compiling its Phase-2 stub main.swift — its output
//       binary is never embedded into Ice.app.
//
//  Wire contract symlinks:
//  Sources/IceMCPBridge/{MenuBarItemService,WindowInfo,Bridging,Shims,
//  Logging,SharedExtensions,AXHelpers}.swift are symlinks to the one
//  true files under ../Shared/. Keeps the bridge in lockstep with the
//  Xcode targets without duplicating code.
//

import PackageDescription

let package = Package(
    name: "IceMCPBridge",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "IceMCPBridge", targets: ["IceMCPBridge"]),
        .executable(name: "fire", targets: ["FireCLI"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/modelcontextprotocol/swift-sdk",
            from: "0.10.0"
        ),
        // Used by AXHelpers in symlinked Shared/Utilities/.
        .package(
            url: "https://github.com/tmandry/AXSwift",
            from: "0.3.2"
        ),
    ],
    targets: [
        .executableTarget(
            name: "IceMCPBridge",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "AXSwift", package: "AXSwift"),
            ],
            path: "Sources/IceMCPBridge"
        ),
        .executableTarget(
            name: "FireCLI",
            path: "Sources/FireCLI"
        ),
    ]
)
