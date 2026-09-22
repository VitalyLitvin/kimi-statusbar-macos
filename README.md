# Kimi Status Bar

A macOS menu bar app that shows what [Kimi Code CLI](https://www.kimi.com/code/docs/en/kimi-code-cli/) is doing — live state, current tool, project and session, at a glance.

![Kimi Status Bar](docs/screenshot.png)

## Features

- **Live status in the menu bar** — crescent moon icon + label: `Thinking…`, `Running command`, `Editing`, `Browsing web`, …
- **Color-coded states** — blue: working · orange: awaiting your permission · green: done · amber: waiting for input
- **Elapsed timer** while Kimi is working
- **Completion sound** when a turn finishes or a background task completes (the same `completion.mp3` style as other status bars)
- **Dropdown menu** with project, session title, and quick actions
- **Self-managing lifecycle** — launches when a Kimi Code session starts, quits ~15 s after the last session ends, relaunches itself on the next event

## Requirements

- macOS 13+
- [Kimi Code CLI](https://www.kimi.com/code/docs/en/kimi-code-cli/) installed and logged in
- [Node.js](https://nodejs.org/) on the machine (the hook scripts are plain Node, no dependencies)

## Install

1. Download `KimiStatusBar.dmg` (or `-macOS.zip`) from the latest [Release](../../releases/latest), open it and drag **Kimi Status Bar** to Applications.
2. Register the hooks (one time):

   ```sh
   node "/Applications/KimiStatusBar.app/Contents/Resources/install.js"
   ```

3. Start a new `kimi` session — the moon appears in the menu bar.

Hooks activate for sessions started after installation; already-running sessions pick them up on their next start.

> **Gatekeeper:** the app is not signed with a paid Developer ID. On first launch macOS may warn about an unidentified developer — right-click the app → **Open**, or run `xattr -cr "/Applications/KimiStatusBar.app"`.

## Uninstall

```sh
node "/Applications/KimiStatusBar.app/Contents/Resources/uninstall.js"
```

Removes the hooks from `~/.kimi-code/config.toml`, deletes `~/.kimi-code/statusbar/` and the app. Everything else in your config stays untouched (a one-time backup is kept at `config.toml.bak-statusbar`).

## How it works

Kimi Code [hooks](https://www.kimi.com/code/docs/en/kimi-code-cli/customization/hooks.html) (`UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `PermissionResult`, `Stop`, `Interrupt`, `Notification`, `SessionStart`, `SessionEnd`) fire tiny Node scripts that atomically write `~/.kimi-code/statusbar/state.json` and touch per-session files under `sessions.d/`. The app polls that state once a second and renders it. Session files older than 10 minutes are ignored, so killed terminals and one-shot `kimi -p` runs never leave the app hanging.

If you relocated the Kimi Code data directory with `KIMI_CODE_HOME`, the hook scripts honor it automatically; for the menu bar app, run `launchctl setenv KIMI_STATUSBAR_DIR ~/.kimi-code-custom/statusbar` once per login (`install.js` prints the exact command).

## Build from source

```sh
git clone https://github.com/VitalyLitvin/kimi-statusbar-macos.git && cd kimi-statusbar-macos
make install   # builds universal binary, installs app + hooks
make dmg       # or: release artifacts in dist/
```

Swift Package Manager only — no Xcode project needed.

## License

[MIT](LICENSE)
