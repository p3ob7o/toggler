import Foundation

/// Persisted, app-level settings that are not part of the shortcuts file.
///
/// The shortcut bindings themselves live in `~/.config/toggler/shortcuts.txt`
/// (see `ShortcutStore`); these flags are simple booleans best kept in
/// `UserDefaults` so they survive relaunches independently of that file.
enum SettingsDefaults {
    private enum Key {
        static let isEnabled = "TogglerEnabled"
    }

    /// Whether Toggler's shortcuts are active. Defaults to `true` on a fresh
    /// install (when the key has never been written).
    ///
    /// Note: Hyperkey on/off is *not* stored here — it lives in
    /// `HyperkeyPreference` (`capsLockHyperkeyEnabled`) and is driven through
    /// `HyperkeyController`, so the Settings checkbox and the real feature
    /// share a single source of truth.
    static var isEnabled: Bool {
        get {
            let store = UserDefaults.standard
            return store.object(forKey: Key.isEnabled) == nil
                ? true
                : store.bool(forKey: Key.isEnabled)
        }
        set { UserDefaults.standard.set(newValue, forKey: Key.isEnabled) }
    }
}
