# Padlet — notes for Claude

Padlet is a macOS menu bar app (Swift Package, no Xcode project) that turns trackpad edges
into controls and adds gestures. Repo `vuhpquang/padlet` (formerly `mac-shortcuts`; GitHub
redirects the old name). Work on `develop`, which is also the release branch.
Bundle ID `com.vuhpquang.padlet`, macOS 13+, universal binary.

## Commands

```bash
swift build                       # debug build
swift test                        # 79 unit tests: recognizers, actions, window geometry, settings
./build.sh                        # release .app + styled DMG in build/
scripts/release.sh X.Y.Z [notes.md]   # full release (see below)
DRY_RUN=1 scripts/release.sh X.Y.Z    # build + verify only, reverts the version bump
PADLET_SNAPSHOT=/tmp/shots .build/debug/Padlet   # render every screen (light+dark) to PNG
PADLET_SWITCHER_DEMO=/tmp/shots .build/debug/Padlet  # show the live glass app switcher, capture it
PADLET_UPDATE_DRYRUN=1 .build/debug/Padlet       # check → download → verify an update, no install
log stream --predicate 'subsystem == "com.vuhpquang.padlet"'
```

Check UI changes with `PADLET_SNAPSHOT`, not by launching the app. The user's own copy
runs from `/Applications/Padlet.app`. Don't launch, quit or replace it unless asked.

## Layout

`Sources/Padlet/`: `App/` (entry, AppDelegate, menu bar, permissions), `Input/` (private
MultitouchSupport bridge), `Recognizers/` (pure: frames in, events out — keep them free of
AppKit/side effects so they stay testable), `Engine/` (GestureCoordinator), `Actions/`,
`System/` (volume, brightness, media keys, OSD, haptics), `Settings/`, `Update/`, `UI/`.
`scripts/`: icon, DMG background, dmgbuild settings, release. `packaging/`: DMG art,
Homebrew cask source.

## UI surfaces

- Menu bar panel (`UI/PanelView.swift`, left click): quick controls. Its sections
  (`EdgeControlsSection`, `GesturesSection`, `EdgeBehaviorSection`, `GeneralSection`,
  `UpdatesSection`, `ProfilesPage`, `ProfileDetailPage`) are shared with the Settings window.
- Settings window (`UI/SettingsWindow.swift`, `AppWindows`). Panes: General, Edge Controls,
  Gestures, App Profiles, About & Updates. "About Padlet" everywhere opens the About & Updates
  pane, so there is no separate About window. While the window is open the app is `.regular`
  (Dock icon + `AppMenu`: About / Check for Updates / Settings ⌘,), then goes back to
  `.accessory`.
- Right-click quick menu (`App/MenuBarController.swift` + `UI/QuickMenuView.swift`).

## Top-edge app switcher

The switcher is an Edge Controls setting (`EdgeSettings.topAppSwitcher`, row in `EdgeControlsSection`),
independent of the Top Edge Swipe family flag (`EdgeRecognizerConfig.appSwitcher` = edgeControls && setting).
`EdgeGestureRecognizer` decides top-strip flicks on lift when it is on (default): lifted within `topSwipeMaxDuration` = mapped flick slot; held longer and moved sideways
`switcherCommit` = `switcherBegan/Moved(offset)/Ended(commit)`, one app per `switcherStep`.
`UI/AppSwitcher.swift` shows the panel (glass on macOS 26, material before) with apps from
`FrontmostAppTracker.switcherApps()` (frontmost, then MRU, then other Dock apps); offset wraps.
Switcher off = old behaviour (flick fires mid-gesture, slow moves are pointer moves).
Glass doesn't render offscreen, so `PADLET_SNAPSHOT` uses the material fallback; check glass
with `PADLET_SWITCHER_DEMO`.

## Actions

`GestureAction` = `.none | .builtin(BuiltinAction) | .keystroke | .openApp | .runShortcut |
.openURL | .pasteText | .runCommand`.
`BuiltinAction` raw values are persisted (and match v1/v2.0 type names), so never rename
one. Add a case → give it a group, a title and a branch in `ActionExecutor.perform`.
Window actions live in `System/WindowManager.swift` (AX API). Keystrokes post real key
codes via `System/KeyCodes.swift` (layout-aware), and fall back to a Unicode event.
Do Not Disturb has no public API: `System/DoNotDisturb.swift` runs the user's
"Toggle Do Not Disturb" shortcut and shows setup help if it fails. The on/off hotkey is a
Carbon hotkey (`System/GlobalHotKey.swift`, `GeneralSettings.toggleHotKey`), and it is
paused while a recorder listens.

## Gotchas

