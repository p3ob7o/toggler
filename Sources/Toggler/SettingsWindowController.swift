import AppKit
import SwiftUI

/// Hosts the SwiftUI `SettingsView` in a window. Holds the window alive
/// (`isReleasedWhenClosed = false`) so it can be reopened, and reports closure
/// back to `AppDelegate` so it can drop its reference and restore the
/// accessory activation policy.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void

    init(viewModel: SettingsViewModel, onClose: @escaping () -> Void) {
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Toggler Settings"
        window.isReleasedWhenClosed = false

        super.init(window: window)

        let rootView = SettingsView(viewModel: viewModel) { [weak self] in
            self?.close()
        }
        window.contentViewController = NSHostingController(rootView: rootView)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
