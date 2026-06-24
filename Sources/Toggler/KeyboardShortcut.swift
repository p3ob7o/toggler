import Carbon.HIToolbox
import Foundation

struct KeyboardShortcut: Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let displayValue: String
}

enum ShortcutParser {
    static func parse(_ value: String) throws -> KeyboardShortcut {
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

        guard let keyCode = keyCodes[keyToken] else {
            throw ShortcutParseFailure("unknown key '\(keyToken)'")
        }

        return KeyboardShortcut(
            keyCode: UInt32(keyCode),
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

    private static let keyCodes: [String: Int] = [
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
        "grave": kVK_ANSI_Grave,
        "-": kVK_ANSI_Minus,
        "minus": kVK_ANSI_Minus,
        "=": kVK_ANSI_Equal,
        "equal": kVK_ANSI_Equal,
        "[": kVK_ANSI_LeftBracket,
        "leftbracket": kVK_ANSI_LeftBracket,
        "]": kVK_ANSI_RightBracket,
        "rightbracket": kVK_ANSI_RightBracket,
        "\\": kVK_ANSI_Backslash,
        "backslash": kVK_ANSI_Backslash,
        ";": kVK_ANSI_Semicolon,
        "semicolon": kVK_ANSI_Semicolon,
        "'": kVK_ANSI_Quote,
        "quote": kVK_ANSI_Quote,
        ",": kVK_ANSI_Comma,
        "comma": kVK_ANSI_Comma,
        ".": kVK_ANSI_Period,
        "period": kVK_ANSI_Period,
        "/": kVK_ANSI_Slash,
        "slash": kVK_ANSI_Slash,
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
