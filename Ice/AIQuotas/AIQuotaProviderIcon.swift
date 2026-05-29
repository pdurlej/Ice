//
//  AIQuotaProviderIcon.swift
//  Ice
//
//  Loads per-provider brand icons for the AI Quotas menu-bar readout.
//
//  Source: the installed CodexBar.app's ProviderIcon-<provider>.svg
//  assets. AI Quotas already depends on the CodexBar CLI (same app
//  bundle), so reading its provider icons at runtime is consistent and
//  avoids vendoring brand assets into Fire. Falls back to nil (caller
//  uses a text label) when CodexBar isn't installed.
//

import AppKit

enum AIQuotaProviderIcon {
    private static var cache: [String: NSImage] = [:]

    /// Candidate CodexBar resource directories.
    private static let resourceDirs = [
        "/Applications/CodexBar.app/Contents/Resources",
    ]

    /// Returns the provider's brand icon, scaled to the given height,
    /// or nil if not found.
    static func image(for provider: AIQuotaProvider, height: CGFloat = 14) -> NSImage? {
        let key = "\(provider.rawValue)@\(height)"
        if let cached = cache[key] { return cached }

        for dir in resourceDirs {
            let path = "\(dir)/ProviderIcon-\(provider.rawValue).svg"
            guard let raw = NSImage(contentsOfFile: path) else { continue }
            let scaled = scaled(raw, toHeight: height)
            cache[key] = scaled
            return scaled
        }
        return nil
    }

    private static func scaled(_ image: NSImage, toHeight height: CGFloat) -> NSImage {
        let original = image.size
        guard original.height > 0 else { return image }
        let width = (original.width / original.height) * height
        let target = NSSize(width: width.rounded(), height: height)
        let out = NSImage(size: target)
        out.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: target),
            from: NSRect(origin: .zero, size: original),
            operation: .sourceOver,
            fraction: 1.0
        )
        out.unlockFocus()
        return out
    }
}
