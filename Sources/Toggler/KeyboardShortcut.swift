import Carbon.HIToolbox
import Foundation

struct KeyboardShortcut: Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let displayValue: String
}

protocol KeyboardShortcutKeyResolving {
    func keyCode(for token: String) -> UInt32?
}

/// The reverse of `KeyboardShortcutKeyResolving`: maps a virtual key code back
/// to the layout-correct, unshifted character it produces. Used to turn a
/// captured key event into a token string the parser can re-parse.
protocol KeyboardShortcutCharacterResolving {
    func character(forKeyCode keyCode: UInt16) -> String?
}

enum ShortcutParser {
    static func parse(
        _ value: String,
        keyResolver: KeyboardShortcutKeyResolving = CurrentKeyboardLayoutKeyResolver()
    ) throws -> KeyboardShortcut {
        let tokens = value
            .split(separator: "+")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard let keyToken = tokens.last else {
            throw ShortcutParseFailure("missing shortcut")
        }

        var modifiers: UInt32 = 0
        for token in tokens.dropLast() {
            switch token {
            case "hyper", "hyperkey":
                modifiers |= UInt32(cmdKey | optionKey | controlKey | shiftKey)
            case "cmd", "command", "⌘":
                modifiers |= UInt32(cmdKey)
            case "opt", "option", "alt", "⌥":
                modifiers |= UInt32(optionKey)
            case "ctrl", "control", "ctl", "⌃":
                modifiers |= UInt32(controlKey)
            case "shift", "⇧":
                modifiers |= UInt32(shiftKey)
            default:
                throw ShortcutParseFailure("unknown modifier '\(token)'")
            }
        }

        guard modifiers != 0 else {
            throw ShortcutParseFailure("shortcuts must include at least one modifier")
        }

        guard let keyCode = keyResolver.keyCode(for: keyToken) else {
            throw ShortcutParseFailure("unknown key '\(keyToken)'")
        }

        return KeyboardShortcut(
            keyCode: keyCode,
            carbonModifiers: modifiers,
            displayValue: displayValue(modifiers: modifiers, key: keyToken)
        )
    }

    private static func displayValue(modifiers: UInt32, key: String) -> String {
        var parts: [String] = []

        if modifiers & UInt32(controlKey) != 0 {
            parts.append("control")
        }
        if modifiers & UInt32(optionKey) != 0 {
            parts.append("option")
        }
        if modifiers & UInt32(shiftKey) != 0 {
            parts.append("shift")
        }
        if modifiers & UInt32(cmdKey) != 0 {
            parts.append("command")
        }

        parts.append(key)
        return parts.joined(separator: "+")
    }
}

struct CurrentKeyboardLayoutKeyResolver: KeyboardShortcutKeyResolving, KeyboardShortcutCharacterResolving {
    private let layoutKeyCodes: [String: UInt32]?
    private let layoutCharacters: [UInt32: String]?

    init() {
        let layout = Self.buildLayout()
        layoutKeyCodes = layout?.keyCodes
        layoutCharacters = layout?.characters
    }

    func keyCode(for token: String) -> UInt32? {
        if let keyCode = Self.nonLayoutKeyCodes[token] {
            return UInt32(keyCode)
        }

        guard let character = Self.layoutCharacter(for: token) else {
            return nil
        }

        if let layoutKeyCodes {
            return layoutKeyCodes[character]
        }

        return Self.qwertyFallbackKeyCodes[character].map(UInt32.init)
    }

    func character(forKeyCode keyCode: UInt16) -> String? {
        if let layoutCharacters {
            return layoutCharacters[UInt32(keyCode)]
        }

        return Self.qwertyFallbackCharacters[UInt32(keyCode)]
    }

    private static func layoutCharacter(for token: String) -> String? {
        if let character = layoutCharacterAliases[token] {
            return character
        }

        return token.count == 1 ? token : nil
    }

    private static func buildLayout() -> (keyCodes: [String: UInt32], characters: [UInt32: String])? {
        guard let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawLayoutData = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }

        let layoutData = Unmanaged<CFData>.fromOpaque(rawLayoutData).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(layoutData) else {
            return nil
        }

        let keyboardLayout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        let keyboardType = UInt32(LMGetKbdType())
        let unshifted = UInt32(0)
        let modifierStates = [unshifted, UInt32(shiftKey >> 8)]
        var keyCodes: [String: UInt32] = [:]
        var characters: [UInt32: String] = [:]

        for keyCode in UInt16(0)..<UInt16(128) {
            for modifierState in modifierStates {
                guard let character = translatedCharacter(
                    keyCode: keyCode,
                    modifierState: modifierState,
                    keyboardLayout: keyboardLayout,
                    keyboardType: keyboardType
                ), character.count == 1 else {
                    continue
                }

                if keyCodes[character] == nil {
                    keyCodes[character] = UInt32(keyCode)
                }

                // The reverse map stores only the unshifted character so a
                // recorded key round-trips to its base token (e.g. the "=" key
                // yields "=", never "+", which would break the token split).
                if modifierState == unshifted, characters[UInt32(keyCode)] == nil {
                    characters[UInt32(keyCode)] = character
                }
            }
        }

