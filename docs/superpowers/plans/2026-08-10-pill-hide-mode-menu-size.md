# Pill hide-mode default, 40% menu sizing, integration audit — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make smart-hide the default pill behavior behind a single Smart|Auto selector, grow every open menu surface by a fixed 40% without touching the global scale, and deliver a documentation-only audit of the pill's external integrations.

**Architecture:** Three independent deliverable units.
1. `Flags.qml` swaps the two persisted booleans `autoHide`/`smartHide` for one persisted string `hideMode` (`"smart"` default) and exposes `autoHide`/`smartHide` as derived read-only booleans so `shell.qml` never changes. `Look.qml` replaces the two toggle rows with one `FieldRow` + `SettingsSeg` (Smart|Auto).
2. `Pill.qml` introduces `menuScale: 1.4` and `surfaceS: s * menuScale`, applied only to menu-surface geometry (constants, the `surfaces` size table, and the `ld*` surface Loaders' `s:` bindings). Rest/hover/toast/OSD/quick overlays keep `s`.
3. `docs/integrations-audit.md` is a stand-alone Portuguese report cataloguing binaries present/missing, Hyprland-only references, and missing external scripts.

**Tech Stack:** Quickshell (QML), Wayland (WlrLayershell), JSON state (`flags.json` via `JsonAdapter`). No local QML test harness exists in this repo; validation is content-based `rg` checks plus target-side manual verification.

## Global Constraints

- No changes to `Containerfile` or any installed packages (audit is report only).
- No changes to `shell.qml` at all — its reads of `Flags.autoHide`/`Flags.smartHide` must keep working unchanged.
- Menu bump is a **fixed constant** `menuScale: 1.4`; no new `flags.json` setting, no `uiScale` change.
- Only "menu surfaces" grow: the entries of the `surfaces` table in `Pill.qml`. `restW/restH/hover*`, `toastW`, `quickChooseW/H`, `quickCountW/H`, `dragOverW/H`, `openCorner`, `restCorner`, and the `s:` of `Ame`, rest/hover rows, `Osd`, the toast loader and quick/drag overlays must stay on `s`.
- Pre-existing user `flags.json` with `autoHide`/`smartHide` keys is ignored on load (unknown keys) → `hideMode` default `"smart"` wins. Deterministic; no migration code.
- Preserve each file's existing comment style and naming conventions.
- One commit per task.
- The audit report is user-facing and written in Portuguese; plan prose follows the repo's English doc convention.

---

### Task 1: Hide mode — smart default behind a single Smart|Auto selector

**Files:**
- Modify: `system_files/etc/quickshell/topbar/pill/Singletons/Flags.qml:34-35` (aliases) and `:92-93` (adapter defaults)
- Modify: `system_files/etc/quickshell/topbar/pill/Look.qml:75-76` (row registry) and `:887-907` (the two toggle FieldRows)

**Interfaces:**
- Consumes: existing `FileView`/`JsonAdapter` in `Flags.qml`; existing `SettingsSeg` component used in `Look.qml` (same directory, no import needed).
- Produces: `Flags.hideMode` (string, `"smart"` | `"auto"`, persisted), and `Flags.autoHide`/`Flags.smartHide` as derived read-only booleans preserving today's semantics. `shell.qml` keeps compiling/wiring via the same two boolean names.

- [ ] **Step 1: Replace the two flag aliases with one `hideMode` + derived booleans**

In `system_files/etc/quickshell/topbar/pill/Singletons/Flags.qml`, replace lines 34-35:

```qml
    property alias autoHide: adapter.autoHide
    property alias smartHide: adapter.smartHide
```

with:

```qml
    property alias hideMode: adapter.hideMode
    /**
     * Derived from hideMode so shell.qml keeps reading the same two booleans:
     * "smart" (default) hides only in real fullscreen, "auto" stays hidden
     * until the pointer touches the top edge.
     */
    readonly property bool autoHide: hideMode === "auto"
    readonly property bool smartHide: hideMode === "smart"
```

- [ ] **Step 2: Replace the adapter defaults**

In the same file, replace the JsonAdapter's lines 92-93:

```qml
            property bool autoHide: true
            property bool smartHide: false
```

with:

```qml
            /** "smart" hides only in real fullscreen; "auto" hides until the top edge is touched. */
            property string hideMode: "smart"
```

- [ ] **Step 3: Replace the two registry entries with one seg entry**

In `system_files/etc/quickshell/topbar/pill/Look.qml`, inside the `if (pillGrp.open)` block, replace lines 75-76:

```qml
            r.push({ item: autoHideRow, kind: "toggle", get: function () { return Flags.autoHide; }, set: function (v) { Flags.autoHide = v; } });
            r.push({ item: smartHideRow, kind: "toggle", get: function () { return Flags.smartHide; }, set: function (v) { Flags.smartHide = v; } });
```

with:

```qml
            r.push({ item: hideModeRow, kind: "seg", vals: ["smart", "auto"], get: function () { return Flags.hideMode; }, set: function (v) { Flags.hideMode = v; } });
```

- [ ] **Step 4: Replace the two toggle FieldRows with one segmented row**

Replace the `autoHideRow` and `smartHideRow` blocks (currently lines 887-907):

```qml
            FieldRow {
                id: autoHideRow
                label: "Auto hide"
                caption: "Hide the pill until the cursor touches the top edge"
                LinkToggle {
                    s: root.s
                    on: Flags.autoHide
                    onToggled: Flags.autoHide = !Flags.autoHide
                }
            }

            FieldRow {
                id: smartHideRow
                label: "Smart hide"
                caption: "Hide only in real fullscreen. Keeps the pill under Mod+F tile maximize"
                LinkToggle {
                    s: root.s
                    on: Flags.smartHide
                    onToggled: Flags.smartHide = !Flags.smartHide
                }
            }
```

with:

```qml
            FieldRow {
                id: hideModeRow
                label: "Hide mode"
                caption: "Smart hides only in real fullscreen; Auto hides until the cursor touches the top edge"
                SettingsSeg {
                    s: root.s
                    options: [{ label: "Smart", value: "smart" }, { label: "Auto", value: "auto" }]
                    value: Flags.hideMode
                    onPicked: v => Flags.hideMode = v
                }
            }
```

- [ ] **Step 5: Consistency check (no local QML tooling)**

`rg` is not installed in this environment; use `grep` (GNU grep, `-E` for regex). Run from `/var/home/brunosouzar/projects/fedora-bootc-niri-qs-base`:

```bash
grep -nE "autoHideRow|smartHideRow" system_files/etc/quickshell/topbar/pill/Look.qml
grep -rnE "Flags\.(autoHide|smartHide)" system_files/etc/quickshell/topbar/pill -g '*.qml'
grep -n "hideMode" system_files/etc/quickshell/topbar/pill/Singletons/Flags.qml system_files/etc/quickshell/topbar/pill/Look.qml
```

Expected: the first grep prints nothing (exit 1 is fine); the second prints only `shell.qml:173,178,211` (read-only reads, untouched); the third prints the alias, the two derived booleans, the adapter default and the new Look row (one `kind: "seg"` plus the `SettingsSeg` `value`/`onPicked`).

Also verify no `LinkToggle` was orphaned where it was the only use — `LinkToggle` is still used by `pillBlurRow`, so its usage stays:

```bash
grep -n "LinkToggle" system_files/etc/quickshell/topbar/pill/Look.qml
```

Expected: at least the `pillBlurRow` match remains.

- [ ] **Step 6: Commit**

```bash
git add system_files/etc/quickshell/topbar/pill/Singletons/Flags.qml system_files/etc/quickshell/topbar/pill/Look.qml
git commit -m "feat(pill): smart-hide default behind single Smart|Auto selector

Replace the independent autoHide/smartHide booleans with one persisted
hideMode string (default \"smart\": hide only in real fullscreen).
autoHide/smartHide become derived read-only booleans, so shell.qml
keeps its logic untouched. Look shows a single Smart|Auto segmented
row instead of the two toggles. Legacy flags.json keys are ignored
and the default wins."
```

---

### Task 2: Grow open menu surfaces by a fixed 40%

**Files:**
- Modify: `system_files/etc/quickshell/topbar/pill/Pill.qml`
  - insert `menuScale`/`surfaceS` properties near line 110
  - constants block `:112-152` (scale the menu widths/heights only)
  - `surfaces` size table `:177-201` (paddings/fallbacks → `surfaceS`)
  - surface Loaders `:1635-1913` (`s: pill.s` → `s: pill.surfaceS` for the 23 `ld*` menu loaders)

**Interfaces:**
- Consumes: `Pill.s` (existing, from the shell overlay); the `surfaces` map and its `surfaceItem(ld)` thunks (existing).
- Produces: `Pill.menuScale` (constant `1.4`) and `Pill.surfaceS` (`s * menuScale`). All menu-surface geometry and their loaded content now scale by `surfaceS`; everything else still scales by `s`.

- [ ] **Step 1: Add `menuScale` and `surfaceS`**

In `system_files/etc/quickshell/topbar/pill/Pill.qml`, right after the `quickCounting` line (~110):

```qml
    readonly property bool quickCounting: quickHere && ScreenRec.counting && !recorderOpen

    /**
     * Menu-only scale: open surfaces render 40% larger than the shell-derived
     * scale while the rest pill, hover pill, toasts and OSD keep `s`. The
     * surfaces table, the menu width/height constants and each menu surface's
     * `s` all multiply by this factor.
     */
    readonly property real menuScale: 1.4
    readonly property real surfaceS: s * menuScale
```

- [ ] **Step 2: Scale the menu constants to `* surfaceS`**

In the constants block (lines 112-152), keep `restW`, `restH`, `hoverPad`, `hoverW`, `hoverH`, `restCorner`, `toastW`, `quickChooseW/H`, `quickCountW/H`, `dragOverW/H`, `openCorner` on `* s`. Change every other line from `* s` to `* surfaceS` — exactly: `mixerH`, `launcherW`, `launcherH`, `clipboardW`, `clipboardH`, `wallpaperW`, `wallpaperH`, `powerW`, `powerH`, `mediaW`, `mediaH`, `batteryW`, `wifiW`, `btW`, `settingsW`, `keybindsW`, `recorderW`, `sysmonW`, `appearanceW`, `updatesW`, `displayW`, `inputW`, `lookW`, `idlelockW`, `animationW`, `fontpickerW`.

The block after edit (lines 112-151):

```qml
    readonly property real restW: 160 * s
    readonly property real restH: 38 * s
    readonly property real hoverPad: 20 * s
    readonly property real hoverW: hoverRow.implicitWidth + 2 * hoverPad
    readonly property real hoverH: 58 * s
    readonly property real mixerH: 214 * surfaceS
    readonly property real launcherW: 360 * surfaceS
    readonly property real launcherH: 332 * surfaceS
    readonly property real clipboardW: 360 * surfaceS
    readonly property real clipboardH: 332 * surfaceS
    readonly property real wallpaperW: 720 * surfaceS
    readonly property real wallpaperH: 172 * surfaceS
    readonly property real powerW: 330 * surfaceS
    readonly property real powerH: 150 * surfaceS
    readonly property real mediaW: (Players.pickable.length > 1 ? 460 : 390) * surfaceS
    readonly property real mediaH: 150 * surfaceS
    readonly property real batteryW: 316 * surfaceS
    readonly property real wifiW: 272 * surfaceS
    readonly property real btW: 286 * surfaceS
    readonly property real settingsW: 392 * surfaceS
    readonly property real keybindsW: 460 * surfaceS
    readonly property real recorderW: 384 * surfaceS
    readonly property real sysmonW: 392 * surfaceS
    readonly property real appearanceW: 392 * surfaceS
    readonly property real updatesW: 360 * surfaceS
    readonly property real displayW: 392 * surfaceS
    readonly property real inputW: 392 * surfaceS
    readonly property real lookW: 392 * surfaceS
    readonly property real idlelockW: 392 * surfaceS
    readonly property real animationW: 392 * surfaceS
    readonly property real fontpickerW: 360 * surfaceS
    readonly property real toastW: 342 * s
    readonly property real quickChooseW: 344 * s
    readonly property real quickChooseH: 76 * s
    readonly property real quickCountW: 150 * s
    readonly property real quickCountH: 64 * s
    readonly property real dragOverW: 300 * s
    readonly property real dragOverH: 126 * s
    readonly property real restCorner: 18 * s
    readonly property real openCorner: 22 * s
```

- [ ] **Step 3: Scale the `surfaces` table paddings/fallbacks to `surfaceS`**

In the `surfaces` map (lines 177-201), change only the `* s` padding/fallback terms to `* surfaceS`. `qt.size(...)` geometry terms that already read `surfaceItem(ld).implicitHeight/implicitWidth` are fine as-is. The edited entries:

```qml
        calendar:  { size: () => { const it = surfaceItem(ldCalendar); return Qt.size((it.implicitWidth > 0 ? it.implicitWidth : 282 * surfaceS) + 36 * surfaceS, it.implicitHeight + 32 * surfaceS); }, ame: () => surfaceItem(ldCalendar) },
        launcher:  { size: () => { surfaceItem(ldLauncher); return Qt.size(launcherW, launcherH); }, ame: () => surfaceItem(ldLauncher) },
        clipboard: { size: () => { surfaceItem(ldClip); return Qt.size(clipboardW, clipboardH); }, ame: () => surfaceItem(ldClip) },
        wallpaper: { size: () => { surfaceItem(ldWall); return Qt.size(wallpaperW, wallpaperH); }, ame: () => null },
        power:     { size: () => { surfaceItem(ldPower); return Qt.size(powerW, powerH); }, ame: () => surfaceItem(ldPower) },
        media:     { size: () => { surfaceItem(ldMedia); return Qt.size(mediaW, mediaH); }, ame: () => surfaceItem(ldMedia) },
        mixer:     { size: () => Qt.size(93 * Math.max(4, surfaceItem(ldMixer).faderCount) * surfaceS, mixerH), ame: () => surfaceItem(ldMixer) },
        link:      { size: () => { const it = surfaceItem(ldLink); return Qt.size(it.desiredW, it.implicitHeight + 26 * surfaceS); }, ame: () => surfaceItem(ldLink) },
        wifi:      { size: () => Qt.size(wifiW, surfaceItem(ldWifi).implicitHeight + 26 * surfaceS), ame: () => surfaceItem(ldWifi) },
        bt:        { size: () => Qt.size(btW, surfaceItem(ldBt).implicitHeight + 26 * surfaceS), ame: () => surfaceItem(ldBt) },
        battery:   { size: () => Qt.size(batteryW, surfaceItem(ldBattery).implicitHeight + 26 * surfaceS), ame: () => surfaceItem(ldBattery) },
        settings:  { size: () => Qt.size(settingsW, surfaceItem(ldSettings).implicitHeight + 29 * surfaceS), ame: () => surfaceItem(ldSettings) },
        keybinds:  { size: () => Qt.size(keybindsW, surfaceItem(ldKeybinds).implicitHeight + 29 * surfaceS), ame: () => surfaceItem(ldKeybinds) },
        recorder:  { size: () => Qt.size(recorderW, surfaceItem(ldRecorder).implicitHeight + 33 * surfaceS), ame: () => surfaceItem(ldRecorder) },
        sysmon:    { size: () => Qt.size(sysmonW, surfaceItem(ldSysmon).implicitHeight + 33 * surfaceS), ame: () => surfaceItem(ldSysmon) },
        appearance: { size: () => Qt.size(appearanceW, surfaceItem(ldAppearance).implicitHeight + 29 * surfaceS), ame: () => surfaceItem(ldAppearance) },
        updates:    { size: () => Qt.size(updatesW, surfaceItem(ldUpdates).implicitHeight + 29 * surfaceS), ame: () => surfaceItem(ldUpdates) },
        display:    { size: () => Qt.size(displayW, surfaceItem(ldDisplay).implicitHeight + 29 * surfaceS), ame: () => surfaceItem(ldDisplay) },
        input:      { size: () => Qt.size(inputW, surfaceItem(ldInput).implicitHeight + 29 * surfaceS), ame: () => surfaceItem(ldInput) },
        look:       { size: () => Qt.size(lookW, surfaceItem(ldLook).implicitHeight + 29 * surfaceS), ame: () => surfaceItem(ldLook) },
        idlelock:   { size: () => Qt.size(idlelockW, surfaceItem(ldIdlelock).implicitHeight + 29 * surfaceS), ame: () => surfaceItem(ldIdlelock) },
        animation:  { size: () => Qt.size(animationW, surfaceItem(ldAnimation).implicitHeight + 29 * surfaceS), ame: () => surfaceItem(ldAnimation) },
        fontpicker: { size: () => Qt.size(fontpickerW, surfaceItem(ldFontpicker).implicitHeight + 29 * surfaceS), ame: () => surfaceItem(ldFontpicker) }
```

- [ ] **Step 4: Scale the menu surface Loaders' `s` to `surfaceS`**

Only the 23 `ld*` Loaders whose `sourceComponent` is one of: `Mixer`, `Calendar`, `Launcher`, `Clipboard`, `Wallpaper`, `Power`, `Media`, `Link`, `WifiSurface`, `BtSurface`, `BatterySurface`, `Settings`, `Keybinds`, `Recorder`, `SysmonSurface`, `Appearance`, `Updates`, `Display`, `Input`, `Look`, `IdleLock`, `AnimationSurface`, `FontPicker`. Change each `s: pill.s` in those Loaders to `s: pill.surfaceS`. Do NOT change the `s: pill.s` on `Ame`, `MusicBars`, the rest/hover rows, `Osd`, the toast loader, or `WheelScroller` (the quick-record overlay).

- [ ] **Step 5: Consistency check (no local QML tooling)**

Run from `/var/home/brunosouzar/projects/fedora-bootc-niri-qs-base`:

```bash
grep -c "s: pill\.surfaceS" system_files/etc/quickshell/topbar/pill/Pill.qml
grep -nE "s: pill\.s\b" system_files/etc/quickshell/topbar/pill/Pill.qml
grep -nE "readonly property real (mixerH|launcherW|launcherH|clipboardW|clipboardH|wallpaperW|wallpaperH|powerW|powerH|mediaW|mediaH|batteryW|wifiW|btW|settingsW|keybindsW|recorderW|sysmonW|appearanceW|updatesW|displayW|inputW|lookW|idlelockW|animationW|fontpickerW|toastW|quickChooseW|quickChooseH|quickCountW|quickCountH|dragOverW|dragOverH|restCorner|openCorner):" system_files/etc/quickshell/topbar/pill/Pill.qml
```

Expected: first prints `23`; second prints only the 8 non-menu bindings (Ame `716`, MusicBars `1112`, hover-row pieces `1150/1255/1330`, Osd `1927`, Toast `1962`, quick-overlay WheelScroller `2111`); third prints every menu constant ending in `* surfaceS` and every non-menu constant ending in `* s`.

- [ ] **Step 6: Commit**

```bash
git add system_files/etc/quickshell/topbar/pill/Pill.qml
git commit -m "feat(pill): render open menu surfaces 40% larger

Add menuScale (1.4) and surfaceS (s * menuScale) and apply surfaceS to
the menu width/height constants, the surfaces size-table paddings and
each menu surface Loader's s. Rest/hover pill, toasts, OSD and the
quick-record overlays keep base scale; window layout and uiScale are
untouched."
```

---

### Task 3: Integration audit report (documentation only)

**Files:**
- Create: `docs/integrations-audit.md`

**Interfaces:**
- Consumes: the audit evidence gathered in `docs/superpowers/specs/2026-08-10-pill-hide-mode-menu-size-design.md` §3 and the call sites listed below.
- Produces: a stand-alone, user-facing Portuguese reference of what the pill integrates with, what is missing, and what cannot work under Niri as written. No code or package changes.

- [ ] **Step 1: Write `docs/integrations-audit.md`**

Write the file with the following content (Portuguese; adjust only call-site line numbers if greps show drift, not content):

````markdown
# Auditoria de integrações da Pill (Quickshell)

**Data:** 2026-08-10
**Escopo:** somente diagnóstico — nenhum pacote, `Containerfile` ou código foi alterado.
**Origem:** leitura estática de `system_files/etc/quickshell/topbar/pill/**` e `system_files/etc/niri/config.kdl`.

A Pill (topbar Ricelin/Quickshell) integra com programas e scripts externos. Divisão:

1. Binários já presentes na imagem (funcionando).
2. Binários **faltando** na imagem (quebram funções).
3. Referências **só-Hyprland** (não funcionam sob o Niri como estão escritas).
4. Scripts externos esperados em `~/.config/hypr/scripts/` que **não são empacotados** neste repo.
5. Explicação do caso do wallpaper.

---

## 1. Binários presentes (funcionando)

| Programa | Pacote (Containerfile) | Uso principal |
| --- | --- | --- |
| `niri` / `niri msg` | `niri` | IPC: outputs, event-stream, janelas, workspaces — `Singletons/Niri.qml`, `shell.qml` |
| `quickshell` | `quickshell` | host do topbar/lock |
| `slurp` / `grim` | `slurp`, `grim` | seleção de região de gravação (`Singletons/ScreenRec.qml`) e screenshot (`config.kdl`) |
| `wl-copy` / `wl-paste` | `wl-clipboard` | clipboard (`Singletons/Cliphist.qml`, spawms do `config.kdl`) |
| `cliphist` | `cliphist` | histórico do clipboard |
| `matugen` | `matugen` | paleta dinâmica (via `wallcolors.py`) — `Singletons/Dyn.qml` |
| `swaybg` | `swaybg` | instalado, mas **não usado** (o `config.kdl` manda iniciar `swww-daemon`) |
| `brightnessctl` | `brightnessctl` | brilho de tela (`Singletons/Backlight.qml`, binds `config.kdl`) |
| `powerprofilesctl` | `power-profiles-daemon` | perfil de energia (bind `config.kdl`) |
| `curl` | `curl` | clima (`Singletons/Weather.qml`) |
| `python3` | base | engine de updates (`Updates.qml`) e `wallcolors.py` (`Appearance.qml`) |
| `gio` / `gdbus` | glib2 (base) | `gio trash`/lixeira de wallpaper (`Walls.qml`), toast de update (`shell.qml`) |
| `systemctl` / `systemd-inhibit` | systemd | inibição idle/keep-awake (`shell.qml`) |

## 2. Binários faltando (quebram funções)

| Programa | Pacote sugerido | Onde é chamado | O que quebra |
| --- | --- | --- | --- |
| `cava` | `cava` | `pill/Singletons/Cava.qml`, `lock/Singletons/Cava.qml` | visualizer de áudio (pill em repouso + lock); sem ele o `command -v cava` falha e o visualizer fica mudo |
| `ddcutil` | `ddcutil` | `pill/Singletons/Devices.qml:76,101`, `pill/Mixer.qml:522` | brilho DDC / faders de monitor externo no Mixer |
| `gpu-screen-recorder` | `gpu-screen-recorder` (COPR) | `pill/Singletons/ScreenRec.qml:233,260,460` | gravação de tela inteira (window/region) e o `pgrep` de status |
| `notify-send` | `libnotify` | `pill/Singletons/ScreenRec.qml:382,402`, bind energia do `config.kdl` | notificações nativas de gravação salva/falha e perfil de energia |
| `xrandr` | `xorg-xrandr` | `pill/Display.qml:351,353` | definir monitor primário via XWayland (`xrandr --output … --primary`) |
| `bluetoothctl` | `bluez` | `pill/BtSurface.qml:138` | fluxo pair/trust/connect de dispositivos Bluetooth (nota: o `Containerfile` instala só `bluez-tools`, que fornece `bt-agent` — `bluetoothctl` é do pacote `bluez`) |
| `swww` | `swww` (COPR) | `config.kdl` linha 30 (`spawn-at-startup "swww-daemon"`) | daemon de wallpaper do Niri não existe → spawn falha; nenhum papel de parede é desenhado |
| `noctalia` | `noctalia` (GitHub) | `config.kdl` binds `XF86KbdBrightness*` | brilho do teclado retroiluminado |
| `nmcli` | `NetworkManager` | `pill/WifiSurface.qml` (vários) | **verificar no base**: a família ublue-base normalmente inclui NetworkManager; se faltar, Wi-Fi inteiro quebra |
| `wpctl` | `wireplumber` | binds de áudio do `config.kdl` | **verificar no base**: sessão de som |
| polkit agent | `polkit-kde-agent-1` | `config.kdl` linha 39 (`/usr/libexec/kf6/…`) | **verificar caminho**: no Fedora o binário costuma ser `/usr/libexec/polkit-kde-authentication-agent-1` |

## 3. Referências só-Hyprland (não funcionam sob o Niri)

Esses programas pertencem ao Hyprland e **não existem** nesta imagem (que usa Niri). As superfícies que os chamam ficam inertes ou falham silenciosamente — precisariam de reescrita (fora do escopo):

| Ferramenta | Onde | Função hoje |
| --- | --- | --- |
| `hyprctl` | `Look.qml:316,324`, `Input.qml:230,240`, `AnimationSurface.qml:134`, `Keybinds.qml:307`, `Display.qml:288`, `Appearance.qml:62,69` | reload/regras/blur/cursor/decoração |
| `hypridle` | `IdleLock.qml:95`, `~/.config/hypr/hypridle.conf` | idle/lock (no Niri o certo é `swayidle` ou equivalente + `niri msg` idle inhibit) |
| `hyprsunset` | `Singletons/NightLight.qml:162`, `~/.config/hypr/hyprsunset.conf` | night light (no Niri o certo é gammastep/wlsunset) |

## 4. Scripts externos esperados (não empacotados neste repo)

A Pill chama scripts em `~/.config/hypr/scripts/` (na instalação Ricelin original). Este repo bootc **não os distribui** — em boot limpo eles não existem, então os módulos que dependem deles abrem mas não funcionam:

| Script | Onde é chamado | Módulo afetado |
| --- | --- | --- |
| `wallpaper.sh` | `Singletons/Walls.qml:40,72,98` | Wallpaper (set/resolve) |
| `wallpaper-thumbs.sh` | `Singletons/Walls.qml:39,123` | Wallpaper (miniaturas 512px) |
| `wallpaper-search.sh` | `Wallpaper.qml:276` | Wallpaper (busca) |
| `wallcolors.py` | `Appearance.qml:62,69`, paleta `Dyn.qml` | cores dinâmicas |
| `cliphist-thumbs.sh` | `Singletons/Cliphist.qml:30,121` | Clipe histórico (miniaturas) |
| `rec-thumbs.sh` | `Singletons/ScreenRec.qml:49,408` | Gravações recentes (miniaturas) |
| `app-install.sh` | `Launcher.qml:50`, `Pill.qml:811` | instalar AppImage arrastada |
| `lock.sh` | `Power.qml:50`, `IdleLock.qml:25` | bloquear tela |
| `ricelin-update.py` | `Updates.qml:31,257,276` | sistema de updates |
| `display-apply.sh` | `Display.qml:44,326` | aplicar configuração de monitores |
| `hypridle.conf`, `hyprsunset.conf`, `modules/*.lua` | `IdleLock.qml`, `NightLight.qml`, Look/Input/Animation/Keybinds | persistência Hyprland |

## 5. Por que o wallpaper abre mas não lista/seta imagens

Cadeia do módulo Wallpaper (`Singletons/Walls.qml`):

1. `refresh()` → `resolveProc` roda `bash wallpaper.sh resolve` → o script **não existe** (item 4) → falha.
2. `thumbProc` roda `sh wallpaper-thumbs.sh` → idem.
3. `listProc` faz `find` na pasta resolvida (`~/Ricelin/wallpapers` padrão) → se a pasta não existir, `entries` fica vazio.
4. `stateProc` lê `~/.local/state/ricelin-wallpaper` → vazio → `current` sem valor.

Mesmo que os scripts existissem, o **Niri não desenharia o wallpaper**: o `config.kdl` inicia `swww-daemon` (pacote `swww` não instalado — item 2) e **nunca** executa `swww img <arquivo>` nem `swaybg <arquivo>` no startup. Ou seja: backend não instalado + nenhuma imagem inicial.

**Ação manual sugerida (fora do escopo deste trabalho):**
- Escolher backend: `swaybg` (já instalado) ou instalar `swww`.
- Adicionar no `config.kdl` um `spawn-at-startup` para setar a imagem (ex.: `spawn-at-startup "swaybg" "-i" "/caminho/para/imagem"`).
- Criar/portar `wallpaper.sh`, `wallpaper-thumbs.sh`, `wallpaper-search.sh` e `wallcolors.py` para este repo (ou apontar `Walls.qml`/`Appearance.qml` para scripts próprios do Niri), ajustando o backend e o caminho de cores para `matugen`.

## 6. Resumo das ações manuais possíveis

- **Instalar (Containerfile):** `ddcutil`, `cava`, `gpu-screen-recorder`, `libnotify`, `xorg-xrandr`, `bluez`, `swww` (ou usar `swaybg`), `noctalia`; conferir `NetworkManager`/`wireplumber`/caminho do polkit no base.
- **Reescrever para Niri (fora do escopo):** `hyprctl`/`hypridle`/`hyprsunset` → `swayidle` + `gammastep`/`wlsunset` + IPC `niri`.
- **Ship de scripts:** portar os `~/.config/hypr/scripts/*` e configs para o fluxo Niri, ou substituir por equivalentes.
````

- [ ] **Step 2: Consistency check**

Run from `/var/home/brunosouzar/projects/fedora-bootc-niri-qs-base`:

```bash
test -s docs/integrations-audit.md && echo ok
grep -nE "wallpaper\.sh|swww|ddcutil|cava|gpu-screen-recorder|hyprctl|noctalia" docs/integrations-audit.md | wc -l
```

Expected: `ok` and a count of 10 or more (every missing program/script named).

- [ ] **Step 3: Commit**

```bash
git add docs/integrations-audit.md
git commit -m "docs: pill integration audit (programs, scripts, niri gaps)

Documents which binaries the pill NEEDS (present vs missing), which
Hyprland-only references cannot work under Niri as written, and which
external scripts under ~/.config/hypr/scripts are not shipped by this
repo -- including the root cause of the wallpaper module listing and
setting nothing."
```

---

## Self-review notes (run by the plan author)

- **Spec coverage:** §1 (hide mode) → Task 1; §2 (40% menus) → Task 2; §3 (audit/report) → Task 3. Global constraints keep `shell.qml`, `Containerfile`, `uiScale` untouched and confine the 40% to menu surfaces only.
- **Type/property consistency:** `Flags.hideMode` is the single new persisted key (default `"smart"`); `Flags.autoHide`/`smartHide` remain boolean names with identical meaning for `shell.qml`. `Pill.surfaceS` is used only where the spec lists it; `menuScale` referenced only by `surfaceS`. No cross-task signature drift.
- **Placeholders:** all steps embed the exact code/commands/content to write. The report content is fully inlined in Task 3.
- **Validation lane:** no local QML harness — every task ends in content-based `rg` checks plus a target-machine manual pass (open each menu → ~1.4x; Look → Pill → "Hide mode" Smart/Auto; edit `flags.json` and reload → `hideMode` round-trips; verify fullscreen hides pill only in Smart).