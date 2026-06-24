@testable import Toggler
import XCTest

@MainActor
final class SettingsViewModelTests: XCTestCase {
    private func makeViewModel() throws -> SettingsViewModel {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        let fileURL = directory.appending(path: "shortcuts.txt")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return SettingsViewModel(store: ShortcutStore(configURL: fileURL), hyperkeyEnabled: false) { _ in }
    }

    func testEmptyStateIsSingleEmptyRow() throws {
        let viewModel = try makeViewModel()
        XCTAssertEqual(viewModel.rows.count, 1)
        XCTAssertTrue(viewModel.rows[0].isEmpty)
    }

    func testTouchingAFieldAppendsTrailingEmptyRow() throws {
        let viewModel = try makeViewModel()
        viewModel.rows[0].appTarget = "Safari"
        viewModel.rowsDidChange()

        XCTAssertEqual(viewModel.rows.count, 2)
        XCTAssertFalse(viewModel.rows[0].isEmpty)
        XCTAssertTrue(viewModel.rows[1].isEmpty)
    }

    func testDuplicateTrailingEmptyRowsCollapse() throws {
        let viewModel = try makeViewModel()
        viewModel.rows = [ShortcutRow(), ShortcutRow(), ShortcutRow()]
        viewModel.normalizeTrailingEmptyRow()

        XCTAssertEqual(viewModel.rows.count, 1)
    }

    func testFilledRowsKeepExactlyOneTrailingEmpty() throws {
        let viewModel = try makeViewModel()
        viewModel.rows = [
            ShortcutRow(appTarget: "Safari", shortcutText: "command+option+space")
        ]
        viewModel.rowsDidChange()

        XCTAssertEqual(viewModel.rows.count, 2)
        XCTAssertTrue(viewModel.rows.last?.isEmpty == true)
    }

    func testRemoveRowKeepsTrailingEmpty() throws {
        let viewModel = try makeViewModel()
        viewModel.rows = [
            ShortcutRow(appTarget: "Safari", shortcutText: "command+option+space"),
            ShortcutRow()
        ]
        let filledID = viewModel.rows[0].id
        viewModel.removeRow(filledID)

        XCTAssertEqual(viewModel.rows.count, 1)
        XCTAssertTrue(viewModel.rows[0].isEmpty)
    }
}
