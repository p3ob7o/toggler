import Foundation

struct ShortcutBinding: Equatable {
    let shortcut: KeyboardShortcut
    let target: AppTarget
    let lineNumber: Int
}

struct ShortcutParseError: Equatable {
    let lineNumber: Int
    let message: String
}

struct ShortcutLoadResult {
    let bindings: [ShortcutBinding]
    let errors: [ShortcutParseError]
}

final class ShortcutStore {
    /// A single editable shortcut row, in the file's text form.
    ///
    /// `shortcutText` is a canonical token string accepted by `ShortcutParser`
    /// (the same form `KeyboardShortcut.displayValue` produces), e.g.
    /// `control+option+shift+command+t`. `appTarget` is the raw value used by
    /// `AppToggler` (a bundle identifier, app name, or `.app` path).
    struct Entry: Equatable, Sendable {
        let shortcutText: String
        let appTarget: String
    }

    let configURL: URL

    init(configURL: URL = ShortcutStore.defaultConfigURL()) {
        self.configURL = configURL
    }

    /// Writes the given entries to the config file, replacing its contents.
    ///
    /// The file is rewritten from scratch, so any hand-written comments are
    /// not preserved — a short generated header documents this. Each entry is
    /// serialized as `shortcut = app`, which round-trips back through `load()`.
    func save(_ entries: [Entry]) throws {
        let header = """
        # Toggler shortcuts
        #
        # This file is managed by the Toggler Settings window. Saving from
        # Settings rewrites the whole file, so comments added by hand are not
        # preserved.
        #
        # Format: shortcut = app

        """

        let body = entries
            .map { "\($0.shortcutText) = \(Self.quoteIfNeeded($0.appTarget))" }
            .joined(separator: "\n")

        let content = body.isEmpty ? header : header + body + "\n"

        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private static func quoteIfNeeded(_ value: String) -> String {
        value.contains(where: { $0 == " " || $0 == "\t" }) ? "\"\(value)\"" : value
    }

    func load() -> ShortcutLoadResult {
        ensureConfigFileExists()

        let content: String
        do {
            content = try String(contentsOf: configURL, encoding: .utf8)
        } catch {
            return ShortcutLoadResult(
                bindings: [],
                errors: [ShortcutParseError(lineNumber: 0, message: "Could not read shortcuts file: \(error.localizedDescription)")]
            )
        }

        return parse(content)
    }

    private func parse(_ content: String) -> ShortcutLoadResult {
        var bindings: [ShortcutBinding] = []
        var errors: [ShortcutParseError] = []

        for (index, rawLine) in content.components(separatedBy: .newlines).enumerated() {
            let lineNumber = index + 1
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !line.isEmpty, !line.hasPrefix("#") else {
                continue
            }

            guard let separatorRange = line.range(of: "=") else {
                errors.append(ShortcutParseError(lineNumber: lineNumber, message: "Missing '=' separator"))
                continue
            }

            let shortcutValue = line[..<separatorRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let targetValue = line[separatorRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)

            guard !targetValue.isEmpty else {
                errors.append(ShortcutParseError(lineNumber: lineNumber, message: "Missing app target"))
                continue
            }

            do {
                let shortcut = try ShortcutParser.parse(String(shortcutValue))
                bindings.append(
                    ShortcutBinding(
                        shortcut: shortcut,
                        target: AppTarget(rawValue: String(targetValue).unquoted()),
                        lineNumber: lineNumber
                    )
                )
            } catch {
                errors.append(
                    ShortcutParseError(
                        lineNumber: lineNumber,
                        message: error.localizedDescription
                    )
                )
            }
        }

        return ShortcutLoadResult(bindings: bindings, errors: errors)
    }

    private func ensureConfigFileExists() {
        guard !FileManager.default.fileExists(atPath: configURL.path(percentEncoded: false)) else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try sampleConfig.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Toggler: failed to create default shortcuts file: \(error.localizedDescription)")
        }
    }

    static func defaultConfigURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config")
            .appending(path: "toggler")
            .appending(path: "shortcuts.txt")
    }

    private let sampleConfig = """
    # Toggler shortcuts
    #
    # Format:
    # shortcut = app
    #
    # App targets can be bundle identifiers, app names, or .app paths.
    # Hyperkey means command+option+control+shift.
    #
    # Tip: enable "Caps Lock → Hyperkey" from the Toggler menu to use Caps Lock as hyper.
    #
    # Examples:
    # hyper+t = com.apple.Terminal
    # hyper+s = Safari
    # hyper+c = /Applications/Google Chrome.app

    """
}

private extension String {
    func unquoted() -> String {
        guard count >= 2 else {
            return self
        }

        if first == "\"", last == "\"" {
            return String(dropFirst().dropLast())
        }

        if first == "'", last == "'" {
            return String(dropFirst().dropLast())
        }

        return self
    }
}
