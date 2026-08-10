# Auto-hide Behavior Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix three auto-hide pill behaviors in `shell.qml`: flickering reveal strip, window push-down on click, and popups (OSD/toast) staying hidden.

**Architecture:** All changes live in one file, `system_files/etc/quickshell/topbar/pill/shell.qml`. Three independent edits: (1) a flush 14px reveal strip plus a union input mask (`revealRegion`) that keeps the pointer inside the input region during reveal; (2) the `reserve` window stops claiming an exclusive zone when `Flags.autoHide` is on; (3) `revealWant` also triggers on `pill.osdActive` and focused-monitor toasts so popups reveal the pill briefly.

**Tech Stack:** Quickshell (QML), WlrLayershell (Wayland). Quickshell `Region` supports nested children with `Intersection.Combine` (the default) for union masks.

## Global Constraints

- Only modify `system_files/etc/quickshell/topbar/pill/shell.qml`. Do not touch `Pill.qml`, `Osd.qml`, `Toast.qml`, or any `Singletons/*`.
- The three edits are independent and can be committed separately (one commit per task).
- Preserve the existing comment style/naming conventions in `shell.qml`.
- Auto-hide (`Flags.autoHide`) on means "pill floats over windows, never reserves space"; always-visible mode (`autoHide` off) and `smartHide` keep today's behavior.
- Toast popups reveal only the pill on the **focused** monitor; OSD already gates per monitor via `Osd.onFocusedMonitor`.
- There is no local QML test harness (no `quickshell`/`qmllint` in this environment); validation is manual on the target plus strict file-consistency checks in this repo.

---

### Task 1: Flush 14px reveal strip with flicker-free union mask

**Files:**
- Modify: `system_files/etc/quickshell/topbar/pill/shell.qml:225-244`

**Interfaces:**
- Consumes: `overlay.width`, `pillRegion` (existing), `pillHidden`, `modal` (existing booleans on the `overlay` PanelWindow).
- Produces: `hiddenStripRegion` (flush, 14px tall) and `revealRegion` (union of strip + `pillRegion`), used in the `mask` expression.

- [ ] **Step 1: Edit `mask` binding and region definitions**

Replace the current `mask` line and the `hiddenStripRegion` / `pillRegion` / `fullRegion` block (shell.qml:225-244) with:

```qml
            mask: pillHidden ? hiddenStripRegion : (modal ? fullRegion : revealRegion)
            Region {
                id: hiddenStripRegion
                y: 0
                width: overlay.width
                height: 14 * s
            }
            Region {
                id: pillRegion
                readonly property real baseW: Math.max(pill.width, pill.targetW)
                x: pill.x + (pill.width - baseW) / 2
                y: pill.y
                width: baseW + pill.inputPadRight
                height: Math.max(pill.height, pill.targetH)
            }
            Region {
                id: revealRegion
                Region {
                    y: 0
                    width: overlay.width
                    height: 14 * s
                }
                Region {
                    x: pillRegion.x
                    y: pillRegion.y
                    width: pillRegion.width
                    height: pillRegion.height
                }
            }
            Region {
                id: fullRegion
                width: overlay.width
                height: overlay.height
            }
```

Note: `pillRegion` keeps its original geometry exactly; `revealRegion` reuses it via `x/y/width/height` bindings so the union tracks the live pill rect.

- [ ] **Step 2: Consistency check (no local QML tooling)**

Run:
```bash
cd /var/home/brunosouzar/projects/fedora-bootc-niri-qs-base
git diff system_files/etc/quickshell/topbar/pill/shell.qml
```
Expected: only the `mask` line and the region block changed; the `hiddenStripRegion` inner `Region` now reads `y: 0`/`height: 14 * s`; `pillRegion` block unchanged in geometry; a new `revealRegion` block between `pillRegion` and `fullRegion`.

- [ ] **Step 3: Commit**

```bash
git add system_files/etc/quickshell/topbar/pill/shell.qml
git commit -m "fix(pill): flush 14px reveal strip with union input mask

hiddenStripRegion was at y:-4 with only ~3px on screen; revealing
switched the mask to pillRegion, dropping the pointer out of the
input region and flickering the pill open/closed. Make the strip
flush (y:0) and double its height (14px), and introduce
revealRegion - a Combine union of the top strip and pillRect -
so the pointer stays inside the input mask while the pill expands."
```

---

### Task 2: No exclusive-zone push on click in auto-hide

**Files:**
- Modify: `system_files/etc/quickshell/topbar/pill/shell.qml:178`

