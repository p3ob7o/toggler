import AppKit

struct AppTarget: Equatable {
    let rawValue: String

    var normalizedName: String {
        rawValue
            .deletingAppSuffix()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

@MainActor
final class AppToggler {
    private let workspace: NSWorkspace
    private let fileManager: FileManager

    init(workspace: NSWorkspace = .shared, fileManager: FileManager = .default) {
        self.workspace = workspace
        self.fileManager = fileManager
    }

    func toggle(_ target: AppTarget) {
        if let runningApp = runningApplication(matching: target) {
            toggle(runningApp)
            return
        }

        launch(target)
    }

    private func toggle(_ app: NSRunningApplication) {
        if workspace.frontmostApplication?.processIdentifier == app.processIdentifier {
            app.hide()
            return
        }

        app.unhide()
        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    private func launch(_ target: AppTarget) {
        guard let url = applicationURL(for: target) else {
            NSSound.beep()
            NSLog("Toggler: could not find application for target '\(target.rawValue)'")
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false

        workspace.openApplication(at: url, configuration: configuration) { runningApp, error in
            if let error {
                NSSound.beep()
                NSLog("Toggler: failed to launch '\(target.rawValue)': \(error.localizedDescription)")
                return
            }

            runningApp?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }
    }

    private func runningApplication(matching target: AppTarget) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { app in
            if app.bundleIdentifier == target.rawValue {
                return true
            }

            if let bundleURL = app.bundleURL,
               bundleURL.path(percentEncoded: false).caseInsensitiveCompare(expandedPath(target.rawValue)) == .orderedSame {
                return true
            }

            if app.localizedName?.lowercased() == target.normalizedName {
                return true
            }

            if app.bundleURL?.deletingPathExtension().lastPathComponent.lowercased() == target.normalizedName {
                return true
            }

            return false
        }
    }

    private func applicationURL(for target: AppTarget) -> URL? {
        let rawValue = target.rawValue
        let expanded = expandedPath(rawValue)

        if expanded.hasSuffix(".app") || expanded.contains("/") {
            let url = URL(fileURLWithPath: expanded)
            if isApplication(at: url) {
                return url
            }
        }

        if let bundleURL = workspace.urlForApplication(withBundleIdentifier: rawValue) {
            return bundleURL
        }

        return commonApplicationLocations(for: rawValue).first(where: isApplication(at:))
    }

    private func commonApplicationLocations(for appName: String) -> [URL] {
        let name = appName.hasSuffix(".app") ? appName : "\(appName).app"
        let home = fileManager.homeDirectoryForCurrentUser

        return [
            home.appending(path: "Applications").appending(path: name),
            URL(filePath: "/Applications").appending(path: name),
            URL(filePath: "/Applications/Utilities").appending(path: name),
            URL(filePath: "/System/Applications").appending(path: name),
            URL(filePath: "/System/Applications/Utilities").appending(path: name)
        ]
    }

    private func isApplication(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) else {
            return false
        }

        return isDirectory.boolValue && url.pathExtension == "app"
    }

    private func expandedPath(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }
}

private extension String {
    func deletingAppSuffix() -> String {
        hasSuffix(".app") ? String(dropLast(4)) : self
    }
}
