import Foundation

/// One editable app↔shortcut pair in the Settings list.
struct ShortcutRow: Identifiable, Equatable {
    let id = UUID()
    var appTarget: String = ""
    var shortcutText: String = ""
    var shortcutError: String?

    /// A row is empty when neither field is set — touching either field makes
    /// it non-empty (which is what drives appending a fresh trailing row).
    var isEmpty: Bool {
        appTarget.trimmedValue.isEmpty && shortcutText.trimmedValue.isEmpty
    }

    /// A row is saveable only when both fields are set.
    var isFilled: Bool {
        !appTarget.trimmedValue.isEmpty && !shortcutText.trimmedValue.isEmpty
    }
}

/// What `AppDelegate` needs to re-apply after a save.
struct SettingsOutcome: Sendable {
    let isEnabled: Bool
    let hyperkeyEnabled: Bool
}

/// Backs the Settings window: loads current state, manages the dynamic row
/// list, validates shortcuts, and persists on save.
@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var rows: [ShortcutRow] = []
    @Published var isEnabled: Bool
    @Published var hyperkeyEnabled: Bool
    @Published var saveErrorMessage: String?

    private let store: ShortcutStore
    private let onSave: @MainActor (SettingsOutcome) -> Void

    /// `hyperkeyEnabled` reflects the real feature's current state, supplied by
    /// `AppDelegate` (which owns `HyperkeyController`/`HyperkeyPreference`).
    init(
        store: ShortcutStore,
        hyperkeyEnabled: Bool,
        onSave: @escaping @MainActor (SettingsOutcome) -> Void
    ) {
        self.store = store
        self.onSave = onSave
        self.isEnabled = SettingsDefaults.isEnabled
        self.hyperkeyEnabled = hyperkeyEnabled
        reload()
    }

    /// Loads bindings from disk and the app-enabled flag. Existing bindings map
    /// to rows via `displayValue`, which round-trips through the parser.
    /// `hyperkeyEnabled` is owned by the caller and left untouched here.
    func reload() {
        let result = store.load()
        rows = result.bindings.map { binding in
            ShortcutRow(
                appTarget: binding.target.rawValue,
                shortcutText: binding.shortcut.displayValue
            )
        }
        validate()
        normalizeTrailingEmptyRow()
        isEnabled = SettingsDefaults.isEnabled
    }

    /// Called by the view after any row edit. Refreshes validation and keeps
    /// exactly one trailing empty row. Idempotent, so it converges if a view
    /// `onChange` re-invokes it after the mutations here.
    func rowsDidChange() {
        validate()
        normalizeTrailingEmptyRow()
    }

    /// Ensures the list ends with exactly one empty row (and that the empty
    /// state is a single empty row).
    func normalizeTrailingEmptyRow() {
        while rows.count > 1, rows[rows.count - 1].isEmpty, rows[rows.count - 2].isEmpty {
            rows.removeLast()
        }
        if rows.isEmpty || rows.last?.isEmpty == false {
            rows.append(ShortcutRow())
        }
    }

    func removeRow(_ id: UUID) {
        rows.removeAll { $0.id == id }
        normalizeTrailingEmptyRow()
    }

    func validate() {
        for index in rows.indices {
            let newError = validationError(for: rows[index].shortcutText)
            if rows[index].shortcutError != newError {
                rows[index].shortcutError = newError
            }
        }
    }

    /// Persists rows + flags and asks `AppDelegate` to re-apply. Returns false
    /// (and sets `saveErrorMessage`) if a filled row has an invalid shortcut or
    /// writing fails.
    func save() -> Bool {
        validate()

        if rows.contains(where: { $0.isFilled && validationError(for: $0.shortcutText) != nil }) {
            saveErrorMessage = "Some shortcuts are invalid. Fix them before saving."
            return false
        }

        let entries = rows
            .filter(\.isFilled)
            .map { ShortcutStore.Entry(
                shortcutText: $0.shortcutText.trimmedValue,
                appTarget: $0.appTarget.trimmedValue
            ) }

        do {
            try store.save(entries)
        } catch {
            saveErrorMessage = "Could not save shortcuts: \(error.localizedDescription)"
            return false
        }

        SettingsDefaults.isEnabled = isEnabled
        saveErrorMessage = nil
        // Hyperkey is persisted/applied by AppDelegate through HyperkeyController.
        onSave(SettingsOutcome(isEnabled: isEnabled, hyperkeyEnabled: hyperkeyEnabled))
        return true
    }

    private func validationError(for shortcutText: String) -> String? {
        let trimmed = shortcutText.trimmedValue
        guard !trimmed.isEmpty else { return nil }
        do {
            _ = try ShortcutParser.parse(trimmed)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

private extension String {
    var trimmedValue: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
