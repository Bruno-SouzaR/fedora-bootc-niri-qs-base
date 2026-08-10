# Auto-hide behavior fixes — design

**Date:** 2026-08-09
**Status:** Approved
**Scope:** `system_files/etc/quickshell/topbar/pill/shell.qml` (+ reading of `Pill.qml`/`Osd.qml`/`Singletons/Niri.qml`, no edits there)

Fixes three behaviors of the pill in auto-hide that the user found wrong while
testing on target: a flickering reveal strip, an unwanted window push-down on
click, and popups (OSD/toast) staying hidden with the pill.

---

## Problem 1: flicker and contact area of the auto-hide reveal strip

### Root cause

`hiddenStripRegion` is declared as `y: -4*s, height: 7*s`, so only ~3px of it
are actually on screen. When the pointer hits the strip, `pill.hovered` goes
true and the pill reveals: the overlay `mask` switches from `hiddenStripRegion`
to `pillRegion`. `pillRegion` covers only the pill rect (its top starts at
`topGap`, 8px), so a pointer that was just inside the 3px strip is now outside
the input region → `hovered` drops → the pill hides → the mask flips back to the
strip → the pointer is again inside → `hovered` rises again: a flicker loop.

### Fix

- `hiddenStripRegion`: `y: 0`, `height: 14*s`, keep full width. Flush against
  the top of each monitor and double the current size downward, per user choice.
- New `revealRegion`: a `Region` whose nested children combine (Quickshell
  `Region` supports nesting with `Intersection.Combine`, the default) the top
  contact strip (`0..14*s`, full monitor width) **union** `pillRegion`. Use it
  as the mask while revealed and non-modal:
  `mask: pillHidden ? hiddenStripRegion : (modal ? fullRegion : revealRegion)`.
- Because the revealed mask keeps covering the strip, the pointer stays inside
  the input region while the pill is expanding, so `hovered` never drops during
  the transition. Hover is lost only when the pointer leaves both the strip
  band and the pill; the existing 300ms `graceTimer` already handles the
  delayed latch release.

### Files

- `system_files/etc/quickshell/topbar/pill/shell.qml`

---

## Problem 2: clicking a surface pushes windows down

### Root cause

A second PanelWindow (`reserve`) claims an exclusive zone:
`exclusiveZone: collapsed ? 0 : reservedH` (≈46px), where
`collapsed` becomes false as soon as a surface opens on the monitor
(`root.openMon === modelData.name`). On hover nothing is open so `collapsed`
stays true → no push; on click a surface opens → push. The user wants the same
overlay behavior in both cases.

### Fix

In auto-hide, never claim the exclusive zone — the pill always floats over
windows, identical to hover:

```
exclusiveZone: (Flags.autoHide || collapsed) ? 0 : reservedH
```

- `Flags.autoHide` on → always `0` (pill, pinned state, peek and open surfaces
  all overlay).
- Always-visible mode (`autoHide` off) and `smartHide` keep today's behavior.

### Files

- `system_files/etc/quickshell/topbar/pill/shell.qml`

---

## Problem 3: popups (OSD / toast) invisible in auto-hide

### Root cause

The hidden pill gets `opacity: 0` and a `Translate{ y: -(...) }` (shell.qml
366-375), which also hides its children: the OSD flash and the toast loader.
`revealWant` does not include `osdActive` / `toastActive`, so a volume/brightness
flash or a media/Bluetooth toast fires while the pill is hidden → nothing shows.

### Fix

Extend `revealWant` so a popup briefly reveals the pill (it descends, morphs to
`osd` / `toast` mode, shows the popup, then rises again when the flash/timer
ends — reusing the existing morph machinery):

```
revealWant: pill.hovered || pill.held || surfaceOpen || pill.quickChoosing
    || root.peekMon === modelData.name
    || pill.osdActive
    || (pill.toastActive && Niri.focusedMonitorName === modelData.name)
```

- OSD already self-gates per monitor via `Osd.onFocusedMonitor`, so each pill
  only reveals for its own monitor's flash.
- Toast popups (`Notifs.popups`) are global, so reveal is gated to the focused
  monitor's pill only, per user choice.

### Files

- `system_files/etc/quickshell/topbar/pill/shell.qml`

---

## Interaction matrix (post-fix, auto-hide on)

| Trigger                          | Pill behavior                                  |
| -------------------------------- | ---------------------------------------------- |
| Pointer on 14px top strip        | Reveals, stays while inside strip or pill      |
| Hover pill body                  | Reveals (unchanged)                            |
| Click icon → surface opens       | Grows over apps; windows do not move           |
| Pin / peek                       | Overlay; windows do not move                   |
| Volume/brig/ws/player OSD flash  | Pill descends, shows OSD, rises on end         |
| Toast notification               | Pill on focused monitor descends, shows, rises |
| Fullscreen (smartHide only)      | Retracts (unchanged by Problem 2 fix)          |

## Non-goals

- No changes to `Pill.qml`, `Osd.qml`, `Toast.qml`, data singletons.
- No new windows; the pill/overlay/reserve trio stays.
- `smartHide` + always-visible behavior is intentionally untouched.

## Validation

Manual on target after implementation:

1. Move pointer over the top edge strip — pill reveals without flicker while the
   pointer stays in the strip band; hides soon after leaving.
2. Click a tray/settings icon → surface expands over open apps without pushing
   the tiled windows down; close returns windows unchanged.
3. Change volume (brightness / track / Bluetooth connect) while pill auto-hidden
   → OSD/toast appears and fades; end state is hidden pill again.
4. Re-check in always-visible mode that the pill still reserves its band.