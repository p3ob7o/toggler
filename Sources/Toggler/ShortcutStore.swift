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
    let configURL: URL

    init(configURL: URL = ShortcutStore.defaultConfigURL()) {
        self.configURL = configURL
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
