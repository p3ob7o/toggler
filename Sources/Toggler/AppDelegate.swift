import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let shortcutStore = ShortcutStore()
    private let appToggler = AppToggler()
    private lazy var hotKeyManager = HotKeyManager { [weak self] message in
        self?.presentNotification(title: "Toggler", body: message)
    }
    private let hyperkeyPreference = HyperkeyPreference()
    private lazy var hyperkeyController = HyperkeyController { [weak self] message in
        self?.presentNotification(title: "Toggler", body: message)
    }

    private var statusItem: NSStatusItem?
    private var bindings: [ShortcutBinding] = []
    private var parseErrors: [ShortcutParseError] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        loadShortcuts()
        reconcileHyperkeyState()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager.unregisterAll()
        hyperkeyController.stop()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Toggler") {
            item.button?.image = image
            item.button?.imagePosition = .imageOnly
        } else {
            item.button?.title = "T"
        }
        statusItem = item
        rebuildMenu()
    }

    @objc private func reloadShortcuts() {
        loadShortcuts()
    }

    @objc private func openShortcutsFile() {
        NSWorkspace.shared.open(shortcutStore.configURL)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func toggleHyperkey() {
        if hyperkeyController.isActive {
            hyperkeyPreference.isEnabled = false
            hyperkeyController.stop()
            presentNotification(title: "Toggler", body: "Caps Lock → Hyperkey disabled. Caps Lock is back to normal.")
        } else {
            hyperkeyPreference.isEnabled = true
            switch hyperkeyController.start() {
            case .started:
                presentNotification(title: "Toggler", body: "Caps Lock → Hyperkey enabled. Hold Caps Lock as your Hyper modifier.")
            case .needsAccessibility:
                hyperkeyController.requestAccessibility()
                presentNotification(title: "Toggler", body: "Grant Accessibility access to Toggler, then enable Caps Lock → Hyperkey again.")
            case .failed(let message):
                hyperkeyPreference.isEnabled = false
                presentNotification(title: "Toggler", body: "Could not enable Hyperkey: \(message)")
            }
        }
        rebuildMenu()
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Brings the controller's actual state in line with the stored preference.
    private func reconcileHyperkeyState() {
        if hyperkeyPreference.isEnabled {
            // Starts only if Accessibility is already granted; otherwise stays inactive
            // (pending) without nagging the user with a prompt at launch.
            _ = hyperkeyController.start()
        } else {
            // Clear any stale remap left behind if a previous run crashed while active.
            hyperkeyController.ensureInactive()
        }
        rebuildMenu()
    }

    private func loadShortcuts() {
        let result = shortcutStore.load()
        bindings = result.bindings
        parseErrors = result.errors

        hotKeyManager.register(bindings) { [weak self] binding in
            self?.appToggler.toggle(binding.target)
        }

        rebuildMenu()

        if bindings.isEmpty, parseErrors.isEmpty {
            presentNotification(
                title: "Toggler",
                body: "No active shortcuts found. Edit \(shortcutStore.configURL.path(percentEncoded: false))."
            )
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let statusTitle: String
        if bindings.isEmpty {
            statusTitle = "No shortcuts loaded"
        } else if bindings.count == 1 {
            statusTitle = "1 shortcut loaded"
        } else {
            statusTitle = "\(bindings.count) shortcuts loaded"
        }

        let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if !parseErrors.isEmpty {
            let errorTitle = parseErrors.count == 1 ? "1 config issue" : "\(parseErrors.count) config issues"
            let errorItem = NSMenuItem(title: errorTitle, action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        }

        menu.addItem(.separator())

        let hyperItem = NSMenuItem(title: "Caps Lock → Hyperkey", action: #selector(toggleHyperkey), keyEquivalent: "")
        hyperItem.state = hyperkeyController.isActive ? .on : .off
        menu.addItem(hyperItem)

        if hyperkeyPreference.isEnabled, !hyperkeyController.isActive {
            let hint = NSMenuItem(title: "Needs Accessibility permission…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
            menu.addItem(hint)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Shortcuts File", action: #selector(openShortcutsFile), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Reload Shortcuts", action: #selector(reloadShortcuts), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Toggler", action: #selector(quit), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    private func presentNotification(title: String, body: String) {
        NSLog("\(title): \(body)")
    }
}
