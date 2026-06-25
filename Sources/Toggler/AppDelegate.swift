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
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        loadShortcuts()
        reconcileHyperkeyState()
        observeShortcutRecording()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager.unregisterAll()
        hyperkeyController.stop()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = menuBarIcon() {
            item.button?.image = image
            item.button?.imagePosition = .imageOnly
        } else if let image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Toggler") {
            item.button?.image = image
            item.button?.imagePosition = .imageOnly
        } else {
            item.button?.title = "T"
        }
        statusItem = item
        rebuildMenu()
    }

    private func menuBarIcon() -> NSImage? {
        let image: NSImage
        if
            let iconURL = Bundle.main.url(forResource: "MenuBarIconTemplate", withExtension: "png"),
            let bundledImage = NSImage(contentsOf: iconURL)
        {
            image = bundledImage
        } else {
            image = drawnMenuBarIcon()
        }

        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        image.accessibilityDescription = "Toggler"
        return image
    }

    private func drawnMenuBarIcon() -> NSImage {
        NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()

            let path = NSBezierPath()
            path.windingRule = .evenOdd
            path.appendRoundedRect(
                NSRect(x: 2, y: 2, width: 14, height: 14),
                xRadius: 2.5,
                yRadius: 2.5
            )
            path.appendRect(NSRect(x: 5, y: 11, width: 8, height: 2))
            path.appendRect(NSRect(x: 8, y: 5, width: 2, height: 8))
            path.fill()

            return true
        }
    }

    @objc private func reloadShortcuts() {
        loadShortcuts()
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            let viewModel = SettingsViewModel(
                store: shortcutStore,
                hyperkeyEnabled: hyperkeyPreference.isEnabled
            ) { [weak self] outcome in
                self?.applySettings(outcome)
            }
            settingsWindowController = SettingsWindowController(viewModel: viewModel) { [weak self] in
                self?.settingsWindowDidClose()
            }
        }

        // An accessory app can't reliably become the foreground/key app, which
        // the shortcut recorder needs. Become a regular app while Settings is
        // open, then revert on close.
        NSApp.setActivationPolicy(.regular)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.center()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    private func settingsWindowDidClose() {
        settingsWindowController = nil
        NSApp.setActivationPolicy(.accessory)
    }

    private func applySettings(_ outcome: SettingsOutcome) {
        // The view model already persisted the app-enabled flag; reload re-reads
        // and re-registers shortcuts, honoring it.
        loadShortcuts()

        // Drive the real Hyperkey feature only when the desired state differs
        // from what's stored, so re-saving an unchanged setting doesn't re-prompt
        // for Accessibility.
        if outcome.hyperkeyEnabled != hyperkeyPreference.isEnabled {
            setHyperkeyEnabled(outcome.hyperkeyEnabled)
        }
    }

    @objc private func openShortcutsFile() {
        NSWorkspace.shared.open(shortcutStore.configURL)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    /// Enables or disables the Caps Lock → Hyperkey feature, persisting the
    /// preference and starting/stopping the controller. On enable, handles the
    /// missing-Accessibility and failure cases.
    private func setHyperkeyEnabled(_ enabled: Bool) {
        if enabled {
            hyperkeyPreference.isEnabled = true
            switch hyperkeyController.start() {
            case .started:
                presentNotification(title: "Toggler", body: "Caps Lock → Hyperkey enabled. Hold Caps Lock as your Hyper modifier.")
            case .needsAccessibility:
                hyperkeyController.requestAccessibility()
                presentNotification(title: "Toggler", body: "Grant Accessibility access to Toggler to finish enabling Caps Lock → Hyperkey.")
            case .failed(let message):
                hyperkeyPreference.isEnabled = false
                presentNotification(title: "Toggler", body: "Could not enable Hyperkey: \(message)")
            }
        } else {
            hyperkeyPreference.isEnabled = false
            hyperkeyController.stop()
            presentNotification(title: "Toggler", body: "Caps Lock → Hyperkey disabled. Caps Lock is back to normal.")
        }
        rebuildMenu()
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

        resumeHotKeys()

        rebuildMenu()

        if bindings.isEmpty, parseErrors.isEmpty {
            presentNotification(
                title: "Toggler",
                body: "No active shortcuts found. Edit \(shortcutStore.configURL.path(percentEncoded: false))."
            )
        }
    }

    /// Registers the current in-memory bindings (honoring the enabled flag). Also
    /// used to restore shortcuts after they are suspended during recording.
    private func resumeHotKeys() {
        let activeBindings = SettingsDefaults.isEnabled ? bindings : []
        hotKeyManager.register(activeBindings) { [weak self] binding in
            self?.appToggler.toggle(binding.target)
        }
    }

    /// While a shortcut recorder in Settings is capturing keys, suspend global
    /// hotkeys so an existing shortcut doesn't fire as the user records a new one.
    private func observeShortcutRecording() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(suspendHotKeysForRecording),
            name: .shortcutRecordingDidBegin,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(resumeHotKeysAfterRecording),
            name: .shortcutRecordingDidEnd,
            object: nil
        )
    }

    @objc private func suspendHotKeysForRecording() {
        hotKeyManager.unregisterAll()
    }

    @objc private func resumeHotKeysAfterRecording() {
        resumeHotKeys()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let statusTitle: String
        if !SettingsDefaults.isEnabled {
            statusTitle = "Toggler is disabled"
        } else if bindings.isEmpty {
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
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        menu.addItem(settingsItem)
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
