import CoreGraphics
import Foundation
@testable import Toggler
import XCTest

final class HyperkeyTests: XCTestCase {
    func testDecorateAddsAllFourHyperModifiers() {
        let result = HyperkeyFlags.decorate([])

        XCTAssertTrue(result.contains(.maskCommand))
        XCTAssertTrue(result.contains(.maskAlternate))
        XCTAssertTrue(result.contains(.maskControl))
        XCTAssertTrue(result.contains(.maskShift))
    }

    func testDecoratePreservesExistingFlags() {
        let result = HyperkeyFlags.decorate(.maskSecondaryFn)

        XCTAssertTrue(result.contains(.maskSecondaryFn))
        XCTAssertTrue(result.contains(.maskCommand))
    }

    func testDecorateIsIdempotentForAlreadyPresentFlags() {
        let once = HyperkeyFlags.decorate(.maskShift)
        let twice = HyperkeyFlags.decorate(once)

        XCTAssertEqual(once, twice)
        XCTAssertEqual(twice, HyperkeyFlags.hyper)
    }

    func testApplyPayloadMapsCapsLockToF18() {
        // hidutil accepts hex integer literals (0x...), which is not strict JSON, so we
        // assert on the structure textually rather than parsing it.
        let payload = HyperkeyRemap.applyPayload

        XCTAssertTrue(payload.hasPrefix("{\"UserKeyMapping\":["))
        XCTAssertTrue(payload.hasSuffix("]}"))
        XCTAssertTrue(payload.contains("\"HIDKeyboardModifierMappingSrc\":0x700000039")) // Caps Lock HID usage
        XCTAssertTrue(payload.contains("\"HIDKeyboardModifierMappingDst\":0x70000006d")) // F18 HID usage
        // Exactly one mapping entry.
        XCTAssertEqual(payload.components(separatedBy: "HIDKeyboardModifierMappingSrc").count - 1, 1)
    }

    func testClearPayloadIsEmptyMapping() {
        XCTAssertEqual(HyperkeyRemap.clearPayload, "{\"UserKeyMapping\":[]}")
    }

    func testPreferenceDefaultsToFalse() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        XCTAssertFalse(HyperkeyPreference(defaults: defaults).isEnabled)
    }

    func testPreferencePersistsEnabledState() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        let preference = HyperkeyPreference(defaults: defaults)
        preference.isEnabled = true

        XCTAssertTrue(HyperkeyPreference(defaults: defaults).isEnabled)
    }

    // MARK: - applySettings gate decision

    func testShouldApplyWhenEnablingFromInactive() {
        // The reported regression: preference is already true (set before a failed
        // start) but the controller never came up. A Save with the toggle ON must
        // retry start() rather than treat it as an unchanged no-op.
        XCTAssertTrue(shouldApplyHyperkey(desired: true, isActive: false, isEnabled: true))
    }

    func testShouldApplyWhenEnablingFreshFromOff() {
        XCTAssertTrue(shouldApplyHyperkey(desired: true, isActive: false, isEnabled: false))
    }

    func testShouldNotApplyWhenAlreadyActiveAndEnabled() {
        // True no-op: avoids re-prompting for Accessibility on an unchanged Save.
        XCTAssertFalse(shouldApplyHyperkey(desired: true, isActive: true, isEnabled: true))
    }

    func testShouldApplyWhenDisablingActiveFeature() {
        XCTAssertTrue(shouldApplyHyperkey(desired: false, isActive: true, isEnabled: true))
    }

    func testShouldApplyWhenDisablingStuckPreference() {
        // Preference still true but controller inactive: disabling must run so the
        // stale preference gets cleared.
        XCTAssertTrue(shouldApplyHyperkey(desired: false, isActive: false, isEnabled: true))
    }

    func testShouldNotApplyWhenAlreadyOff() {
        XCTAssertFalse(shouldApplyHyperkey(desired: false, isActive: false, isEnabled: false))
    }
}
