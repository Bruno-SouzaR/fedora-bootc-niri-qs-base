# Pill hide mode default + menu sizing + integration audit — design

**Date:** 2026-08-10
**Status:** Approved
**Scope:**
- `system_files/etc/quickshell/topbar/pill/Singletons/Flags.qml`
- `system_files/etc/quickshell/topbar/pill/Look.qml`
- `system_files/etc/quickshell/topbar/pill/Pill.qml`
- New report: `docs/integrations-audit.md` (documentation only, no Containerfile/code changes)

Three requests from the user, agreed during brainstorming:

1. **Hide mode**: make smart-hide the default pill behavior; the only alternative is
   auto-hide. The two independent toggles become a single segmented selector.
2. **Menu size**: all open menu surfaces grow ~40% **without** touching the global
   scale, the rest pill, hover pill, fonts of the system or window layout. Fixed
   constant in code, no new setting.
3. **Integration audit**: a report of which programs/scripts the pill integrates
   with, which are present or missing in the image, and which break under Niri.
   Report only — no package or code fixes in this change.

---

## 1. Hide mode: smart default, single Smart|Auto selector

### Current state

`Flags.qml` persists two independent booleans (`autoHide: true`, `smartHide: false`
by default) and exposes them as aliases. `shell.qml` computes the pill's hidden /
reserve-exclusive state from them:

- `collapsed` (reserve window): `Flags.autoHide || (Flags.smartHide && fullscreen)`
- `exclusiveZone`: `(Flags.autoHide || collapsed) ? 0 : reservedH`
- `pillHidden`: `!revealWant && (Flags.autoHide || (Flags.smartHide && monFullscreen))`

`Look.qml` shows two toggle rows ("Auto hide" / "Smart hide") that can both be on at
once, which is a state the user does not want.

### Change

**`Flags.qml`**
- Replace `property alias autoHide: adapter.autoHide` and
  `property alias smartHide: adapter.smartHide` with a single persisted string:
  `property alias hideMode: adapter.hideMode` (JsonAdapter default `"smart"`).
- Keep `shell.qml` untouched by exposing two derived read-only booleans:

  ```qml
  readonly property bool autoHide: adapter.hideMode === "auto"
  readonly property bool smartHide: adapter.hideMode === "smart"
  ```

  Semantics as today: `smart` = hide only when a real fullscreen client is present
  (`Niri.fullscreenByMonitor`), `auto` = always hidden until the pointer touches the
  top edge. With smart on, the reserve window claims its exclusive zone when not
  fullscreen, so tiled windows sit below the pill; with auto it never claims it.

- Migration: a pre-existing `flags.json` carrying `autoHide`/`smartHide` is
  backward-compatible because unknown keys are ignored by the JsonAdapter; its
  `hideMode` is absent, so the adapter default `"smart"` applies. Deterministic.

**`Look.qml`** (Pill group)
- Delete the `autoHideRow` and `smartHideRow` `FieldRow`s.
- Add one `FieldRow` "Hide mode" with a `SettingsSeg` control, matching the
  existing pattern used by `layoutRow`/`nlModeRow`:

  ```qml
  SettingsSeg {
      s: root.s
      options: [{ label: "Smart", value: "smart" }, { label: "Auto", value: "auto" }]
      value: Flags.hideMode
      onPicked: v => Flags.hideMode = v
  }
  ```

- Row registry: replace the two `kind: "toggle"` entries with one
  `kind: "seg", vals: ["smart", "auto"], get: () => Flags.hideMode,
  set: v => Flags.hideMode = v`.

**Not changed:** `shell.qml` logic, Niri config, keybinds.

---

## 2. Menus 40% larger (fixed constant)

### Current state

Every open surface is a `Loader` child of the pill that receives `s: pill.s`
(`s = (monitorHeight/1080) * uiScale`). Surface target geometry comes from the
`surfaces` size table in `Pill.qml`: fixed `*W`/`*H` constants (`launcherW`, …)
multiplied by `s`, plus `+ 26*s`/`+29*s`/… paddings around each surface's
`implicitWidth`/`implicitHeight`. Internal content of every surface sizes itself
with its own `s`, so fonts, rows and paddings all scale together.

Raising the global `uiScale` is rejected: it also grows the rest pill, hover pill,
OSD/toast and scales window layout. The requirement is that only the open menus
grow.

### Change

Introduce a menu-only scale in `Pill.qml`:

```qml
readonly property real menuScale: 1.4
readonly property real surfaceS: s * menuScale
```

Apply `surfaceS` in these three places (the only reads of menu geometry):

1. **Menu constants** — change `* s` to `* surfaceS` for all of:
   `mixerH`, `launcherW/H`, `clipboardW/H`, `wallpaperW/H`, `powerW/H`, `mediaW`,
   `batteryW`, `wifiW`, `btW`, `settingsW`, `keybindsW`, `recorderW`, `sysmonW`,
   `appearanceW`, `updatesW`, `displayW`, `inputW`, `lookW`, `idlelockW`,
   `animationW`, `fontpickerW`.

   Keep `* s` for the rest/hover geometry and for the small transient pop-ups
   (which are not "menus"): `restW`, `restH`, `hoverPad`, `hoverW`, `hoverH`,
   `restCorner`, `toastW`, `quickChooseW/H`, `quickCountW/H`, `dragOverW/H`,
   `openCorner` (corner radius stays uniform so small overlays keep a sane look).

