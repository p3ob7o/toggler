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
    private struct TargetIdentity {
        let target: AppTarget
        let expandedRawValue: String
        let applicationURL: URL?
        let canonicalApplicationPath: String?
        let bundleIdentifier: String?
        let names: Set<String>
    }

    private let workspace: NSWorkspace
    private let fileManager: FileManager

    init(workspace: NSWorkspace = .shared, fileManager: FileManager = .default) {
        self.workspace = workspace
        self.fileManager = fileManager
    }

    func toggle(_ target: AppTarget) {
        let identity = identity(for: target)

        if let frontmostApplication = workspace.frontmostApplication,
           matches(frontmostApplication, identity: identity) {
            logDecision("hide frontmost", app: frontmostApplication, identity: identity)
            hide(frontmostApplication, identity: identity)
            return
        }

        if let runningApp = runningApplication(matching: identity) {
            if runningApp.isActive || workspace.frontmostApplication?.processIdentifier == runningApp.processIdentifier {
                logDecision("hide active running app", app: runningApp, identity: identity)
                hide(runningApp, identity: identity)
                return
            }

            logDecision("activate", app: runningApp, identity: identity)
            activate(runningApp)
            return
        }

        logDecision("launch", app: nil, identity: identity)
        launch(identity)
    }

    private func hide(_ app: NSRunningApplication, identity: TargetIdentity) {
        let didHide = app.hide()
        if !didHide {
            hideWithFallbacks(app, identity: identity)
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            if self.isStillFrontmost(app, identity: identity) {
                self.hideWithFallbacks(app, identity: identity)
            }
        }
    }

    private func hideWithFallbacks(_ app: NSRunningApplication, identity: TargetIdentity) {
        if hideWithCommandH(app, identity: identity) {
            return
        }

        if hideWithAppleScript(app) {
            return
        }

        if hideWithAccessibility(app) {
            return
        }

        NSLog("Toggler: failed to hide '\(app.localizedName ?? app.bundleIdentifier ?? "unknown app")'")
    }

    private func hideWithCommandH(_ app: NSRunningApplication, identity: TargetIdentity) -> Bool {
        guard isStillFrontmost(app, identity: identity),
              let hKeyCode = CurrentKeyboardLayoutKeyResolver().keyCode(for: "h") else {
            return false
        }

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(hKeyCode), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(hKeyCode), keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        return true
    }

    private func hideWithAppleScript(_ app: NSRunningApplication) -> Bool {
        guard let bundleIdentifier = app.bundleIdentifier else {
            return false
        }

        let escapedBundleIdentifier = bundleIdentifier
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = NSAppleScript(source: "tell application id \"\(escapedBundleIdentifier)\" to hide")
        var error: NSDictionary?
        script?.executeAndReturnError(&error)

        if let error {
            NSLog("Toggler: AppleScript hide failed for '\(bundleIdentifier)': \(error)")
            return false
        }

        return true
    }

    private func hideWithAccessibility(_ app: NSRunningApplication) -> Bool {
        let applicationElement = AXUIElementCreateApplication(app.processIdentifier)
        let status = AXUIElementSetAttributeValue(
            applicationElement,
            kAXHiddenAttribute as CFString,
            kCFBooleanTrue
        )

        guard status == .success else {
            NSLog("Toggler: Accessibility hide failed for pid \(app.processIdentifier): \(status.rawValue)")
            return false
        }

        return true
    }

    private func isStillFrontmost(_ app: NSRunningApplication, identity: TargetIdentity) -> Bool {
        guard let frontmostApplication = workspace.frontmostApplication else {
            return app.isActive && !app.isHidden
        }

        return frontmostApplication.processIdentifier == app.processIdentifier
            || matches(frontmostApplication, identity: identity)
            || (app.isActive && !app.isHidden)
    }

    private func activate(_ app: NSRunningApplication) {
        app.unhide()
        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    private func launch(_ identity: TargetIdentity) {
        guard let url = identity.applicationURL else {
            NSSound.beep()
            NSLog("Toggler: could not find application for target '\(identity.target.rawValue)'")
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false

        workspace.openApplication(at: url, configuration: configuration) { runningApp, error in
            if let error {
                NSSound.beep()
                NSLog("Toggler: failed to launch '\(identity.target.rawValue)': \(error.localizedDescription)")
                return
            }

            runningApp?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }
    }

    private func runningApplication(matching identity: TargetIdentity) -> NSRunningApplication? {
        workspace.runningApplications.first { app in
            matches(app, identity: identity)
        }
    }

    private func matches(_ app: NSRunningApplication, identity: TargetIdentity) -> Bool {
        if let bundleIdentifier = identity.bundleIdentifier,
           app.bundleIdentifier == bundleIdentifier {
            return true
        }

        if app.bundleIdentifier == identity.target.rawValue {
            return true
        }

        if let canonicalApplicationPath = identity.canonicalApplicationPath,
           let appPath = app.bundleURL.map(canonicalPath(for:)),
           appPath.caseInsensitiveCompare(canonicalApplicationPath) == .orderedSame {
            return true
        }

        if let bundleURL = app.bundleURL,
           bundleURL.path(percentEncoded: false).caseInsensitiveCompare(identity.expandedRawValue) == .orderedSame {
            return true
        }

        if let localizedName = app.localizedName?.lowercased(),
           identity.names.contains(localizedName) {
            return true
        }

        if let bundleName = app.bundleURL?.deletingPathExtension().lastPathComponent.lowercased(),
           identity.names.contains(bundleName) {
            return true
        }

        return false
    }

    private func identity(for target: AppTarget) -> TargetIdentity {
        let rawValue = target.rawValue
        let expanded = expandedPath(rawValue)
        let applicationURL = applicationURL(for: target, expandedRawValue: expanded)
        let bundle = applicationURL.flatMap(Bundle.init(url:))
        var names = Set<String>()
        names.insert(target.normalizedName)

        if let applicationURL {
            names.insert(applicationURL.deletingPathExtension().lastPathComponent.lowercased())
        }

        if let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String {
            names.insert(bundleName.lowercased())
        }

        if let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
            names.insert(displayName.lowercased())
        }

        return TargetIdentity(
            target: target,
            expandedRawValue: expanded,
            applicationURL: applicationURL,
            canonicalApplicationPath: applicationURL.map(canonicalPath(for:)),
            bundleIdentifier: bundle?.bundleIdentifier,
            names: names
        )
    }

    private func applicationURL(for target: AppTarget, expandedRawValue: String) -> URL? {
        let rawValue = target.rawValue

        if expandedRawValue.hasSuffix(".app") || expandedRawValue.contains("/") {
            let url = URL(fileURLWithPath: expandedRawValue)
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

    private func canonicalPath(for url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
    }

    private func logDecision(_ decision: String, app: NSRunningApplication?, identity: TargetIdentity) {
        let appDescription: String
        if let app {
            appDescription = "\(app.localizedName ?? "unknown") pid=\(app.processIdentifier) bundle=\(app.bundleIdentifier ?? "nil") path=\(app.bundleURL?.path(percentEncoded: false) ?? "nil") active=\(app.isActive) hidden=\(app.isHidden)"
        } else {
            appDescription = "nil"
        }

        let frontmost = workspace.frontmostApplication
        let frontmostDescription = "\(frontmost?.localizedName ?? "nil") pid=\(frontmost?.processIdentifier.description ?? "nil") bundle=\(frontmost?.bundleIdentifier ?? "nil") path=\(frontmost?.bundleURL?.path(percentEncoded: false) ?? "nil")"
        NSLog("Toggler: decision=\(decision) target=\(identity.target.rawValue) resolvedBundle=\(identity.bundleIdentifier ?? "nil") app=\(appDescription) frontmost=\(frontmostDescription)")
    }
}

private extension String {
    func deletingAppSuffix() -> String {
        hasSuffix(".app") ? String(dropLast(4)) : self
    }
}
