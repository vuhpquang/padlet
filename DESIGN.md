---
name: Padlet
platform: macos
appearance: light+dark
tokens: Sources/Padlet/UI/Components.swift; Vendor/app-shell/Sources/AppShellCore/ShellTokens.swift
dials:
  variance: 2              # stock macOS: a Control Center–style list, grouped Settings forms
  motion: 2                # short ease-out state changes (0.12–0.15 s), nothing choreographed
  density: 7               # a 340 pt menu bar panel packed with rows, sliders and pickers
fonts: system
accent: "#5C59F0"
---

# Padlet design

## 1. The look

Padlet lives in the menu bar. Its face is a **340 pt panel** that reads like a denser Control Center:
a header with the app icon, a "Ready" status and the master switch; a levels card showing the edge
functions live (Brightness, Volume 54 %); then plain rows grouped under small grey section headers —
each row a **coloured circular icon badge**, a medium-weight title, a one-line secondary subtitle and
a mini switch or compact menu picker on the right. The colour of a badge says what the control does
(volume blue, brightness orange, Padlet's indigo for everything else); a badge that is off turns into
a neutral grey circle. Settings is the opposite temperament: the stock app-shell window with grouped
forms, no Padlet styling at all. The rest is small: a right-click quick menu, three onboarding pages,
and the top-edge app switcher strip on Liquid Glass.

Load-bearing ideas:

1. **Badge colour = function, fill = state.** Active and tinted → filled colour with white glyph; off
   → `primary` at low opacity with a muted glyph.
2. **Compact, Control Center density in the panel**; stock, roomy grouped forms in Settings. The same
   `Preferences` fields are edited in both, so every setting appears twice.
3. **Indigo accent** (`Theme.accent`) tints the panel (`.tint`), selection and links like "Swap Sides".
4. **Glass only on the floating switcher**, with a material fallback.

## 2. Identity and references

- **macOS Control Center / menu bar extras**: the panel's row rhythm and mini switches. Padlet keeps
  its own indigo, its own badge colours and icon (indigo tile with a trackpad glyph,
  `scripts/make-icon.swift`).
- **BetterTouchTool / Swish-style gesture apps**: the feature set, not the look. Nothing is copied.
- App-shell (`.claude/rules/app-shell.md`) gives the family look of About, Updates, What's New and the
  Settings shell, shared with LaunchApp and ZenTask.

## 3. Tokens

The token source is the `Theme` enum in `Sources/Padlet/UI/Components.swift`, plus app-shell's
`ShellTokens.swift` for shared surfaces.

| Role | Value | Where |
|---|---|---|
| Accent | `Color(red: 0.36, green: 0.35, blue: 0.94)` ≈ `#5C59F0` (same in both appearances); `accentNS` for AppKit | `Theme.accent` |
| Function colours | volume `#30A6FF`, brightness `#FF9E0A`, keyboard light `#B073FF`, scroll `#33C78C`, zoom `#FF5C8C`, off `.secondary` | `Theme.color(for:)` |
| Gesture symbols / titles / subtitles | SF Symbol + copy per `GestureFamily` | `Theme.symbol/title/subtitle(for:)` |
| Panel width | 340 pt | `Theme.panelWidth` |
| Spacing | literals: 16 pt panel side padding, 12 pt row icon gap, 40 pt sub-row indent | `PanelView`, `Components` (not tokens — see gaps) |
| Radii | Card 14, levels/profile tiles 10–12, onboarding 12/18, quick menu 6; switcher derives cell radius from the outer one (concentric) | literals, all `.continuous` |
| Fills | `Color.primary.opacity(0.05–0.09)` for neutral wells, borders `0.07` | literals |
| Durations | `easeOut 0.15` badge fill, `easeInOut 0.15` disclosure, `easeOut 0.12` switcher selection | literals |

## 4. Typography

System font throughout. The panel uses **fixed sizes** for density: titles 13 pt medium, subtitles and
metadata 11 pt secondary, section headers 12 pt semibold secondary, sub-rows 12.5 pt, badge glyphs
12.5 pt semibold; numbers (`54 %`, `1.5×`) use `.monospacedDigit()`. Settings pages use the form's
default text styles. Onboarding titles use large bold system type.

## 5. Components

All in `Sources/Padlet/UI/Components.swift` unless noted.

- `IconBadge` — 28 pt circle; filled with the function/accent colour when active and tinted.
- `SettingRow` — badge + title/subtitle + trailing control; optional `DisclosureChevron` that expands
  `SubRow`s (indented 40 pt) underneath.
- `SliderRow` — badge, title, monospaced value label, small slider indented under the title.
- `SectionHeader` — grey semibold label with an optional mini switch (the family on/off).
- `SwitchToggle` — `.switch` at `.mini` size.
- `ActionPickerRow` / `OverridePickerRow` — label + compact `.menu` picker (170 pt) with
  `ActionDetailField` below for key/app/shortcut input; override rows say "Default (…)".
- `Card` — 14 pt continuous rounded well (`primary` 5.5 % fill, 7 % border); `LevelsCard` in
  `PanelView.swift` is the live brightness/volume readout.
- Settings: app-shell `SettingsShell` with Padlet's pages as stock `Form`s
  (`UI/SettingsPages.swift`), then the shared Updates and About panes.
- `AppSwitcher` (`UI/AppSwitcher.swift`) — a row of app icons with a selection cell and the app name.
- `QuickMenuView` — right-click menu: header + one switch per family.

## 6. Layout and density

- Panel: fixed 340 pt wide, 16 pt side padding, scrolls when taller than the screen allows
  (`maxContentHeight`), footer (Settings, more menu, quit) under a divider.
- Rows are tight (1 pt between title and subtitle, ~10 pt between rows); groups separated by a
  `Divider` and a section header. Disabled groups drop to 45 % opacity.
- Settings window: 760 × 580 snapshot size, sidebar + grouped form; rows follow the system form.
- Density 7 is the panel; Settings is system density.

## 7. Depth, materials, glass

- Panel and quick menu: the system menu bar window material; no extra shadows.
- App switcher: Liquid Glass (`.glassEffect(.regular)`) by default, `.regularMaterial` as the setting's
  Blur choice and as the fallback before macOS 26 or with Reduce Transparency.
- Wells/cards are flat `primary`-opacity fills, never glass.

## 8. Motion

Small, functional, ease-out: badge fill 0.15 s, disclosure chevron rotation 0.15 s, switcher selection
0.12 s. The switcher drops its animation when Reduce Motion is on. Padlet has **no global animation
switch** (see gaps). The system volume/brightness bezel (OSD) is the feedback while sliding an edge.

## 9. States

- Not available: the levels card shows "—" and "Not available here" (e.g. brightness on an external
  display).
- Off: badge turns neutral, group at 45 % opacity, subtitle stays.
- Permission missing: onboarding page + Settings → General "Reset & Ask Again" for Accessibility.
- Glass unavailable: a note under the switcher background picker says why blur is used.
- Long text: subtitles are one line with tail truncation; picker labels truncate inside 170 pt.
- Empty profiles list: render not checked in this pass (see gaps).

## 10. Do's and don'ts

- Do add every new setting to **both** the panel section and the Settings page (same `Preferences`
  field).
- Do keep function colours stable: a user learns "blue = volume" across the panel, OSD and onboarding.
- Do leave Settings stock (`.formStyle(.grouped)`, no Padlet card style there).
- Do check glass with `PADLET_SWITCHER_DEMO`; the offscreen snapshot only shows the fallback.
- Don't put glass on the panel or on cards.
- Don't rename persisted enum raw values while touching UI (`BuiltinAction`, settings keys).

**Allowed exceptions** (hub banned tells used on purpose):

- *Fixed point font sizes* in the menu bar panel and quick menu: deliberate Control Center–like
  compactness, applied consistently across the panel. Settings keeps text styles.
- *Several accent-like colours* in the panel: the function colours are a code (one per edge
  function), not competing accents; Padlet's own accent is the indigo.

## 11. Render recipe

From `projects/padlet`:

```bash
swift build
PADLET_SNAPSHOT=<dir> .build/debug/Padlet     # every screen, light + dark, then exits
PADLET_SWITCHER_DEMO=<dir> .build/debug/Padlet  # the live glass switcher (shows on screen briefly)
```

`PADLET_SNAPSHOT` writes `panel-{main,settings,profiles,profile}`, `quickmenu`,
`onboarding-{0,1,2}`, `settings-{general,edges,gestures,profiles,profile,updates,about}` and
`switcher`, each `-light.png` / `-dark.png`. Glass renders as the material fallback offscreen. Never
launch or replace `/Applications/Padlet.app` to check UI.

## 12. Known gaps

- **Spacing, radii, fills and durations are literals** in views (≈ 61 fixed font sizes, 23
  `.opacity(0.0x)` fills, radii 6/10/12/14/18). Promote to `Theme` tokens when touching a view; don't
  add more literals.
- **No app-wide animation switch**; only the switcher checks Reduce Motion. Badge/disclosure
  animations ignore it.
- **Onboarding page 1 is a row of three equal feature cards** (Edge Controls, Gestures, App Profiles)
  on a centred welcome — reads as a template; a candidate for `design-directions` if onboarding is
  revisited.
- Mini switches render grey in snapshots (inactive window); check accent tint on a live build.
- Function colours are fixed sRGB values, not tuned per appearance or for Increase Contrast.
- Empty states (no app profiles) not reviewed in this pass.
