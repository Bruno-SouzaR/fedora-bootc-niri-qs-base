# Palette Presets — Design

Date: 2026-08-12

## Goal

Rework the pill's "Palette" sub-menu so users can define the pill's colours through up to 8 named roles with clear meaning, save their combinations as presets, and pick among factory presets, saved presets, or the wallpaper-derived dynamic palette — without risking broken contrast or external-system breakage.

## Current state

- `Theme.qml` defines ~35 tokens but they are not independent: 3 ramps (surface, accent, text) derived from a single hue + saturation + light/dark tone via `wallcolors.py`.
- The `Palette` sub-menu (`Appearance.qml`) is a `SettingsSeg` with `Static | Dynamic | Manual`.
- Manual mode today only picks a single hue (`Flags.manualHue` + `manualSat` + `manualDark`) and rebuilds the whole palette through `wallcolors.py --hue`, which also recolours niri, the terminal and fastfetch.
- `Flags.qml` persists session flags to `~/.local/state/ricelin/flags.json`.
- `Dyn.qml` watches `~/.cache/ricelin/colors.json`, written by `wallcolors.py`, for the dynamic mode.

## Scope decisions

- Only the pill changes when a preset/manual palette is active. niri, terminal (ghostty) and fastfetch keep their current colours (zero risk).
- Derivation of derived tones happens in `Theme.qml` (QML: `Qt.darker`, `Qt.lighter`, `Qt.alpha`), not in Python, so the Manual editor preview is live without running a script.
- Dynamic mode remains a separate source: clicking Dynamic derives from the wallpaper and that palette becomes the base of the Manual editor, exactly like any preset from Presets does.

## Menu structure

`Flags.paletteMode` values: `presets` · `dynamic` · `manual`.

Sub-menu "Palette" (in `Appearance.qml`):

- **Presets** — horizontally scrollable mini-list, ~4 slots visible, remainder reached by side scrolling. Contains 3 factory presets (`Warm`, `Cool`, `Mono`) plus every user-saved preset. Selecting one applies its 8 roles to the pill.
- **Dynamic** — current behaviour (derives from wallpaper via `wallcolors.py`); generated palette becomes the base for Manual.
- **Manual** — 8 role pickers; base colours load from the currently active preset (or from the Dynamic-generated palette when that is the current mode). Contains a **Save preset** button: user names it, the preset is saved, automatically selected in Presets, and appears in the Presets list.

## The 8 colour roles (anchors)

| # | Role | Renders | Derived from it automatically |
|---|------|---------|-------------------------------|
| 1 | Pill background | pill body, tiles, shadow | `cardBot`, `tileBg`, shadow |
| 2 | Menu surface | menus/popups, raised surfaces | `cardTop`, `frameBg`, `frameBorder` |
| 3 | Accent | menu selection, active workspace dot, glow, flame | `onGlow`, `verm*`, `todayWarm`, `flameInk/Ember/Burn/Tip` |
| 4 | Inactive dots | non-selected workspace dots | — |
| 5 | Primary text | main labels | `cream`, `bright` |
| 6 | Secondary text | dim labels, icons | `dim`, `subtle`, `faint`, `iconDim` |
| 7 | Border | outlines, hairline fades | `border` + derived alphas |
| 8 | Tone (dark/light) | contrast guard | chooses dark/light direction for all derived tones |

### Always automatic (never a user field)

All alpha-based tokens (`hair`, `hairSoft`, `sheen`, `threadBg`, `frameBg`, `frameBorder`, `creamMenu`), shadows, and dark accent tones (`vermDeep`, `vermDim`, `vermDimDeep`, `vermBurn`). `tone` guarantees text contrast.

## Preset data format

Each preset is an object with the 8 roles:

```json
{
  "id": "preset-warm",
  "name": "Warm",
  "factory": true,
  "roles": {
    "background": "#211711",
    "surface": "#2e231b",
    "accent": "#e0563b",
    "dotInactive": "#e6d6cb",
    "text": "#e6d6cb",
    "textSoft": "#8a7d74",
    "border": "#3a2a22",
    "tone": "dark"
  }
}
```

## Theme.qml derivation

Replace the current `dyn ? Dyn.x : static-hex` ternaries with derivation from the active preset's roles:

- `cardBot`/`tileBg` ← `background`
- `cardTop`, `frameBg`, `frameBorder` ← `surface`
- accent family ← `accent` via `Qt.darker`/`Qt.lighter` (+ alpha for glow)
- active dot ← `accent`; inactive dot ← `dotInactive`
- `cream`, `bright` ← `text`
- `dim`, `subtle`, `faint`, `iconDim` ← `textSoft`
- `border` ← `border`
- hairline alphas ← `Qt.alpha(text/textSoft)`
- `shadow` ← alpha of black
- `tone` selects dark vs light direction for derived tones (contrast guard)

In Dynamic mode (`paletteMode === "dynamic"`), Theme continues to read `Dyn` as today.

## Persistence

- New file `~/.local/state/ricelin/presets.json`: list of presets + `activePresetId`.
- `flags.json` keeps the current `paletteMode`; the active preset reference moves to `presets.json`.
- Factory presets are immutable (re-seeded if missing).

## UI labels (English, descriptive)

- Pill background
- Menu surface
- Accent (selection & active dot)
- Inactive workspace dots
- Primary text
- Secondary text
- Border
- Tone (Dark/Light)

Factory presets: `Warm` · `Cool` · `Mono`.

## Files touched

- `Singletons/Theme.qml` — derive from active preset roles instead of static hex.
- `Singletons/Flags.qml` — paletteMode values; expose active preset / save API.
- New preset storage (singleton or adapter) reading/writing `presets.json`.
- `Appearance.qml` — Presets scrollable list, Manual 8-role editor, Save preset flow; remove the old single-hue editor.
- `Dyn.qml` — unchanged (source stays).
- `wallcolors.py` — unchanged (still feeds Dynamic + external consumers). The `--hue` (single-hue manual) path is no longer used as the pill's colour source; it remains for external consumers only.

## Obsolete manual flags

`Flags.manualHue`, `Flags.manualSat`, `Flags.manualDark` and the single-hue editor in `Appearance.qml` are replaced by the 8-role editor and preset storage. Backwards-compatible: keep the fields in `flags.json` harmless for migration, but the pill no longer derives its palette from them.

## Out of scope

- Changing niri / terminal / fastfetch colours from presets or manual.
- Derivation logic in Python (stays in QML).
- More than 8 user-defined roles.
