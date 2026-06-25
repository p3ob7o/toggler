@testable import Toggler
import XCTest

final class SettingsPersistenceTests: XCTestCase {
    func testSaveThenLoadRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        let fileURL = directory.appending(path: "shortcuts.txt")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ShortcutStore(configURL: fileURL)
        try store.save([
            .init(shortcutText: "control+option+shift+command+t", appTarget: "com.apple.Terminal"),
            .init(shortcutText: "control+option+command+s", appTarget: "Safari"),
            // App target with a space must survive quoting/unquoting.
            .init(shortcutText: "command+option+space", appTarget: "/Applications/Google Chrome.app")
        ])

        let result = store.load()
        XCTAssertEqual(result.errors.count, 0)
        XCTAssertEqual(result.bindings.count, 3)
        XCTAssertEqual(result.bindings[0].target.rawValue, "com.apple.Terminal")
        XCTAssertEqual(result.bindings[1].target.rawValue, "Safari")
        XCTAssertEqual(result.bindings[2].target.rawValue, "/Applications/Google Chrome.app")
    }

    func testSaveEmptyEntriesWritesParseableFileWithNoBindings() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        let fileURL = directory.appending(path: "shortcuts.txt")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ShortcutStore(configURL: fileURL)
        try store.save([])

        let result = store.load()
        XCTAssertEqual(result.bindings.count, 0)
        XCTAssertEqual(result.errors.count, 0)
    }

    func testAppScannerDeduplicatesAndFallsBackForName() throws {
        let root1 = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let root2 = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root2, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root1)
            try? FileManager.default.removeItem(at: root2)
        }

        // Same bundle id present in two roots -> de-duplicated to one entry.
        try makeBundle(in: root1, name: "Foo", displayName: "Foo", bundleID: "com.test.foo")
        try makeBundle(in: root2, name: "Foo", displayName: "Foo", bundleID: "com.test.foo")
        // No Info.plist -> name falls back to filename, target falls back to path.
        let barURL = root1.appending(path: "Bar.app")
        try FileManager.default.createDirectory(at: barURL, withIntermediateDirectories: true)

        let apps = AppScanner.scan(roots: [root1, root2])

        XCTAssertEqual(apps.filter { $0.bundleID == "com.test.foo" }.count, 1)

        let bar = try XCTUnwrap(apps.first { $0.name == "Bar" })
        XCTAssertNil(bar.bundleID)
        XCTAssertEqual(bar.targetRawValue, bar.path)

        let foo = try XCTUnwrap(apps.first { $0.bundleID == "com.test.foo" })
        XCTAssertEqual(foo.targetRawValue, foo.path)
    }

    private func makeBundle(in root: URL, name: String, displayName: String, bundleID: String) throws {
        let contents = root.appending(path: "\(name).app").appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundleIdentifier</key>
          <string>\(bundleID)</string>
          <key>CFBundleDisplayName</key>
          <string>\(displayName)</string>
          <key>CFBundleName</key>
          <string>\(name)</string>
        </dict>
        </plist>
        """
        try plist.write(to: contents.appending(path: "Info.plist"), atomically: true, encoding: .utf8)
    }
}
