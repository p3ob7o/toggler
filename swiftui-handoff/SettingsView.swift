//
//  SettingsView.swift
//  Toggler — Settings screen (SwiftUI scaffold)
//
//  Generated from the "Toggler Settings" design mockup. Targets macOS 13+
//  (Ventura) for `.formStyle(.grouped)`, `.toggleStyle(.switch)`, and
//  `Button(role: .destructive)`.
//
//  ▸ IMPORTANT: do NOT port the mockup's hex colors / paddings. A native
//    grouped Form reproduces the System Settings look for free — rounded
//    cards, hairline dividers, the accent-colored switches, and light/dark
//    + accent-color adaptation. The mockup only *emulated* this.
//
//  ▸ Three areas are intentionally stubbed — search for "CUSTOM":
//      1. ShortcutRecorder     — capture real keystrokes
//      2. AppTargetField       — autocomplete to installed apps + their icons
//      3. ShortcutStore.save() — serialize rows back to shortcuts.txt
//                                (see ShortcutStore+Persistence.swift)
//
//  ▸ Wire-up assumes the existing model (Sources/Toggler/…):
//      KeyboardShortcut(keyCode:carbonModifiers:displayValue:)
//      ShortcutBinding(shortcut:target:lineNumber:)
//      AppTarget(rawValue:)        // assumes `.rawValue` is the original string
//      ShortcutStore().load() -> ShortcutLoadResult(bindings:errors:)
//      ShortcutParser.parse(_:) throws -> KeyboardShortcut
//

import SwiftUI
import AppKit
import Carbon.HIToolbox

// MARK: - Row view-model

/// One editable application⇄shortcut pair. Fields are loose (optional / String)
/// because a row is partially filled while the user is mid-edit.
struct ShortcutRow: Identifiable, Equatable {
    let id = UUID()
    var appText: String = ""           // app name, bundle id, or .app path
    var shortcut: KeyboardShortcut?    // nil until recorded

    var isEmpty: Bool {
        appText.trimmingCharacters(in: .whitespaces).isEmpty && shortcut == nil
    }
    var isComplete: Bool {
        !appText.trimmingCharacters(in: .whitespaces).isEmpty && shortcut != nil
    }
}

// MARK: - View model

@MainActor
final class SettingsModel: ObservableObject {
    @Published var isEnabled: Bool = true
    @Published var useHyperkey: Bool = false
    @Published var rows: [ShortcutRow] = [ShortcutRow()]   // empty state = ONE empty pair

    private let store = ShortcutStore()

    func load() {
        let result = store.load()
        rows = result.bindings.map { ShortcutRow(appText: $0.target.rawValue, shortcut: $0.shortcut) }
        ensureTrailingEmptyRow()
        // isEnabled / useHyperkey are app-level prefs — load from UserDefaults here.
        // isEnabled    = UserDefaults.standard.bool(forKey: "TogglerEnabled")
        // useHyperkey  = UserDefaults.standard.bool(forKey: "TogglerHyperkey")
    }

    /// Invariant from the design: exactly one trailing empty pair always sits
    /// below the filled rows; filling it spawns the next one.
    func ensureTrailingEmptyRow() {
        rows.removeAll { $0.isEmpty }                       // collapse interior empties
        if rows.isEmpty || !rows[rows.count - 1].isEmpty {
            rows.append(ShortcutRow())
        }
    }

    func delete(_ row: ShortcutRow) {
        rows.removeAll { $0.id == row.id }
        ensureTrailingEmptyRow()
    }

    func save() {
        let completed = rows.filter(\.isComplete)
        try? store.save(completed)                          // CUSTOM #3
        // UserDefaults.standard.set(isEnabled,   forKey: "TogglerEnabled")
        // UserDefaults.standard.set(useHyperkey, forKey: "TogglerHyperkey")
        // Then tell the hot-key manager to reload (mirrors the menu "Reload" action).
    }
}

// MARK: - Settings screen

struct SettingsView: View {
    @StateObject private var model = SettingsModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Toggle(isOn: $model.isEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Toggler")
                            Text("Bind global keyboard shortcuts to your apps.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: $model.useHyperkey) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Use Hyperkey")
                            Text("Treat the caps lock key as ⌘⌥⌃⇧.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Shortcuts") {
                    ForEach($model.rows) { $row in
                        ShortcutRowView(
                            row: $row,
                            showsDelete: !row.isEmpty,
                            onCommit: { model.ensureTrailingEmptyRow() },
                            onDelete: { model.delete(row) }
                        )
                    }
                }
                // When the app is off, the design dims the shortcut list:
                .opacity(model.isEnabled ? 1 : 0.4)
                .disabled(!model.isEnabled)
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save")   { model.save(); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)        // default (accent) button
            }
            .padding(20)                                     // matches the 20px footer margin
        }
        .frame(width: 560, height: 520)                      // matches the mockup window size
        .onAppear { model.load() }
    }
}

// MARK: - One row

struct ShortcutRowView: View {
    @Binding var row: ShortcutRow
    let showsDelete: Bool
    let onCommit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AppTargetField(text: $row.appText, onCommit: onCommit)      // CUSTOM #2
                .frame(maxWidth: .infinity, alignment: .leading)

