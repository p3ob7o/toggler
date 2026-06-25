//
//  ShortcutStore+Persistence.swift
//  Toggler
//
//  Adds the writer side to ShortcutStore — it currently only parses
//  (`load()`), so this is the small piece you need for Save.
//

import Foundation

extension ShortcutStore {

    /// Serialize completed rows back to `~/.config/toggler/shortcuts.txt`
    /// in the `shortcut = app` line format, preserving a short header.
    func save(_ rows: [ShortcutRow]) throws {
        var lines: [String] = [
            "# Toggler shortcuts",
            "#",
            "# Format:",
            "#   shortcut = app",
            ""
        ]

        for row in rows {
            guard let shortcut = row.shortcut else { continue }
            let target = row.appText.trimmingCharacters(in: .whitespaces)
            guard !target.isEmpty else { continue }
            lines.append("\(Self.fileString(for: shortcut)) = \(target)")
        }

        let text = lines.joined(separator: "\n") + "\n"
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: configURL, atomically: true, encoding: .utf8)
    }

    /// Turn a KeyboardShortcut into a file token, collapsing the full
    /// control+option+shift+command set to the `hyper` shorthand when present
    /// (so the file reads `hyper+t` like the README examples).
    static func fileString(for shortcut: KeyboardShortcut) -> String {
        // displayValue looks like "control+option+shift+command+t"
        let parts = shortcut.displayValue.split(separator: "+").map(String.init)
        guard let key = parts.last else { return shortcut.displayValue }
        let mods = Set(parts.dropLast())
        if mods.isSuperset(of: ["control", "option", "shift", "command"]) {
            return "hyper+\(key)"
        }
        return shortcut.displayValue
    }
}
