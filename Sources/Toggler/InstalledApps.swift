import Foundation

/// Metadata for one installed application, used to populate the app picker.
///
/// Deliberately carries no `NSImage` so it stays `Sendable` and can be produced
/// off the main actor; icons are loaded lazily by the view from `path`.
struct InstalledApp: Identifiable, Sendable, Hashable {
    /// Stable identity: bundle identifier when known, otherwise the path.
    var id: String { bundleID ?? path }
    let name: String
    let bundleID: String?
    let path: String

    /// The value written to the shortcuts file when this app is chosen. The full
    /// `.app` path is used (not the bundle identifier) so the file records the
    /// exact app the user picked: bundle identifiers can be opaque or shared
    /// (e.g. Notion Calendar reports `com.cron.electron`), whereas the path is
    /// unambiguous and human-readable. `AppToggler` resolves `.app` paths
    /// directly.
    var targetRawValue: String { path }
}

/// Scans well-known application directories for `.app` bundles.
enum AppScanner {
    /// The same roots `AppToggler` searches, so the picker only offers apps the
    /// toggler can resolve.
    static func searchRoots(fileManager: FileManager = .default) -> [URL] {
        let home = fileManager.homeDirectoryForCurrentUser
        return [
            home.appending(path: "Applications"),
            URL(filePath: "/Applications"),
            URL(filePath: "/Applications/Utilities"),
            URL(filePath: "/System/Applications"),
            URL(filePath: "/System/Applications/Utilities")
        ]
    }

    /// Returns the installed apps, de-duplicated and sorted by display name.
    static func scan(fileManager: FileManager = .default) -> [InstalledApp] {
        scan(roots: searchRoots(fileManager: fileManager), fileManager: fileManager)
    }

    /// Scans the given roots. Separated for testability.
    static func scan(roots: [URL], fileManager: FileManager = .default) -> [InstalledApp] {
        var byKey: [String: InstalledApp] = [:]

        for root in roots {
            let contents = (try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []

            for url in contents where url.pathExtension == "app" {
                let app = makeApp(at: url)
                let key = app.bundleID ?? canonicalPath(for: url)
                if byKey[key] == nil {
                    byKey[key] = app
                }
            }
        }

        return byKey.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private static func makeApp(at url: URL) -> InstalledApp {
        let bundle = Bundle(url: url)
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent

        return InstalledApp(
            name: name,
            bundleID: bundle?.bundleIdentifier,
            path: url.path(percentEncoded: false)
        )
    }

    private static func canonicalPath(for url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
    }
}

/// Owns the (cached) list of installed apps for the picker and maps stored
/// shortcut targets back to a displayable entry.
@MainActor
final class InstalledAppsModel: ObservableObject {
    @Published private(set) var apps: [InstalledApp] = []

    /// Scans off the main actor and publishes the result on the main actor.
    func load() {
        Task { [weak self] in
            let scanned = await Task.detached(priority: .userInitiated) {
                AppScanner.scan()
            }.value
            self?.apps = scanned
        }
    }

    /// Resolves a stored target value (bundle id, path, or name) to a display
    /// entry. Never loses the user's value: an unrecognized target becomes an
    /// entry showing the raw string.
    func entry(forStoredRawValue rawValue: String) -> InstalledApp {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return InstalledApp(name: "", bundleID: nil, path: "")
        }

        if let match = apps.first(where: { $0.bundleID == trimmed }) {
            return match
        }

        let canonical = URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path(percentEncoded: false)
        if let match = apps.first(where: { $0.path == canonical || $0.path == trimmed }) {
            return match
        }

        let normalized = normalizedName(trimmed)
        if let match = apps.first(where: { normalizedName($0.name) == normalized }) {
            return match
        }

        // Unrecognized: surface the raw value so it is never silently dropped.
        return InstalledApp(name: trimmed, bundleID: nil, path: "")
    }

    private func normalizedName(_ value: String) -> String {
        let base = value.hasSuffix(".app") ? String(value.dropLast(4)) : value
        return base.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