            ShortcutRecorder(shortcut: $row.shortcut, onCommit: onCommit) // CUSTOM #1
                .frame(width: 120, height: 24)

            // Reserve the trash's width on the empty row so columns stay aligned.
            if showsDelete {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove this shortcut")
            } else {
                Color.clear.frame(width: 22, height: 1)
            }
        }
    }
}

// MARK: - CUSTOM #2 · App field (autocomplete + system icon)

/// Text field that shows the target app's real icon (resolved from the system
/// at runtime — the reason the mockup used drop-in icon slots) and offers an
/// autocomplete menu of installed apps.
struct AppTargetField: View {
    @Binding var text: String
    let onCommit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let icon = AppCatalog.icon(for: text) {
                Image(nsImage: icon).resizable()
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.secondary.opacity(0.35), style: .init(dash: [2]))
                    .frame(width: 18, height: 18)
            }

            TextField("Application name, bundle ID, or path", text: $text)
                .textFieldStyle(.plain)
                .onSubmit(onCommit)
            // TODO: present a suggestions popover bound to AppCatalog.matches(text)
            //       and fill `text` on selection, then call onCommit().
        }
    }
}

/// Resolves icons + autocomplete candidates for installed apps.
enum AppCatalog {
    /// Accepts a bundle id, a display name, or a .app path — same as the file format.
    static func url(for target: String) -> URL? {
        let t = target.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let ws = NSWorkspace.shared
        if t.hasSuffix(".app") || t.contains("/") { return URL(fileURLWithPath: t) }
        if let byId = ws.urlForApplication(withBundleIdentifier: t) { return byId }
        if let path = ws.fullPath(forApplication: t) { return URL(fileURLWithPath: path) } // by name
        return nil
    }

    static func icon(for target: String) -> NSImage? {
        guard let url = url(for: target) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// TODO: scan /Applications, ~/Applications, /System/Applications and filter
    /// by display name for the autocomplete menu. Cache the result.
    static func matches(_ query: String) -> [URL] { [] }
}

// MARK: - CUSTOM #1 · Press-keys recorder

/// Click to begin, then press the combo. Produces a `KeyboardShortcut` that is
/// guaranteed to match the file format by round-tripping the human-readable
/// string through your existing `ShortcutParser`.
///
/// Alternative: Sindre Sorhus's `KeyboardShortcuts` package ships a ready-made
/// SwiftUI `KeyboardShortcuts.Recorder` — drop that in instead of this view if
/// you'd rather not own the AppKit capture code.
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: KeyboardShortcut?
    let onCommit: () -> Void

    func makeNSView(context: Context) -> RecorderView {
        let v = RecorderView()
        v.onChange = { sc in shortcut = sc; onCommit() }
        return v
    }
    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.shortcut = shortcut
    }
}

final class RecorderView: NSView {
    var shortcut: KeyboardShortcut? { didSet { needsDisplay = true } }
    var onChange: ((KeyboardShortcut) -> Void)?
    private var recording = false { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) {
        recording = true
        window?.makeFirstResponder(self)
    }
    override func flagsChanged(with event: NSEvent) { needsDisplay = true }

    override func keyDown(with event: NSEvent) {
        guard recording else { return super.keyDown(with: event) }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !mods.isEmpty else { NSSound.beep(); return }   // a modifier is required

        // Build the token string in the same order ShortcutParser.displayValue uses.
        var parts: [String] = []
        if mods.contains(.control) { parts.append("control") }
        if mods.contains(.option)  { parts.append("option") }
        if mods.contains(.shift)   { parts.append("shift") }
        if mods.contains(.command) { parts.append("command") }
        let key = (event.charactersIgnoringModifiers ?? "").lowercased()
        guard !key.isEmpty else { NSSound.beep(); return }
        parts.append(key)

        // Re-parse through the existing parser so keyCode + carbonModifiers and
        // the file representation all stay consistent.
        if let sc = try? ShortcutParser.parse(parts.joined(separator: "+")) {
            shortcut = sc
            onChange?(sc)
        }
        recording = false
    }

    override func draw(_ dirtyRect: NSRect) {
        let title = recording ? "Type shortcut…"
                              : (shortcut.map(Self.glyphs) ?? "Record Shortcut")
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: recording ? NSColor.controlAccentColor : NSColor.labelColor
        ]
        let s = NSAttributedString(string: title, attributes: attrs)
        let sz = s.size()
        s.draw(at: NSPoint(x: (bounds.width - sz.width) / 2,
                           y: (bounds.height - sz.height) / 2))
    }

    /// "control+option+shift+command+t" -> "⌃⌥⇧⌘ T"
    static func glyphs(_ sc: KeyboardShortcut) -> String {
        let v = sc.displayValue
        var g = ""
        if v.contains("control") { g += "⌃" }
        if v.contains("option")  { g += "⌥" }
        if v.contains("shift")   { g += "⇧" }
        if v.contains("command") { g += "⌘" }
        let key = v.split(separator: "+").last.map(String.init) ?? ""
        return g + " " + key.uppercased()
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