2. **`surfaces` size table** — replace the padding/fallback multipliers that use
   `s` with `surfaceS` (`36*s`, `32*s`, `26*s`, `29*s`, `33*s`, the calendar
   fallback `282*s`, and `93*Math.max(4, …)*s` in the mixer entry).

3. **Surface loaders (menu surfaces only)** — change each `ld*` Loader that is
   listed in the `surfaces` map from `s: pill.s` to `s: pill.surfaceS`, so the
   surface's internal content (fonts, rows, paddings) grows with the geometry and
   stays sharp (multiplying `s` scales font sizes; a `transform: Scale` would
   raster-blur and desync the input masks). Do NOT touch the `s: pill.s` bindings
   on `Ame`, the rest/hover rows, `Osd`, the toast loader or the quick-record /
   drag overlays — those stay at base scale.

Result: every open menu surface — geometry and content — is exactly 1.4x its former
size. Rest pill, hover pill, OSD, toast tooltips that use their own `s` from the
pill are untouched, and the window layout / global scale are untouched.

**Note on the 40% scope:** only the open menu surfaces (the `surfaces` table and
their width/height constants) grow. The OSD volume toast (`Osd.qml`), the
notification `Toast.qml`, the quick-record chooser/countdown and the AppImage
drag overlay keep their base size — they are transient pop-ups, not menu
surfaces. During implementation, if a pop-up visually breaks against the larger
pill body, it is reported but out of scope to rescale.

**Verification:** no automated QML tests exist in this repo. Validation = the shell
parses (`quickshell --path …` starts without QML errors), a surface open shows
1.4x dimensions on screen, and `flags.json` round-trips `hideMode`. The full
container build is not triggered by these edits.

---

## 3. Integration audit report — `docs/integrations-audit.md`

Documentation deliverable only. The report catalogs what the pill integrates with,
grouped as:

1. **Binaries already installed** (working): `niri`/`niri msg`, `quickshell`,
   `slurp`/`grim`, `wl-clipboard` (`wl-copy`/`wl-paste`), `cliphist`, `matugen`,
   `swaybg`, `brightnessctl`, `powerprofilesctl`, `curl`, `python3`, `gio`/`gdbus`
   (glib2), `systemctl`/`systemd-inhibit`, `pgrep`/`pkill` (procps).

2. **Binaries missing from the image** (break/module functions): `cava`
   (visualizers), `ddcutil` (DDC monitor brightness / Mixer), `gpu-screen-recorder`
   (recording), `notify-send` (`libnotify`, recording + energy-profile toast),
   `xorg-xrandr` (`Display` primary via XWayland xrandr), `bluetoothctl` (`bluez`;
   only `bluez-tools`/`bt-agent` is installed), `swww` (the Niri config spawns
   `swww-daemon`, but `swww` is not installed and `swaybg` is unused), `noctalia`
   (keyboard-backlight keybind), and to verify on base: `nmcli` (NetworkManager),
   `wpctl` (wireplumber), polkit agent path `/usr/libexec/kf6/...` vs installed
   binary. For each: package name, call sites (file:line), and what breaks.

3. **Hyprland-only references that cannot work under Niri as written**:
   `hyprctl` (Look blur/decoration reload, Input cursor, Animation reload,
   Keybinds, Display), `hypridle` (IdleLock restarts its service and rewrites
   `~/.config/hypr/hypridle.conf`), `hyprsunset` (NightLight). These need Niri
   rewrites (e.g., `niri msg` reload, gammastep/wlsunset for night light), which
   are out of scope of this change.

4. **External scripts the code shells out to, expected at
   `~/.config/hypr/scripts/` and NOT shipped** in this repo:
   `wallpaper.sh`, `wallpaper-thumbs.sh`, `wallpaper-search.sh`, `wallcolors.py`,
   `cliphist-thumbs.sh`, `rec-thumbs.sh`, `app-install.sh`, `lock.sh`,
   `ricelin-update.py`, `display-apply.sh`, plus `hypridle.conf`/`hyprsunset.conf`
   and the Hypr `modules/*.lua`. **This is why the wallpaper module opens but
   cannot list or set wallpapers**: `Walls.qml` calls the missing
   `wallpaper.sh`/`wallpaper-thumbs.sh`, and even the Niri config path is broken
   (`swww-daemon` spawned but never installed, and no image is ever set on
   startup).

The report is user-facing and written in Portuguese.

---

## Decisions taken during brainstorming

- Menu size is a **fixed constant** (`menuScale: 1.4`, one line, easy to tune);
  no new `flags.json` setting was requested.
- Hide mode is persisted as a single `hideMode` string; legacy `autoHide`/
  `smartHide` keys are ignored and the default wins.
- Integration audit is **report only**; fixing the broken programs/scripts
  (installing packages, shipping Niri-adapted scripts, rewiring wallpaper behind
  `swaybg`/`swww`) is follow-up work.

## Out of scope

- Any change to `Containerfile` or packages.
- Wiring wallpapers for Niri (backend selection, initial image, scripts).
- Rewriting `hyprctl`/`hypridle`/`hyprsunset` surfaces to Niri equivalents.
- `uiScale`, window layout, rest/hover/OSD geometry changes.