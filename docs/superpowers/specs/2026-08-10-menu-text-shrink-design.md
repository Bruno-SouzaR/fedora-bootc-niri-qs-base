# Menu text 15% smaller (windows kept) — design

**Date:** 2026-08-10
**Status:** Approved
**Scope:** text scaling inside the 23 pill menu surfaces only. Text (`font.pixelSize`,
`font.letterSpacing`) drops ~15% from the current size; surface geometry and window
sizes stay exactly as today.

Followup to the 2026-08-10 menu-sizing change (`menuScale: 1.4`, `surfaceS: s *
menuScale`). Testing on the target machine confirmed the enlarged windows look
right but the text inside them is now too big. This change decouples text scale
from geometry scale inside menu surfaces.

The value: text currently renders at `1.4×` (the `surfaceS` bump). Reducing 15% of
that gives ≈`1.19×` of the original — text smaller, still larger than the pre-bump
state. Windows, paddings, margins, row heights, `implicitHeight` and icons stay at
`surfaceS` (1.4×) exactly as today.

## 1. Mechanism: `textScale` / `textS` on the surface base

**`PillSurface.qml`** — the base for all 23 menu surfaces — gains a text scale
decoupled from the geometry scale `s`:

```qml
property real textScale: 1
readonly property real textS: s * textScale
```

- `s` keeps driving geometry (insets, paddings, implicit sizes) — untouched.
- `textS` drives only `font.pixelSize` and `font.letterSpacing` inside menu surfaces.
- Default `textScale: 1` → `textS == s`, so any future non-menu `PillSurface`
  derived surface behaves as today.

**`Pill.qml`** — next to `menuScale`:

```qml
readonly property real menuTextScale: 0.85
```

The 23 menu-surface `Loader`s that already set `s: pill.surfaceS` additionally set
`textScale: pill.menuTextScale`. Non-menu loaders (`Ame`, rest/hover rows, `Osd`,
toast, quick overlays) do not set it — default 1.

Result: inside menu surfaces `textS = surfaceS * 0.85 ≈ 1.19 * s`.

## 2. Direct font sites in the 23 menu surface files

Mechanical substitution in the files that derive from `PillSurface` or
`SettingsSurface` (`root` is the surface):

- `font.pixelSize: X * root.s` → `font.pixelSize: X * root.textS`
- `font.letterSpacing: X * root.s` → `font.letterSpacing: X * root.textS`

Files (all 23 menu surfaces; `Settings.qml` contributes none but is listed for
completeness):

`Recorder.qml`, `Calendar.qml`, `Keybinds.qml`, `WifiSurface.qml`, `Updates.qml`,
`Wallpaper.qml`, `Link.qml`, `BtSurface.qml`, `SysmonSurface.qml`, `Display.qml`,
`Launcher.qml`, `Media.qml`, `BatterySurface.qml`, `Clipboard.qml`, `Input.qml`,
`Look.qml`, `Appearance.qml`, `Power.qml`, `Mixer.qml`, `FontPicker.qml`,
`IdleLock.qml`, `AnimationSurface.qml`, `Settings.qml`.

One special case in `SysmonSurface.qml`: `font.pixelSize: (dial.shrink ? 16 : 20) * root.s`
→ same expression with `root.textS`.

## 3. Text-bearing subcomponents

### 3.1 Scale derives from the parent surface (no call-site change)

**`SettingsRow.qml`** — add `readonly property real textS: srow.surface ? srow.surface.textS : 1`
and its three font sites switch from `* srow.s` to `* srow.textS`.

**`IdleLock.qml`'s inner `IdleRow` component** — add
`readonly property real textS: root.textS`; its two font sites switch from
`* irow.s` to `* irow.textS`.

### 3.2 Scale passed in by callers

Each of these gains `property real textS: s` (so non-menu callers that set only
`s` keep today's behavior) and its font sites switch to `* <id>.textS`:

- `SettingsHeader.qml` — 2 sites (`* head.s`)
- `SettingsSeg.qml` — 1 site (`* seg.s`)
- `DisplayLabel.qml` — 3 sites (`* lbl.s`)
- `DisplayPicker.qml` — 1 site (`* pick.s`), plus it passes `textS: pick.textS`
  down to the two inner `DisplayLabel`s it already drives with `s: pick.s`
- `ScrubValue.qml` — 4 sites (`* root.s`)
- `SearchField.qml` — 3 sites (`* root.s`)
- `Tooltip.qml` — 2 sites (`* root.s`)
- `HFader.qml` — 1 site (`* root.s`)
- `VFader.qml` — 2 sites (`* root.s`)

Call sites inside menu surfaces add `textS: root.textS` where today they set
`s: root.s`. Non-menu callers (e.g. `Tooltip` used in the `Tray`/rest pill) are
left untouched and keep `textS == s`.

### 3.3 No internal scale

**`Marquee.qml`** uses `pixelSize` given by the caller — in `Media.qml` the three
`pixelSize: X * root.s` uses become `X * root.textS`. `Marquee.qml` itself is
unchanged.

## 4. Out of scope (must stay untouched)

- `Osd.qml`, `Toast.qml` — not `PillSurface` derived; text at `pill.s`, no bump.
- `Pill.qml` rest/hover pill, toasts, quick-record overlays (`pill.s` font sites).
- All geometry: window sizes, insets, paddings, margins, `implicitHeight`,
  `implicitWidth`, row heights, fader/button sizes.
- Icons (`GlyphIcon`), glyphs, and any `* s` non-font scaling.
- `shell.qml`, `Flags.qml`, `Look.qml` (already clean after the previous change).

## 5. Effect on content-driven heights

Settings and other content-sized surfaces measure `height: … implicitHeight + pad`.
Shrinking fonts shrinks `implicitHeight`, so those surfaces come out slightly
shorter — proportionally, coherent with smaller text. Widths (constants times
`surfaceS`) are unchanged. This is expected and accepted; no height compensation
is planned.

## 6. Validation (no local QML harness)

- Grep consistency: per menu surface file, count `font.pixelSize: …* root.textS`
  vs remaining `…* root.s` (non-font geometry stays on `s`).
- Grep: all subcomponent font sites switched to `textS`; all menu call sites pass
  `textS: root.textS`.
- Grep: `Osd`/`Toast`/`pill.s` sites and geometry untouched.
- Target-machine pass: open each menu, confirm text smaller while windows stay
  the same size; rest/hover pill and toasts unchanged.