import AppKit
import SwiftUI

/// A button that shows the currently chosen application and opens a searchable
/// popover of installed apps. The selected app's stable target value (bundle
/// id or path) is written to `appTarget`.
struct AppPickerField: View {
    @Binding var appTarget: String
    @ObservedObject var appsModel: InstalledAppsModel

    @State private var isPresented = false
    @State private var search = ""

    private var currentEntry: InstalledApp {
        appsModel.entry(forStoredRawValue: appTarget)
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 8) {
                icon(for: currentEntry)
                    .frame(width: 22, height: 22)
                Text(currentEntry.name.isEmpty ? "Application name, bundle ID, or path…" : currentEntry.name)
                    .foregroundStyle(currentEntry.name.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            popoverContent
        }
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppSearchField(text: $search, placeholder: "Search apps")
                .frame(maxWidth: .infinity)

            List(filteredApps) { app in
                Button {
                    appTarget = app.targetRawValue
                    isPresented = false
                    search = ""
                } label: {
                    HStack(spacing: 6) {
                        icon(for: app)
                            .frame(width: 18, height: 18)
                        Text(app.name).lineLimit(1)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .frame(width: 280, height: 320)
        }
        .padding(10)
        .onAppear {
            appsModel.load()
            // Start each open with a fresh, unfiltered list (the field is only
            // cleared on selection otherwise), so auto-focused typing filters
            // from scratch.
            search = ""
        }
    }

    private var filteredApps: [InstalledApp] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return appsModel.apps }
        return appsModel.apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    @ViewBuilder
    private func icon(for app: InstalledApp) -> some View {
        if app.path.isEmpty {
            Image(systemName: "app.dashed")
                .resizable()
                .foregroundStyle(.secondary)
        } else {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
        }
    }
}

/// A rounded text field that grabs keyboard focus as soon as it appears.
/// SwiftUI's `@FocusState` does not reliably take first responder inside an
/// `NSPopover` on macOS, so — like `ShortcutRecorderField` — this drives focus
/// through AppKit directly.
private struct AppSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeNSView(context: Context) -> AutoFocusTextField {
        let field = AutoFocusTextField()
        field.placeholderString = placeholder
        field.bezelStyle = .roundedBezel
        field.isBordered = true
        field.font = .systemFont(ofSize: 13)
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return field
    }

    func updateNSView(_ nsView: AutoFocusTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

/// `NSTextField` that makes itself first responder once it lands in a window.
final class AutoFocusTextField: NSTextField {
    private var hasFocused = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !hasFocused else { return }
        hasFocused = true
        // The popover's window isn't key yet at this point; defer one runloop
        // turn so AppKit accepts first responder and shows the caret.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }
}
