import Carbon.HIToolbox
@testable import Toggler
import XCTest

final class ShortcutParserTests: XCTestCase {
    func testHyperShortcutExpandsToAllModifiers() throws {
        let shortcut = try ShortcutParser.parse(
            "hyper+t",
            keyResolver: StubKeyResolver(["t": UInt32(kVK_ANSI_T)])
        )

        XCTAssertEqual(shortcut.keyCode, UInt32(kVK_ANSI_T))
        XCTAssertNotEqual(shortcut.carbonModifiers & UInt32(cmdKey), 0)
        XCTAssertNotEqual(shortcut.carbonModifiers & UInt32(optionKey), 0)
        XCTAssertNotEqual(shortcut.carbonModifiers & UInt32(controlKey), 0)
        XCTAssertNotEqual(shortcut.carbonModifiers & UInt32(shiftKey), 0)
    }

    func testShortcutParserUsesInjectedLayoutResolverForPrintableKeys() throws {
        let shortcut = try ShortcutParser.parse(
            "hyper+p",
            keyResolver: StubKeyResolver(["p": UInt32(kVK_ANSI_R)])
        )

        XCTAssertEqual(shortcut.keyCode, UInt32(kVK_ANSI_R))
    }

    func testShortcutStoreLoadsBindingsAndReportsBadLines() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        let fileURL = directory.appending(path: "shortcuts.txt")

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
        # comments are ignored
        hyper+t = com.apple.Terminal
        cmd+option+space = Safari
        this is not valid
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let result = ShortcutStore(configURL: fileURL).load()

        XCTAssertEqual(result.bindings.count, 2)
        XCTAssertEqual(result.bindings[0].target.rawValue, "com.apple.Terminal")
        XCTAssertEqual(result.bindings[1].target.rawValue, "Safari")
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(result.errors[0].lineNumber, 4)
    }
}

private struct StubKeyResolver: KeyboardShortcutKeyResolving {
    let keyCodes: [String: UInt32]

    init(_ keyCodes: [String: UInt32]) {
        self.keyCodes = keyCodes
    }

    func keyCode(for token: String) -> UInt32? {
        keyCodes[token]
    }
}
