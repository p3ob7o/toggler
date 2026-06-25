import Carbon.HIToolbox
import SwiftUI

/// A click-to-record keyboard-shortcut field. Focus it and press a real key
/// combination; it captures the chord as a canonical token string (the same
/// form the parser/`displayValue` use) bound to `shortcutText`.
struct ShortcutRecorderField: NSViewRepresentable {
    @Binding var shortcutText: String

    func makeNSView(context: Context) -> RecorderNSView {
        let view = RecorderNSView()
        view.onCommit = { token in shortcutText = token }
        view.onClear = { shortcutText = "" }
        return view
    }

    func updateNSView(_ nsView: RecorderNSView, context: Context) {
        nsView.displayString = ShortcutSymbols.display(for: shortcutText)
        nsView.needsDisplay = true
    }
}

/// First-responder NSView that captures a modifier+key chord while focused.
final class RecorderNSView: NSView {
    var displayString = ""
    var onCommit: ((String) -> Void)?
    var onClear: (() -> Void)?

    private var isRecording = false
    private var liveModifiers: NSEvent.ModifierFlags = []
    private var clickOutsideMonitor: Any?

    // Only accept first responder after an explicit click. This keeps the window
    // from auto-focusing the first recorder (and starting to record) when Settings
    // opens; AppKit otherwise picks the first acceptsFirstResponder view as the
    // initial first responder.
    private var wantsFirstResponder = false

    override var acceptsFirstResponder: Bool { wantsFirstResponder }

    override func mouseDown(with event: NSEvent) {
        // Set before makeFirstResponder: AppKit checks acceptsFirstResponder at the
        // moment of the call, so it must already be true.
        wantsFirstResponder = true
        window?.makeFirstResponder(self)
    }

    // Safety net: drop the event monitor if the field leaves its window while
    // still recording (resignFirstResponder covers the ordinary focus-change path).
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            stopClickOutsideMonitor()
        }
    }

    override func becomeFirstResponder() -> Bool {
        isRecording = true
        liveModifiers = []
        needsDisplay = true
        startClickOutsideMonitor()
        // Tell AppDelegate to suspend global hotkeys so an existing shortcut
        // doesn't fire while the user is recording a new one.
        NotificationCenter.default.post(name: .shortcutRecordingDidBegin, object: nil)
        return true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        wantsFirstResponder = false
        liveModifiers = []
        needsDisplay = true
        stopClickOutsideMonitor()
        NotificationCenter.default.post(name: .shortcutRecordingDidEnd, object: nil)
        return true
    }

    /// While recording, a click anywhere outside this field ends recording, so
    /// focus can leave the recorders entirely instead of only hopping between them.
    private func startClickOutsideMonitor() {
        stopClickOutsideMonitor()
        clickOutsideMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, let window = self.window, event.window === window else {
                return event
            }
            let point = self.convert(event.locationInWindow, from: nil)
            if !self.bounds.contains(point) {
                window.makeFirstResponder(nil)
            }
            return event
        }
    }

    private func stopClickOutsideMonitor() {
        if let clickOutsideMonitor {
            NSEvent.removeMonitor(clickOutsideMonitor)
            self.clickOutsideMonitor = nil
        }
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }
        liveModifiers = event.modifierFlags
        needsDisplay = true
    }

    // Command-based combos arrive here (they would otherwise hit menu items);
    // swallow them while recording so e.g. ⌘W records instead of closing.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        handleKeyDown(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        handleKeyDown(event)
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        let modifiers = event.modifierFlags
        let hasModifier = ShortcutEventEncoder.hasShortcutModifier(modifiers)

        // Escape (no modifiers) cancels; Delete (no modifiers) clears.
        if !hasModifier {
            switch Int(event.keyCode) {
            case kVK_Escape:
                endRecording()
                return
            case kVK_Delete, kVK_ForwardDelete:
                onClear?()
                endRecording()
                return
            default:
                NSSound.beep()
                return
            }
        }

        guard let token = ShortcutEventEncoder.tokenString(
            keyCode: event.keyCode,
            modifierFlags: modifiers
        ) else {
            NSSound.beep()
            return
        }

        onCommit?(token)
        endRecording()
    }

    private func endRecording() {
        window?.makeFirstResponder(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()

        let text: String
        let color: NSColor
        if isRecording {
            let preview = ShortcutSymbols.modifierSymbols(for: liveModifiers)
            text = preview.isEmpty ? "Type shortcut…" : preview + "…"
            color = .secondaryLabelColor
        } else if displayString.isEmpty {
            text = "Record Shortcut"
            color = .secondaryLabelColor
        } else {
            text = displayString
            color = .labelColor
        }

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: color,
            .paragraphStyle: style
        ])
        let size = attributed.size()
        let textRect = NSRect(
            x: 4,
            y: (bounds.height - size.height) / 2,
            width: bounds.width - 8,
            height: size.height
        )
        attributed.draw(in: textRect)
    }
}

/// Formats canonical shortcut tokens as human-readable key symbols.
enum ShortcutSymbols {
    static func display(for token: String) -> String {
        guard !token.isEmpty else { return "" }
        let parts = token.split(separator: "+").map(String.init)
        guard let key = parts.last else { return "" }

        var result = ""
        for modifier in parts.dropLast() {
            result += symbol(forModifier: modifier)
        }
        // A space sets the key apart from the modifier glyphs, e.g. "⌃⌥⇧⌘ T".
        if !result.isEmpty {
            result += " "
        }
        result += symbol(forKey: key)
        return result
    }

    static func modifierSymbols(for flags: NSEvent.ModifierFlags) -> String {
        var result = ""
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        return result
    }

    private static func symbol(forModifier modifier: String) -> String {
        switch modifier {
        case "control": return "⌃"
        case "option": return "⌥"
        case "shift": return "⇧"
        case "command": return "⌘"
        case "hyper", "hyperkey": return "⌃⌥⇧⌘"
        default: return ""
        }
    }

    private static func symbol(forKey key: String) -> String {
        switch key {
        case "space": return "Space"
        case "tab": return "⇥"
        case "return", "enter": return "↩"
        case "escape", "esc": return "⎋"
        case "delete", "backspace": return "⌫"
        case "forwarddelete": return "⌦"
        case "left": return "←"
        case "right": return "→"
        case "up": return "↑"
        case "down": return "↓"
        case "home": return "↖"
        case "end": return "↘"
        case "pageup": return "⇞"
        case "pagedown": return "⇟"
        default: return key.uppercased()
        }
    }
}

extension Notification.Name {
    /// Posted while a shortcut recorder is actively capturing keys. `AppDelegate`
    /// suspends global hotkeys between begin and end so an existing shortcut does
    /// not fire while the user is recording a new one.
    static let shortcutRecordingDidBegin = Notification.Name("TogglerShortcutRecordingDidBegin")
    static let shortcutRecordingDidEnd = Notification.Name("TogglerShortcutRecordingDidEnd")
}
