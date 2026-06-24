import AppKit
import Carbon.HIToolbox

/// Converts a captured key event into a canonical shortcut token string.
///
/// The output is identical in form to `KeyboardShortcut.displayValue`
/// (e.g. `control+option+shift+command+t`) so it parses cleanly back through
/// `ShortcutParser` and serializes unchanged into the shortcuts file. This is
/// the reverse of `ShortcutParser.parse`.
enum ShortcutEventEncoder {
    /// Builds the token string for a recorded key press, or `nil` if the key
    /// code cannot be mapped to a token.
    ///
    /// Modifiers are emitted in the same fixed order as `displayValue`
    /// (control, option, shift, command). The key is resolved by code: special
    /// keys first (space, arrows, F-keys…), then the layout-correct unshifted
    /// character.
    static func tokenString(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        characterResolver: KeyboardShortcutCharacterResolving = CurrentKeyboardLayoutKeyResolver()
    ) -> String? {
        guard let keyToken = keyToken(forKeyCode: keyCode, characterResolver: characterResolver) else {
            return nil
        }

        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        var parts: [String] = []
        if flags.contains(.control) { parts.append("control") }
        if flags.contains(.option) { parts.append("option") }
        if flags.contains(.shift) { parts.append("shift") }
        if flags.contains(.command) { parts.append("command") }
        parts.append(keyToken)
        return parts.joined(separator: "+")
    }

    /// Whether at least one of the four shortcut modifiers is held. A valid
    /// shortcut requires one (the parser rejects modifier-less shortcuts).
    static func hasShortcutModifier(_ modifierFlags: NSEvent.ModifierFlags) -> Bool {
        !modifierFlags.intersection([.control, .option, .shift, .command]).isEmpty
    }

    private static func keyToken(
        forKeyCode keyCode: UInt16,
        characterResolver: KeyboardShortcutCharacterResolving
    ) -> String? {
        if let special = keyCodeToSpecialToken[Int(keyCode)] {
            return special
        }
        return characterResolver.character(forKeyCode: keyCode)
    }

    /// Layout-independent keys mapped to the canonical token that
    /// `ShortcutParser` accepts (e.g. `return` not `enter`, `escape` not `esc`,
    /// `delete` not `backspace`).
    static let keyCodeToSpecialToken: [Int: String] = [
        kVK_Space: "space",
        kVK_Tab: "tab",
        kVK_Return: "return",
        kVK_Escape: "escape",
        kVK_Delete: "delete",
        kVK_ForwardDelete: "forwarddelete",
        kVK_LeftArrow: "left",
        kVK_RightArrow: "right",
        kVK_UpArrow: "up",
        kVK_DownArrow: "down",
        kVK_Home: "home",
        kVK_End: "end",
        kVK_PageUp: "pageup",
        kVK_PageDown: "pagedown",
        kVK_F1: "f1",
        kVK_F2: "f2",
        kVK_F3: "f3",
        kVK_F4: "f4",
        kVK_F5: "f5",
        kVK_F6: "f6",
        kVK_F7: "f7",
        kVK_F8: "f8",
        kVK_F9: "f9",
        kVK_F10: "f10",
        kVK_F11: "f11",
        kVK_F12: "f12",
        kVK_F13: "f13",
        kVK_F14: "f14",
        kVK_F15: "f15",
        kVK_F16: "f16",
        kVK_F17: "f17",
        kVK_F18: "f18",
        kVK_F19: "f19",
        kVK_F20: "f20"
    ]
}
