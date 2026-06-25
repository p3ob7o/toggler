import AppKit
import Carbon.HIToolbox

/// The four modifier flags that make up the Hyperkey.
enum HyperkeyFlags {
    static let hyper: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]

    /// Adds the Hyper modifiers to an existing flag set. Idempotent: flags already
    /// present are left untouched.
    static func decorate(_ flags: CGEventFlags) -> CGEventFlags {
        flags.union(hyper)
    }
}

/// Builds and applies the `hidutil` key remap that neutralizes Caps Lock by turning it
/// into F18 (an otherwise-unused key with no alpha-lock semantics).
enum HyperkeyRemap {
    /// HID usage for Caps Lock (keyboard usage page 0x07, usage 0x39).
    static let capsLock: UInt64 = 0x700000039
    /// HID usage for F18 (keyboard usage page 0x07, usage 0x6D).
    static let f18: UInt64 = 0x70000006D

    static var applyPayload: String {
        payload(source: capsLock, destination: f18)
    }

    static var clearPayload: String {
        "{\"UserKeyMapping\":[]}"
    }

    static func payload(source: UInt64, destination: UInt64) -> String {
        "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":0x\(String(source, radix: 16))," +
        "\"HIDKeyboardModifierMappingDst\":0x\(String(destination, radix: 16))}]}"
    }

    @discardableResult
    static func apply() -> Bool {
        run(applyPayload)
    }

    @discardableResult
    static func clear() -> Bool {
        run(clearPayload)
    }

    private static func run(_ payload: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--set", payload]

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                NSLog("Toggler: hidutil exited with status \(process.terminationStatus)")
                return false
            }
            return true
        } catch {
            NSLog("Toggler: hidutil failed: \(error.localizedDescription)")
            return false
        }
    }
}

/// Persists the user's opt-in choice for the Caps Lock → Hyperkey feature.
///
/// This stores *intent only*. Whether the feature is actually running also depends on
/// macOS Accessibility being granted (see `HyperkeyController.isActive`).
struct HyperkeyPreference {
    private let defaults: UserDefaults
    private let key = "capsLockHyperkeyEnabled"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Defaults to `false` when unset, so the feature is opt-in.
    var isEnabled: Bool {
        get { defaults.bool(forKey: key) }
        nonmutating set { defaults.set(newValue, forKey: key) }
    }
}

/// Turns Caps Lock into a Hyperkey (Command+Option+Control+Shift held together).
///
/// Two parts work together:
/// 1. `hidutil` remaps Caps Lock to F18 so it no longer toggles alpha-lock.
/// 2. A `CGEventTap` watches for F18 and, while it is held, injects the four Hyper
///    modifier flags into every other key event. Those flags make the app's existing
///    Carbon `hyper+<key>` hotkeys fire.
@MainActor
final class HyperkeyController {
    enum StartResult {
        case started
        case needsAccessibility
        case failed(String)
    }

    /// Where the tap is inserted. `.cgSessionEventTap` injects the modifier flags before
    /// the Carbon hotkey matcher runs, so the existing `hyper+<key>` shortcuts fire.
    /// Switch to `.cghidEventTap` here if hotkeys ever fail to recognize the modifiers.
    private static let tapLocation: CGEventTapLocation = .cgSessionEventTap

    private let errorHandler: @MainActor (String) -> Void

    // Touched by the tap callback, which runs on the main run loop (see `start`), so
    // access is in fact serialized with the rest of the main actor.
    nonisolated(unsafe) private var hyperActive = false
    nonisolated(unsafe) private var eventTap: CFMachPort?

    private var runLoopSource: CFRunLoopSource?

    init(errorHandler: @escaping @MainActor (String) -> Void) {
        self.errorHandler = errorHandler
    }

    /// True only while the event tap is live. Drives the menu checkmark.
    var isActive: Bool { eventTap != nil }

    func start() -> StartResult {
        guard !isActive else { return .started }

        guard AXIsProcessTrusted() else {
            return .needsAccessibility
        }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: Self.tapLocation,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hyperkeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return .failed("Could not create the keyboard event tap.")
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source

        // Only neutralize Caps Lock once the tap is live, so we never strand the user
        // with a remapped-but-unhandled Caps Lock.
        guard HyperkeyRemap.apply() else {
            teardownTap()
            return .failed("Could not remap Caps Lock (hidutil failed).")
        }

        return .started
    }

    func stop() {
        HyperkeyRemap.clear()
        teardownTap()
    }

    /// Clears any stale Caps Lock remap left behind by a previous crash. Safe to call
    /// when nothing is mapped.
    func ensureInactive() {
        HyperkeyRemap.clear()
    }

    /// Shows the standard system prompt inviting the user to grant Accessibility access.
    func requestAccessibility() {
        requestAccessibilityAccess()
    }

    private func teardownTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
        }
        runLoopSource = nil
        eventTap = nil
        hyperActive = false
    }

    /// Handles each tapped event. `nonisolated` because the C callback invokes it from a
    /// context the compiler cannot prove is main-actor (it is — the source is on the main
    /// run loop). It only touches `nonisolated(unsafe)` state and pure helpers.
    nonisolated func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables a tap that is too slow or interrupted; re-enable it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return nil
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // F18 is the remapped Caps Lock. Use it purely as the Hyper trigger and never
        // let it reach any app. Key-repeat keyDowns simply re-assert the active state.
        if keyCode == Int64(kVK_F18) {
            switch type {
            case .keyDown: hyperActive = true
            case .keyUp: hyperActive = false
            default: break
            }
            return nil
        }

        if hyperActive {
            event.flags = HyperkeyFlags.decorate(event.flags)
        }

        return Unmanaged.passUnretained(event)
    }
}

/// Requests macOS Accessibility access. Calling this registers Toggler in the
/// Accessibility list (initially toggled off) and shows the standard system
/// prompt, so the user only has to flip the switch on — they never have to add
/// the app to the list by hand.
@MainActor
func requestAccessibilityAccess() {
    // "AXTrustedCheckOptionPrompt" is the documented value of
    // kAXTrustedCheckOptionPrompt; the literal avoids SDK import differences.
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
}

/// Non-capturing C callback bridged to the controller via the opaque `userInfo` pointer,
/// mirroring the `Unmanaged`-self pattern in `HotKeyManager`.
private let hyperkeyTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<HyperkeyController>.fromOpaque(userInfo).takeUnretainedValue()
    return controller.handle(type: type, event: event)
}