**Interfaces:**
- Consumes: `collapsed` (existing computed property on the `reserve` PanelWindow), `Flags.autoHide` (singleton).
- Produces: `exclusiveZone` no longer claims space when `Flags.autoHide` is true; `implicitHeight` stays as-is (derived from `collapsed`).

- [ ] **Step 1: Edit `exclusiveZone`**

Replace `shell.qml:178`:

```qml
            exclusiveZone: collapsed ? 0 : reservedH
```

with:

```qml
            exclusiveZone: (Flags.autoHide || collapsed) ? 0 : reservedH
```

- [ ] **Step 2: Consistency check**

Run:
```bash
cd /var/home/brunosouzar/projects/fedora-bootc-niri-qs-base
git diff system_files/etc/quickshell/topbar/pill/shell.qml
```
Expected: exactly one line changed on the `reserve` PanelWindow (`exclusiveZone`), and nothing else in this task's diff besides the Task 1 changes already committed.

- [ ] **Step 3: Commit**

```bash
git add system_files/etc/quickshell/topbar/pill/shell.qml
git commit -m "fix(pill): never claim exclusive zone in auto-hide

An open surface set collapsed=false, so the reserve window grabbed
~46px and pushed tiled windows down on click while hover kept them
put. In auto-hide the pill now always floats over windows (like
hover); always-visible and smart-hide modes are unchanged."
```

---

### Task 3: Reveal pill for OSD flashes and focused-monitor toasts

**Files:**
- Modify: `system_files/etc/quickshell/topbar/pill/shell.qml:207`

**Interfaces:**
- Consumes: `pill.osdActive`, `pill.toastActive` (readonly props on `Pill.qml:98-99`), `Niri.focusedMonitorName` (singleton, `Singletons/Niri.qml`), `modelData.name`.
- Produces: `revealWant` turns true on popups so `pillHidden` releases; the pill descends, morphs to `osd`/`toast` mode (existing `Pill.qml` machinery), and rises again when the flash/timer ends.

- [ ] **Step 1: Edit `revealWant`**

Replace `shell.qml:207`:

```qml
            readonly property bool revealWant: pill.hovered || pill.held || surfaceOpen || pill.quickChoosing || root.peekMon === modelData.name
```

with:

```qml
            readonly property bool revealWant: pill.hovered || pill.held || surfaceOpen || pill.quickChoosing
                || root.peekMon === modelData.name
                || pill.osdActive
                || (pill.toastActive && Niri.focusedMonitorName === modelData.name)
```

- [ ] **Step 2: Consistency check**

Run:
```bash
cd /var/home/brunosouzar/projects/fedora-bootc-niri-qs-base
git diff system_files/etc/quickshell/topbar/pill/shell.qml
```
Expected: only the `revealWant` property changed in this task; `Niri` is already imported (shell.qml:6) and `Niri.focusedMonitorName` is already used (shell.qml:92), so no new imports.

- [ ] **Step 3: Commit**

```bash
git add system_files/etc/quickshell/topbar/pill/shell.qml
git commit -m "fix(pill): reveal pill for OSD and focused-monitor toasts

The hidden pill (opacity 0 + translate up) also hid its OSD flash
and toast loader. revealWant now includes osdActive, and toasts
(global Notifs.popups) reveal only the focused monitor's pill, so
volume/brightness/media/Bluetooth popups show in auto-hide and the
pill rises again when the flash or toast timer ends."
```

---

## Manual validation on target

After all three commits are applied on the target (quickshell reload):

1. Move the pointer over the top edge: the pill reveals from the flush 14px strip and stays open while the pointer remains in the strip band or over the pill; no rapid open/close flicker. It hides ~300ms after the pointer leaves both regions.
2. Click a tray/settings icon: the surface expands **over** open apps; tiled windows do not move. Close the surface: windows remain where they were.
3. Change volume, brightness, switch workspace/player, or pair a Bluetooth device with the pill auto-hidden: the OSD/toast descends on the focused monitor, shows, and the pill rises again at the end.
4. Toggle `autoHide` off in `~/.local/state/ricelin/flags.json` and confirm the pill still reserves its band (windows tile below it) as before.

## Self-review notes

- Spec coverage: Problem 1 (strip+flicker) → Task 1; Problem 2 (push-down) → Task 2; Problem 3 (popups) → Task 3. Interaction matrix rows are all covered by the three tasks.
- No placeholders; all edits are concrete.
- Type consistency: `revealRegion`, `hiddenStripRegion`, `pillRegion`, `fullRegion`, `revealWant`, `exclusiveZone` names match between tasks and this plan.