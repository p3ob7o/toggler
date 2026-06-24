# Toggler

Toggler is an ultra-light macOS menu bar utility that binds global keyboard shortcuts to apps.

When a shortcut is hit:

- If the app is not running, Toggler launches it and brings it forward.
- If the app is running in the background, Toggler makes it frontmost.
- If the app is already frontmost, Toggler hides it without quitting it.

## Shortcuts

On first launch, Toggler creates:

```text
~/.config/toggler/shortcuts.txt
```

Each active line uses this format:

```text
shortcut = app
```

Examples:

```text
hyper+t = com.apple.Terminal
hyper+s = Safari
hyper+c = /Applications/Google Chrome.app
```

`hyper` expands to `command+option+control+shift`. App targets can be bundle identifiers, app names, or `.app` paths. Toggler can provide the Hyperkey itself — see below — or you can use any external Hyperkey setup (Karabiner, Hyperkey.app, …).

After editing the file, use the menu bar item to reload shortcuts.

## Caps Lock → Hyperkey

Toggler can turn your Caps Lock key into a "Hyper" modifier (Command + Option + Control + Shift held together) so the `hyper+...` shortcuts above are easy to reach with one key.

Enable it from the menu bar: **Caps Lock → Hyperkey**. While enabled:

- Holding Caps Lock acts as Hyper — e.g. Caps Lock + T toggles Terminal when you have `hyper+t = com.apple.Terminal`.
- Caps Lock no longer toggles alpha-lock; tapping it on its own does nothing.

This needs macOS **Accessibility** permission (System Settings → Privacy & Security → Accessibility). The first time you enable it, grant Toggler permission and turn the toggle on again. It is **off by default**, your choice is remembered, and Toggler restores normal Caps Lock behavior when you turn it off or quit.

Under the hood Toggler remaps Caps Lock to F18 with `hidutil` and injects the four Hyper modifiers while F18 is held. Inspect the remap with:

```sh
hidutil property --get UserKeyMapping
```

## Run

```sh
./script/build_and_run.sh
```
