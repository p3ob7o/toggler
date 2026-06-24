import AppKit
import SwiftUI

/// The Settings form: app on/off, Hyperkey, the dynamic list of app↔shortcut
/// rows, and Cancel/Save.
struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @StateObject private var appsModel = InstalledAppsModel()

    /// Invoked to dismiss the window (Cancel, or a successful Save).
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Enable Toggler", isOn: $viewModel.isEnabled)
                .toggleStyle(.switch)
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Enable Hyperkey (Caps Lock)", isOn: $viewModel.hyperkeyEnabled)
                    .toggleStyle(.checkbox)

                if viewModel.hyperkeyEnabled, !AXIsProcessTrusted() {
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
                    .padding(.leading, 18)
                }
            }

            Divider()

            Text("Shortcuts")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach($viewModel.rows) { $row in
                        rowView(row: $row)
                    }
                }
            }

            if let message = viewModel.saveErrorMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    if viewModel.save() { onClose() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 480)
        .onChange(of: viewModel.rows) { _ in
            viewModel.rowsDidChange()
        }
        .onAppear { appsModel.load() }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @ViewBuilder
    private func rowView(row: Binding<ShortcutRow>) -> some View {
        let isTrailingEmptyRow = row.wrappedValue.id == viewModel.rows.last?.id

        HStack(spacing: 8) {
            AppPickerField(appTarget: row.appTarget, appsModel: appsModel)
                .frame(maxWidth: .infinity)

            ShortcutRecorderField(shortcutText: row.shortcutText)
                .frame(width: 180, height: 24)

            if let error = row.wrappedValue.shortcutError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help(error)
            }

            Button {
                viewModel.removeRow(row.wrappedValue.id)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .opacity(isTrailingEmptyRow ? 0 : 1)
            .disabled(isTrailingEmptyRow)
        }
    }
}
