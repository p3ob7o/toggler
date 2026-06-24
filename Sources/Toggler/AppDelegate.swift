import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let shortcutStore = ShortcutStore()
    private let appToggler = AppToggler()
    private lazy var hotKeyManager = HotKeyManager { [weak self] message in
        self?.presentNotification(title: "Toggler", body: message)
    }

    private var statusItem: NSStatusItem?
    private var bindings: [ShortcutBinding] = []
    private var parseErrors: [ShortcutParseError] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        loadShortcuts()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager.unregisterAll()
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