        return (keyCodes, characters)
    }

    private static func translatedCharacter(
        keyCode: UInt16,
        modifierState: UInt32,
        keyboardLayout: UnsafePointer<UCKeyboardLayout>,
        keyboardType: UInt32
    ) -> String? {
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)

        let status = characters.withUnsafeMutableBufferPointer { buffer in
            UCKeyTranslate(
                keyboardLayout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                modifierState,
                keyboardType,
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                buffer.count,
                &length,
                buffer.baseAddress
            )
        }

        guard status == noErr, length > 0 else {
            return nil
        }

        return String(utf16CodeUnits: characters, count: length).lowercased()
    }

    private static let layoutCharacterAliases: [String: String] = [
        "grave": "`",
        "minus": "-",
        "equal": "=",
        "leftbracket": "[",
        "rightbracket": "]",
        "backslash": "\\",
        "semicolon": ";",
        "quote": "'",
        "comma": ",",
        "period": ".",
        "slash": "/"
    ]

    private static let nonLayoutKeyCodes: [String: Int] = [
        "space": kVK_Space,
        "tab": kVK_Tab,
        "return": kVK_Return,
        "enter": kVK_Return,
        "esc": kVK_Escape,
        "escape": kVK_Escape,
        "delete": kVK_Delete,
        "backspace": kVK_Delete,
        "forwarddelete": kVK_ForwardDelete,
        "left": kVK_LeftArrow,
        "right": kVK_RightArrow,
        "up": kVK_UpArrow,
        "down": kVK_DownArrow,
        "home": kVK_Home,
        "end": kVK_End,
        "pageup": kVK_PageUp,
        "pagedown": kVK_PageDown,
        "f1": kVK_F1,
        "f2": kVK_F2,
        "f3": kVK_F3,
        "f4": kVK_F4,
        "f5": kVK_F5,
        "f6": kVK_F6,
        "f7": kVK_F7,
        "f8": kVK_F8,
        "f9": kVK_F9,
        "f10": kVK_F10,
        "f11": kVK_F11,
        "f12": kVK_F12,
        "f13": kVK_F13,
        "f14": kVK_F14,
        "f15": kVK_F15,
        "f16": kVK_F16,
        "f17": kVK_F17,
        "f18": kVK_F18,
        "f19": kVK_F19,
        "f20": kVK_F20
    ]

    private static let qwertyFallbackKeyCodes: [String: Int] = [
        "a": kVK_ANSI_A,
        "b": kVK_ANSI_B,
        "c": kVK_ANSI_C,
        "d": kVK_ANSI_D,
        "e": kVK_ANSI_E,
        "f": kVK_ANSI_F,
        "g": kVK_ANSI_G,
        "h": kVK_ANSI_H,
        "i": kVK_ANSI_I,
        "j": kVK_ANSI_J,
        "k": kVK_ANSI_K,
        "l": kVK_ANSI_L,
        "m": kVK_ANSI_M,
        "n": kVK_ANSI_N,
        "o": kVK_ANSI_O,
        "p": kVK_ANSI_P,
        "q": kVK_ANSI_Q,
        "r": kVK_ANSI_R,
        "s": kVK_ANSI_S,
        "t": kVK_ANSI_T,
        "u": kVK_ANSI_U,
        "v": kVK_ANSI_V,
        "w": kVK_ANSI_W,
        "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y,
        "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0,
        "1": kVK_ANSI_1,
        "2": kVK_ANSI_2,
        "3": kVK_ANSI_3,
        "4": kVK_ANSI_4,
        "5": kVK_ANSI_5,
        "6": kVK_ANSI_6,
        "7": kVK_ANSI_7,
        "8": kVK_ANSI_8,
        "9": kVK_ANSI_9,
        "`": kVK_ANSI_Grave,
        "-": kVK_ANSI_Minus,
        "=": kVK_ANSI_Equal,
        "[": kVK_ANSI_LeftBracket,
        "]": kVK_ANSI_RightBracket,
        "\\": kVK_ANSI_Backslash,
        ";": kVK_ANSI_Semicolon,
        "'": kVK_ANSI_Quote,
        ",": kVK_ANSI_Comma,
        ".": kVK_ANSI_Period,
        "/": kVK_ANSI_Slash
    ]

    /// Reverse of `qwertyFallbackKeyCodes`, used when the current layout data
    /// is unavailable.
    private static let qwertyFallbackCharacters: [UInt32: String] = {
        var result: [UInt32: String] = [:]
        for (character, keyCode) in qwertyFallbackKeyCodes {
            result[UInt32(keyCode)] = character
        }
        return result
    }()
}

struct ShortcutParseFailure: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