- Uses private frameworks (MultitouchSupport, DisplayServices, OSDUIHelper) via dlopen —
  every symbol is optional; keep fallbacks.
- `Preferences.swift` still references `com.mac-shortcuts.app` / "Mac Shortcuts" on purpose:
  that is the one-time settings migration from the old app. Don't rename those.
- GitNexus can't parse Swift. Don't run `npx gitnexus analyze` in this repo (it writes
  AGENTS.md/CLAUDE.md/.claude here). Assess blast radius with grep.
- Accessibility permission is keyed to the code signature. A build with a different signer
  (ad-hoc, another cert) loses the grant and can't auto-update installed copies.
  The old entry stays in the list, shown as on, but it doesn't match. tccd logs
  "Failed to match existing code requirement", and the UI often won't remove it. Fix:
  `tccutil reset Accessibility com.vuhpquang.padlet` (the app has a "Reset & Ask Again"
  button in Settings → General for this), then relaunch and grant again.
- Replacing `/Applications/Padlet.app` doesn't change the process that is already running.
  If that process was granted access, the grant belongs to its signature. Quit it before
  swapping builds that are signed differently.
- In this shell `log` is overridden by a zsh function. Use `/usr/bin/log show …` to read
  tccd and app logs.

## Signing

Releases are signed with the self-signed keychain identity **"Padlet Self-Signed"**
(certificate SHA-1 `3e9ca590…86a9`). It gives a stable designated requirement
(`certificate root = H"…"`), so Accessibility survives updates. `build.sh` uses it when it is
in the keychain and falls back to ad-hoc otherwise.

- Backup: `~/.config/padlet-signing/padlet-signing.p12` + `p12-password.txt` (never commit).
  Import on another Mac: `security import padlet-signing.p12 -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign`.
- If the key is lost, installed copies can never auto-update again; users must reinstall.
- It is not notarized: first launch needs System Settings → Privacy & Security → Open Anyway.
  `TEAM_ID="Developer ID Application: …" NOTARIZE=1 ./build.sh` is ready for a real
  Apple certificate, but switching signer breaks auto-update for existing installs once.

## Auto-update

`Update/UpdateManager.swift` polls `api.github.com/repos/vuhpquang/padlet/releases/latest`
at launch and every 6 h. It compares the `vX.Y.Z` tag with `CFBundleShortVersionString`
and downloads the first `.dmg` asset. Before installing, it mounts the DMG and checks the
bundle ID, `codesign --verify`, and that the new app satisfies the running app's designated
requirement (same signer). A detached shell script then swaps the bundle and relaunches.
It only replaces a bundle whose path ends in `.app`.
So a release must be: tag `vX.Y.Z`, marked Latest, with `Padlet.dmg` attached, signed by
the release certificate.

## Releasing

Always use `scripts/release.sh X.Y.Z [notes.md]` from a clean `develop` synced with origin.
It:
1. Bumps `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`.
2. Runs the tests.
3. Runs `./build.sh` (universal binary, signed, DMG built with dmgbuild in `.build/dmgbuild-venv`).
4. Refuses to continue unless the app is signed by the release certificate.
5. Updates `packaging/homebrew/padlet.rb` (version + sha256).
6. Commits `release: vX.Y.Z`, tags it and pushes.
7. Runs `gh release create` with the DMG.
8. Regenerates `Casks/padlet.rb` in `vuhpquang/homebrew-tap` and pushes it.

Without a notes file it uses GitHub's generated notes. Write a notes file for user-facing
releases.
After releasing from the parent `software-team` repo, bump the submodule pointer with
`git add projects/padlet` and commit `chore: bump padlet submodule (Padlet X.Y.Z)`.

## Homebrew

Tap repo `vuhpquang/homebrew-tap`. The cask source of truth is
`packaging/homebrew/padlet.rb`, and the tap copy is generated by the release script, so
don't edit it by hand.
Install: `brew install --cask vuhpquang/tap/padlet`. Since Homebrew 6, third-party taps are
untrusted until the user trusts them (tap code is Ruby that runs on load). Installing by fully
qualified name trusts just that cask, so no separate `brew trust` is needed. Commands that
only *load* the cask (`brew info`, `fetch`, `audit`) still need `brew trust vuhpquang/tap`
first. The full name also avoids the unrelated `padlet` cask in homebrew/cask. The cask declares `auto_updates true`, so `brew upgrade` leaves updating to
the app. The official homebrew/cask is out of reach for now: it needs notarization and a
popular repo.

## DMG

Background drawn by `scripts/make-dmg-background.swift` → `packaging/dmg-background{,@2x}.png`
(920×400 pt — Finder won't make the window narrower). Layout in `scripts/dmg-settings.py`.
Icon positions must match between the two files.
