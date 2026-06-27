import AppKit
import SwiftUI

/// The Settings form: app on/off, Hyperkey, the dynamic list of app↔shortcut
/// rows, and Cancel/Save.
///
/// Built on a grouped `Form` so it adopts the System Settings look — rounded
/// cards, hairline dividers, accent-colored switches, and light/dark + accent
/// adaptation — without hardcoding any colors.
struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @StateObject private var appsModel = InstalledAppsModel()

    /// Mirrors `AXIsProcessTrusted()`. Kept in `@State` because TCC changes don't
    /// drive SwiftUI updates; refreshed when the app reactivates (e.g. after the
    /// user grants access in System Settings) so the permission warning clears.
    @State private var accessibilityTrusted = AXIsProcessTrusted()

    /// Invoked to dismiss the window (Cancel, or a successful Save).
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Pinned top: the app/Hyperkey switches stay visible no matter how
            // long the shortcuts list grows. Scroll is disabled and the form is
            // sized to its content so it never steals the scroll from the table.
            Form {
                Section {
                    Toggle(isOn: $viewModel.isEnabled) {
                        labeledToggle(
                            "Enable Toggler",
                            subtitle: "Bind global keyboard shortcuts to your apps."
                        )
                    }
                    .toggleStyle(.switch)

                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: $viewModel.hyperkeyEnabled) {
                            labeledToggle(
                                "Use Hyperkey",
                                subtitle: "Treat the caps lock key as ⌘⌥⌃⇧."
                            )
                        }
                        .toggleStyle(.switch)

                        if viewModel.hyperkeyEnabled, !accessibilityTrusted {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                                Text("Needs Accessibility permission to remap Caps Lock.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button("Open Accessibility Settings") { openAccessibilitySettings() }
                                    .buttonStyle(.link)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            // Shortcuts live in a fixed-size table that scrolls internally: the
            // header and the table frame stay put, and only the rows scroll, with
            // the scrollbar inside the table's own border.
            VStack(alignment: .leading, spacing: 6) {
                Text("Shortcuts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.leading, 4)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach($viewModel.rows) { $row in
                            rowView(row: $row)
                                .padding(.horizontal, 14)

                            if row.id != viewModel.rows.last?.id {
                                Divider()
                                    .padding(.leading, 14)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Match the grouped Form card: same elevated fill and corner
                // radius, with only a hairline edge instead of a hard border.
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
                )
            }
            // When the app is off, the design dims and disables the list.
            .opacity(viewModel.isEnabled ? 1 : 0.4)
            .disabled(!viewModel.isEnabled)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 18)

            Divider()

            HStack(spacing: 12) {
                if let message = viewModel.saveErrorMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button("Cancel", role: .cancel) { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    if viewModel.save() { onClose() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 560, height: 520)
        .onChange(of: viewModel.rows) { _ in
            viewModel.rowsDidChange()
        }
        .onAppear {
            appsModel.load()
            accessibilityTrusted = AXIsProcessTrusted()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Returning from System Settings after granting access reactivates the
            // app; re-check so the permission warning clears itself.
            accessibilityTrusted = AXIsProcessTrusted()
        }
    }

    /// Title above a secondary caption, the label used by both switches.
    private func labeledToggle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func openAccessibilitySettings() {
        // Register Toggler in the Accessibility list first (this is what adds the
        // app), so the user only has to flip its switch on rather than add it.
        requestAccessibilityAccess()

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @ViewBuilder
    private func rowView(row: Binding<ShortcutRow>) -> some View {
        let isTrailingEmptyRow = row.wrappedValue.id == viewModel.rows.last?.id

        HStack(spacing: 12) {
            AppPickerField(appTarget: row.appTarget, appsModel: appsModel)
                .frame(maxWidth: .infinity, alignment: .leading)

            ShortcutRecorderField(shortcutText: row.shortcutText)
                .frame(width: 150, height: 26)
                // Overlaid (not laid out) so an invalid row doesn't shift the
                // recorder column out of alignment with the other rows.
                .overlay(alignment: .trailing) {
                    if let error = row.wrappedValue.shortcutError {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .help(error)
                            .padding(.trailing, 6)
                    }
                }

            // Fixed-width trailing slot keeps the recorder column aligned across
            // every row: the trash shows on filled pairs, the trailing empty pair
            // has none.
            Group {
                if isTrailingEmptyRow {
                    Color.clear
                } else {
                    Button {
                        viewModel.removeRow(row.wrappedValue.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove this shortcut")
                }
            }
            .frame(width: 22)
        }
        .padding(.vertical, 6)
    }
}
