//
//  AgentInput.swift
//  Ice
//
//  Validation for strings an AI agent supplies that later appear in a consent
//  prompt (fire.10.3). The consent prompt is the LAST line of defense — the
//  user approves an action based on the displayed text — so an agent-controlled
//  `name` or `bundleID` must never be able to forge or disguise that text with
//  newlines, control characters, bidi overrides (RLO/LRO), zero-width joiners,
//  or other format trickery. We REJECT such input (translator throws a clear
//  error) rather than silently stripping it, so the agent gets an honest
//  failure instead of a half-sanitized surprise.
//
//  Pure + Foundation-only so it is unit-tested in the FireLogic package.
//

import Foundation

enum AgentInput {
    /// A display name safe to interpolate into a single-line consent prompt:
    /// non-empty after trimming, within `maxLength`, and free of control /
    /// format / separator / bidi / zero-width characters. Returns the trimmed
    /// name, or nil if it must be rejected.
    static func validName(_ raw: String, maxLength: Int = 120) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLength else { return nil }
        guard trimmed.unicodeScalars.allSatisfy(isSafeDisplayScalar) else { return nil }
        return trimmed
    }

    /// A bundle identifier constrained to the reverse-DNS character set
    /// (letters, digits, dot, hyphen), 1–256 chars. Anything else — including
    /// the format trickery `validName` blocks — is rejected. Returns the
    /// trimmed id or nil.
    static func validBundleID(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...256).contains(trimmed.count) else { return nil }
        guard trimmed.unicodeScalars.allSatisfy(isBundleIDScalar) else { return nil }
        return trimmed
    }

    // MARK: Scalar predicates

    private static func isSafeDisplayScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator,
             .surrogate, .privateUse, .unassigned:
            return false
        default:
            return true
        }
    }

    private static func isBundleIDScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "A"..."Z", "a"..."z", "0"..."9", ".", "-":
            return true
        default:
            return false
        }
    }
}
