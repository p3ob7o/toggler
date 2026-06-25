# Toggler — Settings screen · SwiftUI handoff

A developer-facing spec for the Toggler settings screen. The visual reference is
the `Toggler Settings` mockup (light + dark, grouped-list layout). **Implement
with native SwiftUI controls, not a CSS translation** — a grouped `Form` already
produces the System Settings look (cards, dividers, accent switches, light/dark).

---

## Screen structure

A single resizable pane, **560 × 520 pt**:

1. **Section 1 — App controls** (grouped card)
   - `Enable Toggler` — master switch + subtitle "Bind global keyboard shortcuts to your apps."
   - `Use Hyperkey` — switch + subtitle "Treat the caps lock key as ⌘⌥⌃⇧." *(independent setting)*
2. **Section 2 — Shortcuts** (grouped list)
   - Repeating pair rows: **app field (left) · shortcut recorder (right) · trash**
3. **Footer** — `Cancel` and default `Save`, trailing-aligned, 20 pt inset.

## Control mapping

| Design element        | SwiftUI |
|-----------------------|---------|
| Window / pane         | `Form { … }.formStyle(.grouped)` in a `Settings`/`Window` scene |
| Master + Hyperkey     | `Toggle(isOn:).toggleStyle(.switch)` (label = title + caption subtitle) |
| Shortcuts group       | `Section("Shortcuts") { ForEach($rows) { … } }` |
| App field             | `TextField` + leading app icon + autocomplete *(custom — see below)* |
| Shortcut field        | press-keys recorder *(custom — see below)* |
| Delete                | `Button(role: .destructive) { } label: { Image(systemName: "trash") }` `.borderless` |
| Cancel / Save         | trailing `HStack`; Save = `.borderedProminent` + `.keyboardShortcut(.defaultAction)` |
| Light / dark / accent | automatic — do not hardcode colors |

## Behavior rules

- **Trailing empty pair:** one empty pair always sits below the filled rows;
  filling the last one spawns a new empty one. **Empty state = exactly one empty pair.**
  (`ensureTrailingEmptyRow()` in the scaffold.)
- **Delete:** trash appears on every *filled* pair; the trailing empty pair has none.
- **App disabled:** when `Enable Toggler` is off, the Shortcuts list dims (`opacity 0.4`) and is disabled.
- **Save** writes the file and triggers a hot-key reload (same effect as the menu-bar "Reload"); **Cancel** discards.
- Icons are **resolved from the system at runtime** (`NSWorkspace.icon(forFile:)`), never bundled — that's why the mockup used drop-in icon slots.

## Three custom components (everything else is native)

1. **ShortcutRecorder** — capture real keystrokes. Either drop in Sindre Sorhus's
   `KeyboardShortcuts` package (`KeyboardShortcuts.Recorder`), or use the included
   `NSViewRepresentable`. Build the token string in control→option→shift→command→key
   order and **re-parse it through the existing `ShortcutParser`** so `keyCode` /
   `carbonModifiers` / file form all stay consistent. A modifier is required.
2. **AppTargetField** — `TextField` accepting a name, bundle id, or `.app` path,
   with the resolved icon leading it and an autocomplete menu of installed apps
   (scan `/Applications`, `~/Applications`, `/System/Applications`). `AppCatalog`
   in the scaffold resolves the icon; the suggestion data source is a `TODO`.
3. **ShortcutStore.save()** — the store currently only parses. The included
   extension serializes completed rows to `~/.config/toggler/shortcuts.txt` as
   `shortcut = app`, collapsing the full ⌘⌥⌃⇧ set to the `hyper` shorthand.

## Data model (reuse existing types)

- `ShortcutBinding { shortcut: KeyboardShortcut, target: AppTarget }` → maps to a row.
- `KeyboardShortcut { keyCode, carbonModifiers, displayValue }` — recorder output.
- `AppTarget(rawValue:)` — the `.rawValue` String is the editable app text.
- `ShortcutStore.load()` for read; the new `save()` for write.
- App-level prefs (`isEnabled`, `useHyperkey`) → `UserDefaults`.

## Files in this handoff

- `SettingsView.swift` — the screen, view-model, row view, and the two custom-view stubs.
- `ShortcutStore+Persistence.swift` — the `save()` writer.
- `HANDOFF.md` — this doc.

## Dependencies

- macOS 13+ (Ventura) for `.formStyle(.grouped)` / `.toggleStyle(.switch)`.
- *Optional:* `KeyboardShortcuts` (SPM) for the recorder.

## Acceptance checklist

- [ ] Two switches; Hyperkey toggles independently of the master.
- [ ] Trailing empty pair always present; filling it adds another.
- [ ] Empty state shows a single empty pair.
- [ ] Each filled pair has a working trash; empty pair has none.
- [ ] Recorder captures a real combo and shows ⌃⌥⇧⌘ glyphs.
- [ ] App field autocompletes installed apps and shows their real icons.
- [ ] Save writes `shortcut = app` lines and reloads hot-keys; Cancel discards.
- [ ] List dims + disables when the app is off.
- [ ] Looks correct in light and dark with no hardcoded colors.
