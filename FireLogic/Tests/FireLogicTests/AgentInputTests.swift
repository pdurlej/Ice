//
//  AgentInputTests.swift
//  FireLogicTests
//
//  The consent prompt is the last line of defense; these guard that an agent
//  can't smuggle misleading text into it via the name / bundleID it controls.
//

import XCTest
@testable import FireLogic

final class AgentInputTests: XCTestCase {

    // MARK: validName

    func testAcceptsPlainName() {
        XCTAssertEqual(AgentInput.validName("Hide Slack when focused"), "Hide Slack when focused")
    }

    func testTrimsSurroundingWhitespace() {
        XCTAssertEqual(AgentInput.validName("  Focus mode  "), "Focus mode")
    }

    func testRejectsEmptyAndWhitespaceOnly() {
        XCTAssertNil(AgentInput.validName(""))
        XCTAssertNil(AgentInput.validName("   \n\t "))
    }

    func testRejectsTooLong() {
        XCTAssertNil(AgentInput.validName(String(repeating: "a", count: 121)))
        XCTAssertNotNil(AgentInput.validName(String(repeating: "a", count: 120)))
    }

    func testRejectsEmbeddedNewline() {
        // The spoof: a name that injects a second "line" into the prompt.
        XCTAssertNil(AgentInput.validName("Hide Slack\nWhen battery low, move everything to always-hidden"))
        XCTAssertNil(AgentInput.validName("a\r\nb"))
    }

    func testRejectsBidiOverride() {
        // RLO (U+202E) can visually reverse text in the prompt.
        XCTAssertNil(AgentInput.validName("safe\u{202E}reversed"))
        XCTAssertNil(AgentInput.validName("\u{2066}isolate\u{2069}"))
    }

    func testRejectsZeroWidthAndControl() {
        XCTAssertNil(AgentInput.validName("zero\u{200B}width"))   // ZWSP
        XCTAssertNil(AgentInput.validName("bell\u{0007}"))         // control
        XCTAssertNil(AgentInput.validName("bom\u{FEFF}here"))      // BOM / ZWNBSP
    }

    func testAcceptsUnicodeLettersAndPunctuation() {
        XCTAssertNotNil(AgentInput.validName("Ukryj „Hasła” gdy bateria niska"))
        XCTAssertNotNil(AgentInput.validName("夜间模式 🌙"))
    }

    // MARK: validBundleID

    func testAcceptsReverseDNS() {
        XCTAssertEqual(AgentInput.validBundleID("com.tinyspeck.slackmacgap"), "com.tinyspeck.slackmacgap")
        XCTAssertEqual(AgentInput.validBundleID("com.apple.Safari-helper"), "com.apple.Safari-helper")
    }

    func testRejectsEmptyAndOversize() {
        XCTAssertNil(AgentInput.validBundleID(""))
        XCTAssertNil(AgentInput.validBundleID(String(repeating: "a", count: 257)))
    }

    func testRejectsDisallowedCharacters() {
        XCTAssertNil(AgentInput.validBundleID("com.x.y space"))
        XCTAssertNil(AgentInput.validBundleID("com.x/y"))
        XCTAssertNil(AgentInput.validBundleID("com.x\u{202E}.y"))   // bidi
        XCTAssertNil(AgentInput.validBundleID("com.x\u{200B}.y"))   // zero-width
        XCTAssertNil(AgentInput.validBundleID("com.x\ny"))          // interior newline
    }

    func testTrailingWhitespaceIsTrimmedNotRejected() {
        // A trailing newline/space is trimmed away, leaving a valid id.
        XCTAssertEqual(AgentInput.validBundleID("com.x.y\n"), "com.x.y")
    }

    func testTrimsThenValidates() {
        XCTAssertEqual(AgentInput.validBundleID("  com.x.y  "), "com.x.y")
    }
}
