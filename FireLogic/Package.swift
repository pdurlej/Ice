// swift-tools-version:5.9
//
//  FireLogic — standalone test harness for Fire's security-critical pure logic.
//
//  The Ice app target has no test target (and can't easily get one without
//  codesigning/TCC in CI). This package symlinks the FEW Foundation-only,
//  security-critical sources out of Ice/Automation/ into a plain SPM module so
//  `swift test --package-path FireLogic` runs them with zero app/AppKit/TCC
//  dependencies — CI-friendly and fast.
//
//  Sources are SYMLINKS to the one true files under ../Ice/Automation/ (same
//  pattern as the Bridge package), so the tests guard the exact code the app
//  ships. The only non-symlinked file is Shims.swift (a `Logger(category:)`
//  stand-in).
//
//  Covered today: TriggerCanonicalizer (digest determinism — the sealed-grant
//  linchpin), AutomationGrantStore (seal/validate roundtrip + tamper), and
//  TimeWindow (midnight/day/tz edges).
//

import PackageDescription

let package = Package(
    name: "FireLogic",
    platforms: [
        .macOS(.v13),
    ],
    targets: [
        .target(
            name: "FireLogic",
            path: "Sources/FireLogic"
        ),
        .testTarget(
            name: "FireLogicTests",
            dependencies: ["FireLogic"],
            path: "Tests/FireLogicTests"
        ),
    ]
)
