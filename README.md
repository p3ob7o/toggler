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

`hyper` expands to `command+option+control+shift`, so `hyper+t` works with Hyperkey-style setups. App targets can be bundle identifiers, app names, or `.app` paths.

After editing the file, use the menu bar item to reload shortcuts.

## Run

```sh
./script/build_and_run.sh
```
