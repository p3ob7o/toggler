import AppKit
import Carbon.HIToolbox
@testable import Toggler
import XCTest

final class ShortcutEventEncoderTests: XCTestCase {
    func testAllFourModifiersWithLetterEmitsCanonicalOrderAndRoundTrips() throws {
        let stub = StubResolver(
            forward: ["t": UInt32(kVK_ANSI_T)],
            reverse: [UInt32(kVK_ANSI_T): "t"]
        )

        let token = ShortcutEventEncoder.tokenString(
            keyCode: UInt16(kVK_ANSI_T),
            modifierFlags: [.command, .option, .control, .shift],
            characterResolver: stub
        )

        XCTAssertEqual(token, "control+option+shift+command+t")

        let parsed = try ShortcutParser.parse(XCTUnwrap(token), keyResolver: stub)
        XCTAssertEqual(parsed.keyCode, UInt32(kVK_ANSI_T))
        XCTAssertNotEqual(parsed.carbonModifiers & UInt32(cmdKey), 0)
        XCTAssertNotEqual(parsed.carbonModifiers & UInt32(optionKey), 0)
        XCTAssertNotEqual(parsed.carbonModifiers & UInt32(controlKey), 0)
        XCTAssertNotEqual(parsed.carbonModifiers & UInt32(shiftKey), 0)
    }

    func testSpecialKeyResolvedByKeyCodeRoundTrips() throws {
        // The character resolver should be ignored for special keys.
        let stub = StubResolver(forward: ["space": UInt32(kVK_Space)], reverse: [:])

        let token = ShortcutEventEncoder.tokenString(
            keyCode: UInt16(kVK_Space),
            modifierFlags: [.option],
            characterResolver: stub
        )

        XCTAssertEqual(token, "option+space")

        let parsed = try ShortcutParser.parse(XCTUnwrap(token), keyResolver: stub)
        XCTAssertEqual(parsed.keyCode, UInt32(kVK_Space))
        XCTAssertNotEqual(parsed.carbonModifiers & UInt32(optionKey), 0)
    }

    func testFunctionAndArrowKeysMapByKeyCode() throws {
        let stub = StubResolver(forward: ["f5": UInt32(kVK_F5), "left": UInt32(kVK_LeftArrow)], reverse: [:])

        XCTAssertEqual(
            ShortcutEventEncoder.tokenString(keyCode: UInt16(kVK_F5), modifierFlags: [.control], characterResolver: stub),
            "control+f5"
        )
        XCTAssertEqual(
            ShortcutEventEncoder.tokenString(keyCode: UInt16(kVK_LeftArrow), modifierFlags: [.command], characterResolver: stub),
            "command+left"
        )
    }

    func testShiftedNumberUsesUnshiftedCharacterNotSymbol() throws {
        // Shift+2 must record as "2", never "@".
        let stub = StubResolver(
            forward: ["2": UInt32(kVK_ANSI_2)],
            reverse: [UInt32(kVK_ANSI_2): "2"]
        )

        let token = ShortcutEventEncoder.tokenString(
            keyCode: UInt16(kVK_ANSI_2),
            modifierFlags: [.shift],
            characterResolver: stub
        )

        XCTAssertEqual(token, "shift+2")
        XCTAssertFalse(try XCTUnwrap(token).contains("@"))
    }

    func testEqualsKeyNeverEmitsPlusAndRoundTrips() throws {
        // The "=" / "+" key resolves to its unshifted char so the "+" token
        // separator is never broken.
        let stub = StubResolver(
            forward: ["=": UInt32(kVK_ANSI_Equal)],
            reverse: [UInt32(kVK_ANSI_Equal): "="]
        )

        let token = try XCTUnwrap(ShortcutEventEncoder.tokenString(
            keyCode: UInt16(kVK_ANSI_Equal),
            modifierFlags: [.command],
            characterResolver: stub
        ))

        XCTAssertEqual(token, "command+=")
        XCTAssertEqual(token.split(separator: "+").map(String.init), ["command", "="])

        let parsed = try ShortcutParser.parse(token, keyResolver: stub)
        XCTAssertEqual(parsed.keyCode, UInt32(kVK_ANSI_Equal))
    }

    func testPunctuationCommaRoundTrips() throws {
        let stub = StubResolver(
            forward: [",": UInt32(kVK_ANSI_Comma)],
            reverse: [UInt32(kVK_ANSI_Comma): ","]
        )

        let token = try XCTUnwrap(ShortcutEventEncoder.tokenString(
            keyCode: UInt16(kVK_ANSI_Comma),
            modifierFlags: [.command],
            characterResolver: stub
        ))

        XCTAssertEqual(token, "command+,")
        let parsed = try ShortcutParser.parse(token, keyResolver: stub)
        XCTAssertEqual(parsed.keyCode, UInt32(kVK_ANSI_Comma))
    }

    func testEscapeWithCommandCommitsButBareEscapeIsRejectedByParser() throws {
        let stub = StubResolver(forward: ["escape": UInt32(kVK_Escape)], reverse: [:])

        let withCommand = try XCTUnwrap(ShortcutEventEncoder.tokenString(
            keyCode: UInt16(kVK_Escape),
            modifierFlags: [.command],
            characterResolver: stub
        ))
        XCTAssertEqual(withCommand, "command+escape")

        // Bare escape (no modifiers) encodes to just the key, which the parser
        // rejects for missing a modifier (the recorder uses this to cancel).
        let bare = try XCTUnwrap(ShortcutEventEncoder.tokenString(
            keyCode: UInt16(kVK_Escape),
            modifierFlags: [],
            characterResolver: stub
        ))
        XCTAssertEqual(bare, "escape")
        XCTAssertThrowsError(try ShortcutParser.parse(bare, keyResolver: stub))
    }

    func testHasShortcutModifier() {
        XCTAssertFalse(ShortcutEventEncoder.hasShortcutModifier([]))
        XCTAssertFalse(ShortcutEventEncoder.hasShortcutModifier([.capsLock]))
        XCTAssertTrue(ShortcutEventEncoder.hasShortcutModifier([.command]))
        XCTAssertTrue(ShortcutEventEncoder.hasShortcutModifier([.control, .option]))
    }
}

private struct StubResolver: KeyboardShortcutKeyResolving, KeyboardShortcutCharacterResolving {
    let forward: [String: UInt32]
    let reverse: [UInt32: String]

    func keyCode(for token: String) -> UInt32? { forward[token] }
    func character(forKeyCode keyCode: UInt16) -> String? { reverse[UInt32(keyCode)] }
}
