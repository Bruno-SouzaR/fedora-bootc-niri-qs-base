# Migração da Pill quickshell para IPC do niri — Implementation Plan

> **Para agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recomendado) or superpowers:executing-plans para implementar este plano tarefa por tarefa. Passos usam checkbox (`- [ ]`) para rastreio.

**Goal:** Migrar completamente a pill quickshell ("Washi") de `Quickshell.Hyprland` para o IPC do niri, com auto-hide/smart-hide e remoção de gameMode/stash/espaços especiais.

**Architecture:** Um singleton `Niri` novo se torna a única fonte do estado do compositor: um `Process` com `niri msg --json event-stream` + `SplitParser` mantém os estados sempre frescos (só um socket por processo → queries/ações rodam em um segundo `Process` one-shot), e a ocultação é dirigida por dois flags (`autoHide`/`smartHide`) computando `pillHidden`. Fullscreen real é detectado por heurística geométrica (janela focada cobre o `LogicalOutput` do monitor + sem margem de coluna).

**Tech Stack:** Quickshell (QML6), niri IPC (niri-msg 26.4.0), node (testes JS puros .mjs), JSON via serde externally-tagged.

## Global Constraints

- niri-ipc **26.4.0**; não assumir campos extras (novos fields em patch releases podem quebrar; parse tolerante).
- Correr em niri + quickshell no **sistema alvo**; o host de dev não tem `quickshell`/`niri`/`node`/`jq` → verificação de QML só no alvo.
- `niri msg --json <query>` imprime o **payload interno** (sem wrapper `Response`/`Ok`): `workspaces` → array de `Workspace`, `windows` → array de `Window`, `outputs` → objeto `{nome: Output}`, `focused-output` → um `Output` ou `null`.
- `niri msg --json event-stream`: uma linha por evento, serde **externally-tagged** (`{"WorkspacesChanged":{"workspaces":[...]}}`).
- Event stream entrega o estado completo logo no início (`WorkspacesChanged`/`WindowsChanged` etc., snapshots completos) e mantém workspaces/windows frescos → NÃO é preciso re-query no connect para workspaces/windows. Só a query `outputs` (que não tem evento) roda no connect via `outputsProc`; `windows` é re-query one-shot (`requeryWindows`) nos eventos de janela que não trazem payload completo.
- `Window` **não** tem `is_fullscreen`; `Action` não tem `fullscreen-window --set`; `Mod+F` (maximize-column) NÃO é fullscreen — só `Mod+Shift+F` (`Action::FullscreenWindow` toggle) é.
- **Por que a geometria distingue fullscreen de maximize:** o `reserve` panel reserva `exclusiveZone: reservedH` no topo; em niri o *workspace view* (e o maximize-column) respeita exclusive zones de layer-shell, então uma janela maximizada termina com `window_size` ≡ *output − reservedH − gaps* (não cobre o output). Fullscreen real (`fullscreen-window`) IGNORA exclusive zones e gaps e cobre o `logical` inteiro → `window_size` ≈ `logical`. A heurística separa os dois com **tolerância de 1px por lado** (2px total por eixo em `window_size`, 1px no deslocamento `tile_pos_in_workspace_view`). (Se em algum momento `reservedH` for 0 e o user maximizar com `Mod+F`, a geometria colide — mitigado: `gaps 4` + default column-width 0.5 seguram a diferença; na prática o filtro é para vídeo/game fullscreen, que preenche o output.)
- `Action::Quit { skip_confirmation }` → `niri msg action quit --skip-confirmation` (não pode esperar stdin no Process).
- `Action::FocusWorkspace { reference }` → `niri msg action focus-workspace <idx-u8>| <name>` (o FromStr aceita índice numérico ou nome; **não** aceita id).
- `Action::FocusWindow { id: u64 }` → `niri msg action focus-window --id <id>`.
- Remover **somente** o que este plano lista. `lib/binds.js`, `lib/fuzzy.js`, `lib/keychord.js` ficam (usados por Keybinds.qml/Launcher.qml).
- Não editar `config.kdl`; não deletar `Display.qml`/`Keybinds.qml`/`Look.qml`/`Input.qml`/`IdleLock.qml`/`AnimationSurface.qml`/`NightLight.qml`/`Appearance.qml`/`FontPicker.qml` (ficam inertes).
- Código novo sem comentários de martelo; seguir o estilo dos arquivos vizinhos (comentários `/** */` explicativos onde fizer sentido).

---

## File Structure

**Criados:**
- `system_files/etc/quickshell/topbar/pill/Singletons/Niri.qml` — singleton: stream + estado (workspaces/windows/outputs) + derivados (`focusedMonitorName`, `activeWorkspace`, `workspaceList`, `isFullscreen`) + ações (`focusWorkspace`, `focusWindow`, `quit`).
- `system_files/etc/quickshell/topbar/pill/lib/fullscreen.js` — heurística pura testável (cobb/geometria), importada no Niri.qml e no node.
- `system_files/etc/quickshell/topbar/pill/lib/fullscreen.test.mjs` — testes node do fullscreen.

**Editados:**
- `Singletons/qmldir` — +Niri, −GameMode/−Spaces/−Workspacerules.
- `Singletons/Flags.qml` — +autoHide/+smartHide; −gameMode/−gamePrevDonald* (+gamePrevProfile).
- `shell.qml` — import; `refresh()`; onCompleted; Connections Hyprland; toggleSurface; minimize/restoreWindow; `pillHidden`; exclusiveZone colapsável; monFullscreen→Niri.
- `Pill.qml` — specialView; surfaces map (removes entries stash/spaceapps/workspaces; keybinds/appearance/... KEEP); loaders removidos (ldStash, ldSpaceapps, ldWorkspaces); MinimizedTray; game* refs; mask; `hiddenStripRegion`.
- `Mixer.qml` — remover chip gameMode (344-347).
- `Look.qml` — toggles autoHide/smartHide no grupo Pill.
- `Settings.qml` — remover rows display/keybinds/workspaces.
- `Workspaces.qml` — dots via Niri (range, activeName, clique).
- `Osd.qml` — activeWsName/onFocusedMonitor via Niri.
- `Power.qml` — logout via Niri.quit.
- `Singletons/Notifs.qml` — raiseWindow via Niri windows + focus-window.
- `launcher/shell.qml` — remover import Quickshell.Hyprland.

**Removidos:**
- `Singletons/GameMode.qml`, `Singletons/Spaces.qml`, `Singletons/Workspacerules.qml`
- `MinimizedTray.qml`, `Stash.qml`, `WorkspacesSurface.qml`, `SpaceApps.qml`, `AppPickerList.qml`
- `lib/monitors.js`, `lib/monitors.test.mjs`

---

### Task 1: Helper JS puro `lib/fullscreen.js` com heurística geométrica

**Files:**
- Create: `system_files/etc/quickshell/topbar/pill/lib/fullscreen.js`
- Test: `system_files/etc/quickshell/topbar/pill/lib/fullscreen.test.mjs`

**Interfaces:**
- Produces: top-level `function isFullscreenCovering(windowLayout, logicalOutput)` → bool. `windowLayout` é `{ window_size: [i32,i32], tile_pos_in_workspace_view: [f64,f64] }`; `logicalOutput` é `{ width, height }` (u32). Usado por Niri.qml e pelo test.
- Produces: `if (typeof module !== "undefined" && module.exports) module.exports = { isFullscreenCovering };` (mesmo padrão de `lib/monitors.js`).

- [ ] **Step 1: Write the failing test**

```js
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const { isFullscreenCovering } = require("./fullscreen.js");

let failed = 0;
function eq(actual, expected, msg) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) console.log("PASS " + msg);
  else { failed++; console.log("FAIL " + msg + "\n  expected " + e + "\n  got      " + a); }
}

const fullLayout = { window_size: [1920, 1080], tile_pos_in_workspace_view: [0, 0] };
const output1920x1080 = { width: 1920, height: 1080 };

eq(isFullscreenCovering(fullLayout, output1920x1080), true, "exact cover is fullscreen");
const column = { window_size: [1280, 1080], tile_pos_in_workspace_view: [320, 0] };
eq(isFullscreenCovering(column, output1920x1080), false, "smaller width not fullscreen");
const margined = { window_size: [1918, 1080], tile_pos_in_workspace_view: [0, 0] };
eq(isFullscreenCovering(margined, output1920x1080), true, "1px tolerance still fullscreen");
const offset = { window_size: [1920, 1080], tile_pos_in_workspace_view: [2, 0] };
eq(isFullscreenCovering(offset, output1920x1080), false, "tile x offset means column margin");
eq(isFullscreenCovering(null, output1920x1080), false, "null layout not fullscreen");
eq(isFullscreenCovering(fullLayout, null), false, "null output not fullscreen");
eq(isFullscreenCovering({ window_size: [1920, 1080], tile_pos_in_workspace_view: null }, output1920x1080), true, "missing tile pos still fullscreen (floating)");
eq(isFullscreenCovering({ window_size: [1920, 1080], tile_pos_in_workspace_view: [0, null] }, output1920x1080), true, "null x in tile pos still fullscreen");

if (failed > 0) { console.error(failed + " tests failed"); process.exit(1); }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node lib/fullscreen.test.mjs` (em `system_files/etc/quickshell/topbar/pill`; se `node` não existe no host, pular — o arquivo é void no CI, só roda no alvo)
Expected: FAIL com "function isFullscreenCovering is not defined" (module vazio). Se o host não tem node, anote "não verificável aqui — testar no alvo".

- [ ] **Step 3: Write minimal implementation**

```js
const TOLERANCE = 1;

function isFullscreenCovering(windowLayout, logicalOutput) {
    if (!windowLayout || !logicalOutput)
        return false;
    var ws = windowLayout.window_size;
    if (!ws)
        return false;
    if (Math.abs(ws[0] - logicalOutput.width) > 2 * TOLERANCE)
        return false;
    if (Math.abs(ws[1] - logicalOutput.height) > 2 * TOLERANCE)
        return false;
    var tp = windowLayout.tile_pos_in_workspace_view;
    if (tp && tp.length >= 1 && tp[0] !== null && Math.abs(tp[0]) > TOLERANCE)
        return false;
    return true;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { isFullscreenCovering };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node lib/fullscreen.test.mjs` (no alvo se host sem node)
Expected: PASS em todos os 8 casos.

- [ ] **Step 5: Commit**

```bash
git add system_files/etc/quickshell/topbar/pill/lib/fullscreen.js system_files/etc/quickshell/topbar/pill/lib/fullscreen.test.mjs
git commit -m "test(lib): fullscreen geometric heuristic for niri"
```

---

### Task 2: Singleton `Niri.qml` (stream + estado + ações) e qmldir

**Files:**
- Create: `system_files/etc/quickshell/topbar/pill/Singletons/Niri.qml`
- Modify: `system_files/etc/quickshell/topbar/pill/Singletons/qmldir` (adiciona `singleton Niri Niri.qml` antes de `singleton Workspacerules`)
- Consumes: `lib/fullscreen.js` (`import "lib/fullscreen.js" as Fullscreen` — caminho relativo a partir de `Singletons/`, então `../lib/fullscreen.js`).

**Interfaces:**
- Consumes: `Fullscreen.isFullscreenCovering(layout, logical)` da Task 1.
- Produces (usados por Tasks 4, 5, 8, 10, 11):
  - `readonly property string focusedMonitorName` — nome do output focado (de `workspaces` onde `is_focused`), `""` se nenhum.
  - `function workspaceList(mon)` → `Array<Workspace>` ordenado por `idx`.
  - `function activeWorkspace(mon)` → `Workspace` ativo no monitor ou `null`.
  - `property var fullscreenByMonitor` — **mapa reativo** `{mon: bool}` recomputado a cada atualização; bindings usam `Niri.fullscreenByMonitor[name] === true` (NÃO chamar função, senão não re-evalueta).
  - `function isFullscreen(mon)` — getter de leitura (não reativo; só para código imperativo).
  - `function requeryWindows()` → re-dispara a query `windows` (o stream já cobre workspaces; usado quando um evento de janela não traz payload completo).
  - `function focusWorkspace(reference)` → roda `niri msg action focus-workspace <idx>`.
  - `function focusWindow(id)` → `niri msg action focus-window --id <id>`.
  - `signal stateChanged()` — emitido a cada atualização de estado do stream.

- [ ] **Step 1: Write the failing test**

Não há harness QML; o "test" aqui é parse/runtime no alvo. Escrever o Niri.qml por completo (passo 2) e validar no alvo (passo 3). Escreva o componente:

```qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/fullscreen.js" as Fullscreen

/**
 * The single source of compositor truth for the pill. A persistent Process holds
 * an `event-stream` open (one line per serde/tagged JSON event, full snapshots
 * for workspaces/windows/outputs up-front); every event that lacks the full
 * windows/outputs picture triggers a one-shot re-query through a second socket
 * (a fresh `Process` per call, since the stream socket stops reading requests).
 * Everything the shell renders — dots, OSD, fullscreen heuristic — derives from
 * the state this singleton keeps.
 */
Singleton {
    id: root

    property var workspaces: []
    property var windows: []
    property var outputs: ({})

    signal stateChanged()

    readonly property string focusedMonitorName: {
        var ws = root.workspaces;
        for (var i = 0; i < ws.length; i++) {
            if (ws[i].is_focused && ws[i].output)
                return ws[i].output;
        }
        return "";
    }

    function workspaceList(mon) {
        var out = [];
        var ws = root.workspaces;
        for (var i = 0; i < ws.length; i++) {
            if (ws[i].output === mon) {
                out.push(ws[i]);
            }
        }
        out.sort(function (a, b) { return a.idx - b.idx; });
        return out;
    }

    function activeWorkspace(mon) {
        var ws = root.workspaces;
        for (var i = 0; i < ws.length; i++) {
            if (ws[i].output === mon && ws[i].is_active)
                return ws[i];
        }
        return null;
    }

    /**
     * Reactive map monitor-name → "fullscreen real". Kept as a freshly-assigned
     * object so QML bindings that read `Niri.fullscreenByMonitor[mon]` re-evaluate;
     * `isFullscreen(mon)` below is only a non-reactive convenience getter.
     */
    property var fullscreenByMonitor: ({})

    function isFullscreen(mon) {
        return root.fullscreenByMonitor[mon] === true;
    }

    function recomputeFullscreen() {
        var next = {};
        var ws = root.workspaces;
        var activeId = {}; // output -> id do workspace ativo
        for (var i = 0; i < ws.length; i++) {
            if (ws[i].is_active && ws[i].output && ws[i].id !== undefined && ws[i].id !== null)
                activeId[ws[i].output] = ws[i].id;
        }
        var wins = root.windows;
        for (var j = 0; j < wins.length; j++) {
            var w = wins[j];
            if (w.workspace_id === undefined || w.workspace_id === null)
                continue;
            for (var mon in activeId) {
                if (activeId[mon] !== w.workspace_id)
                    continue;
                var out = root.outputs[mon];
                if (out && out.logical && Fullscreen.isFullscreenCovering(w.layout, out.logical))
                    next[mon] = true; // OR: uma janela que cobre = fullscreen; o mapa é rebuilt a cada call
            }
        }
        root.fullscreenByMonitor = next;
    }

    function applyStreamLine(line) {
        var obj;
        try {
            obj = JSON.parse(line);
        } catch (e) {
            return;
        }
        var key = Object.keys(obj)[0];
        if (!key)
            return;
        var payload = obj[key];
        if (key === "WorkspacesChanged") {
            root.workspaces = payload.workspaces;
            root.recomputeFullscreen();
            root.stateChanged();
        } else if (key === "WindowsChanged") {
            root.windows = payload.windows;
            root.recomputeFullscreen();
            root.stateChanged();
        } else if (key === "WindowOpenedOrChanged") {
            root.requeryWindows();
        } else if (key === "WindowClosed" || key === "WindowFocusChanged") {
            root.requeryWindows();
        } else if (key === "WindowLayoutsChanged") {
            root.requeryWindows();
        } else if (key === "WindowUrgencyChanged" || key === "WindowFocusTimestampChanged"
                   || key === "WorkspaceActivated" || key === "WorkspaceUrgencyChanged") {
            root.recomputeFullscreen();
            root.stateChanged();
        }
    }

    function requeryWindows() {
        windowsProc.command = ["niri", "msg", "--json", "windows"];
        windowsProc.running = true;
    }

    Component.onCompleted: {
        streamProc.running = true;
        outputsProc.running = true;
    }

    Process {
        id: outputsProc
        command: ["niri", "msg", "--json", "outputs"]
        stdout: StdioCollector {
            onStreamFinished: {
                var text = this.text.trim();
                if (!text.length)
                    return;
                try {
                    root.outputs = JSON.parse(text);
                } catch (e) { /* malformed */ }
            }
        }
    }

    Process {
        id: streamProc
        command: ["niri", "msg", "--json", "event-stream"]
        stdout: SplitParser {
            onRead: (line) => {
                if (!line || !line.trim().length)
                    return;
                root.applyStreamLine(line);
            }
        }
    }

    Process {
        id: windowsProc
        command: ["niri", "msg", "--json", "windows"]
        stdout: StdioCollector {
            onStreamFinished: {
                var text = this.text.trim();
                if (!text.length)
                    return;
                try {
                    root.windows = JSON.parse(text);
                    root.recomputeFullscreen();
                    root.stateChanged();
                } catch (e) { /* malformed */ }
            }
        }
    }

    function focusWorkspace(reference) {
        actionProc.command = ["niri", "msg", "action", "focus-workspace", String(reference)];
        actionProc.running = true;
    }

    function focusWindow(id) {
        actionProc.command = ["niri", "msg", "action", "focus-window", "--id", String(id)];
        actionProc.running = true;
    }

    function quit() {
        actionProc.command = ["niri", "msg", "action", "quit", "--skip-confirmation"];
        actionProc.running = true;
    }

    Process {
        id: actionProc
        command: ["niri", "msg", "action", "focus-workspace", "1"]
    }
}
```

- [ ] **Step 2: Register in qmldir**

Adicionar a linha `singleton Niri Niri.qml` logo após `singleton Weather Weather.qml` (antes de `Workspacerules`).

- [ ] **Step 3: Validate on target**

Run (no alvo, em sessão com quickshell pill carregada):
`niri msg --json event-stream | head -c 400` deve mostrar JSON tagado; depois recarregar a pill e ver o log quickshell sem erros de import/parse do Niri.qml (quickshell emite JSON com `clog` de erro no stderr se fail).
Expected: sem erro tipo "Unknown component: Niri" e sem crash no Singleton.

- [ ] **Step 4: Commit**

```bash
git add system_files/etc/quickshell/topbar/pill/Singletons/Niri.qml system_files/etc/quickshell/topbar/pill/Singletons/qmldir
git commit -m "feat(pill): add Niri singleton over niri IPC"
```

---

### Task 3: shell.qml — trocar Hyprland por Niri (refresh, foco, minimize/restore, fullscreen)

**Files:**
- Modify: `system_files/etc/quickshell/topbar/pill/shell.qml`

**Interfaces:**
- Consumes: `Niri` (Task 2). Produces: `refresh()`/`refreshEvents`/Connections Hyprland removidos (o Niri é reativo sozinho; não há re-query no shell); `toggleSurface` resolve monitor via `Niri.focusedMonitorName`; remove `minimizeWindow`/`restoreWindow` do IpcHandler (Seção 4); `monFullscreen` vira `Niri.fullscreenByMonitor[modelData.name] === true`.

- [ ] **Step 1: Replace import**

`shell.qml:7` `import Quickshell.Hyprland` → remover. `Coolbar` — shell.qml não usa mais Hyundai nada.

- [ ] **Step 2: Remove refresh(), refreshEvents, onRawEvent e o GameMode do onCompleted**

Remover esses blocos inteiros (o Niri já é a fonte de verdade e suas props são reativas; nenhuma re-query explícita é necessária no shell):

- `function refresh() { Hyprland.refreshMonitors(); Hyprland.refreshWorkspaces(); Hyprland.refreshToplevels(); }` (34-38)
- `Component.onCompleted` (40-44) — trocar por:
```qml
    Component.onCompleted: {
        Devices.restore();
    }
```
- `readonly property var refreshEvents` (107-118)
- `Connections { target: Hyprland; function onRawEvent(event) {...} }` (120-126)

- [ ] **Step 3: toggleSurface monitor fallback**

```qml
    function toggleSurface(mon, surface) {
        if (!mon || mon.length === 0)
            mon = Niri.focusedMonitorName;
        if (root.openMon === mon && root.openSurface === surface) { root.close(); return; }
        root.openMon = mon;
        root.openSurface = surface;
    }
```

- [ ] **Step 4: Remove minimizeWindow/restoreWindow**

IpcHandler `minimizeWindow`/`restoreWindow` (linhas 210-218) → remover (sem stash no niri).

- [ ] **Step 5: monFullscreen via Niri**

Substituir o bloco `readonly property bool monFullscreen` (267-277) por:

```qml
            readonly property bool monFullscreen: Niri.fullscreenByMonitor[modelData.name] === true
```

- [ ] **Step 6: Validate syntax on target**

Run (no alvo): reiniciar quickshell pill; esperar sem erro "Cannot find module" nem crash; `niri msg --json focused-output` responde objeto único (sanity do envelope).
Expected: pill sobe; OSD/dots ainda Hyundai (migrados nas Tasks 8-9), sem regressão.

- [ ] **Step 7: Commit**

```bash
git add system_files/etc/quickshell/topbar/pill/shell.qml
git commit -m "refactor(pill): shell uses Niri singleton instead of Hyprland"
```

---

### Task 4: Flags/Look — toggles autoHide/smartHide

**Files:**
- Modify: `system_files/etc/quickshell/topbar/pill/Singletons/Flags.qml`
- Modify: `system_files/etc/quickshell/topbar/pill/Look.qml`

**Interfaces:**
- Consumes: nada do Niri. Produces: `Flags.autoHide` (default `true`) e `Flags.smartHide` (default `false`), persistidos em flags.json; toggles no grupo "Pill" do Look.

- [ ] **Step 1: Add alias + adapter props (Flags.qml)**

Após `property alias appGap: adapter.appGap` (linha 33):
```qml
    property alias autoHide: adapter.autoHide
    property alias smartHide: adapter.smartHide
```
No `JsonAdapter` (após `property real appGap: 1.0`, linha 94):
```qml
            property bool autoHide: true
            property bool smartHide: false
```

- [ ] **Step 2: Add toggles in Look.qml (grupo Pill)**

Dentro de `pillGrp` (Group { id: pillGrp; title: "Pill" }, linhas 855+), após a row `appGapRow` adicionar:

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

- [ ] **Step 3: Register rows in Look rows fn**

No `rows` getter do `pillGrp` (linhas 70-75) adicionar antes dos returns:
```js
            r.push({ item: autoHideRow, kind: "toggle", get: function () { return Flags.autoHide; }, set: function (v) { Flags.autoHide = v; } });
            r.push({ item: smartHideRow, kind: "toggle", get: function () { return Flags.smartHide; }, set: function (v) { Flags.smartHide = v; } });
```

- [ ] **Step 4: Validate on target**

Run: tocar Look → Pill → alternar Auto hide; abrir/fechar pill e raiar flags.json.
Expected: `autoHide:true`/`smartHide:false` em `~/.local/state/ricelin/flags.json` após edição; pill continua visível (autoHide ON ainda não ativa nada até Task 5).

- [ ] **Step 5: Commit**

```bash
git add system_files/etc/quickshell/topbar/pill/Singletons/Flags.qml system_files/etc/quickshell/topbar/pill/Look.qml
git commit -m "feat(pill): add autoHide and smartHide flags"
```

---

### Task 5: auto-hide/smart-hide no shell (pillHidden, máscara, exclusiveZone)

**Files:**
- Modify: `system_files/etc/quickshell/topbar/pill/shell.qml`
- Modify: `system_files/etc/quickshell/topbar/pill/Pill.qml`

**Interfaces:**
- Consumes: `Niri.fullscreenByMonitor` (mapa reativo) + `Niri.focusedMonitorName` (Task 2), `Flags.autoHide`/`Flags.smartHide` (Task 4). Produces: `overlay.pillHidden`; Pill: `hiddenStripRegion`, mask; reserve: exclusiveZone/implicitHeight colapsáveis.

- [ ] **Step 1: Add pillHidden to overlay**

Em `shell.qml` dentro de cada `overlay` PanelWindow, após `monFullscreen` (Task 3):

```qml
            readonly property bool revealWant: pill.hovered || pill.held || surfaceOpen || pill.quickChoosing || root.peekMon === modelData.name
            readonly property bool pillHidden: !revealWant && (Flags.autoHide || (Flags.smartHide && monFullscreen))
```

- [ ] **Step 2: On return to shown, close surfaces/pin**

Reaproveitar `onMonFullscreenChanged` (hoje fecha surface/pin). Trocar para dissapear somente quando a pill fica escondida:

```qml
            onPillHiddenChanged: if (pillHidden) {
                if (root.openMon === modelData.name) root.close();
                if (root.peekMon === modelData.name) root.peekMon = "";
                pill.pinned = false;
            }
```

- [ ] **Step 3: Pill mask + strip region**

Em Pill.qml, a pilha da mask vive no overlay. No `overlay`, substituir `mask: monFullscreen ? hiddenRegion : (...)` por:

```qml
            mask: pillHidden ? hiddenStripRegion : (modal ? fullRegion : pillRegion)
            Region {
                id: hiddenStripRegion
                y: -4 * s
                width: overlay.width
                height: 7 * s
            }
```

Reposicionar essa máscara na ordem correta: o strip precisa estar acima das janelas mesmas (a pill fica em `WlrLayer.Overlay`, por isso `y: -4*s`). Remover o `Region { id: hiddenRegion }` (295) que ficou órfão (a referência antiga de `monFullscreen` some junto).

- [ ] **Step 4: Pill visual: opacity/translate via pillHidden**

Trocar em Pill (sinais `opacity: overlay.monFullscreen ? 0 : 1` e `transform: Translate { y: overlay.monFullscreen ? ... }`, e `pinned`) por `overlay.pillHidden`:

```qml
                    opacity: overlay.pillHidden ? 0 : 1
                    transform: Translate {
                        y: overlay.pillHidden ? -(pill.height + overlay.topGap) : 0
```
(o `Behavior`/animation permanece igual). Lembrar: `monFullscreen` ainda existe como property p/ smartHide; mas o visual usa `pillHidden`.

- [ ] **Step 5: exclusiveZone colapsável (reserve)**

Em `shell.qml` o PanelWindow `reserve` não tem acesso ao `pill` (filho do overlay), então colapsa pela mesma fórmula com os dados que conhece — surface aberta, peek, fullscreen — sem o hover/held (que só o overlay observa). Isso significa que, durante um hover que revela a pill, o reserve já está em 0: a pill aparece *sobre* o conteúdo, o comportamento de barra auto-hide padrão. Aceito no design:

```qml
            readonly property bool collapsed: root.openMon !== modelData.name && root.peekMon !== modelData.name
                && (Flags.autoHide || (Flags.smartHide && Niri.fullscreenByMonitor[modelData.name] === true))
            exclusiveZone: collapsed ? 0 : reservedH
            implicitHeight: collapsed ? 0 : reservedH
```

**Nota de paridade:** com `autoHide` OFF e `smartHide` OFF, `collapsed` é sempre `false` → `exclusiveZone: reservedH`, idêntico ao comportamento atual. Com `autoHide` ON, o reserve colapsa sempre que nenhum surface/peek do monitor: a pill flutua sobre o conteúdo e o exclusiveZone volta a `reservedH` quando um surface abre ou quando `root.peekMon === modelData.name`.

- [ ] **Step 6: Validate on target (critério 1 e 3)**

Run (alvo): com autoHide ON, mover o mouse ao topo → pill aparece; afastar → some; abrir wallpaper/settings → pill fica; maximizar janela (`Mod+F`) em monitor com smartHide OFF → pill some pela autoHide apenas quando hover-none. Com `Mod+Shift+F` + smartHide ON → pill some mesmo sem autoHide. Checar exclusiveZone: janela maximizada encosta no topo com pill colapsada.
Expected: 2 dos critérios de aceite do spec OK.

- [ ] **Step 7: Commit**

```bash
git add system_files/etc/quickshell/topbar/pill/shell.qml system_files/etc/quickshell/topbar/pill/Pill.qml
git commit -m "feat(pill): auto-hide and smart-hide behavior with masked strip"
```

---

### Task 6: Remover gameMode

**Files:**
- Delete: `system_files/etc/quickshell/topbar/pill/Singletons/GameMode.qml`
- Modify: `Singletons/qmldir` (−linha `singleton GameMode GameMode.qml`)
- Modify: `Singletons/Flags.qml` (−aliases 47-51 e adapter 108-112: `gameMode`, `gamePrevDnd`, `gamePrevViz`, `gamePrevAwake`, `gamePrevProfile`)
- Modify: `shell.qml` (−IpcHandler `gameMode` :187; −`gameBarH` 234; −bind `Flags.gameMode` em `exclusiveZone`/`implicitHeight` (239/243, já substituído na Task 5 — confirmar que não resta); −`void GameMode.active` onCompleted já removido)
- Modify: `Mixer.qml` (remover chip 342-348)
- Modify: `Pill.qml` (−`gameH`/`gameW` 184-185; −`mode === "game"` 244; −`gameBar` 1129-~1190; −`gameFlat` em `body` rectangle 691-698; −refs `pill.mode === "game"` em 530, 1251; −`anchors.topMargin: pill.mode === "game" ? 0 : overlay.topGap` 414)

- [ ] **Step 1: Delete GameMode.qml e remover do qmldir**

`rm Singletons/GameMode.qml`; editar qmldir removendo a linha 20.

- [ ] **Step 2: Strip Flags game fields**

Remover aliases (47-51) e adapter (108-112).

- [ ] **Step 3: Remove IpcHandler gameMode + gameBarH**

Em shell.qml remover `function gameMode` (187) e `readonly property real gameBarH` (234).

- [ ] **Step 4: Remove Mixer chip**

`Mixer.qml:342-348` (o bloco `IconChip { glyph: "gamepad" ... }`).

- [ ] **Step 5: Strip Pill game refs**

- `gameH`/`gameW` (184-185): remover.
- `mode` ternary (242-249): remover a linha `: (Flags.gameMode ? "game"`.
- `gameBar` (1129+): remover o bloco `Item { id: gameBar ... }`.
- `morphRadius` (530): `(mode === "rest" || mode === "hover" || mode === "game")` → sem `game`.
- `gameFlat` em `body` (691-698): remover propriedade e os `topLeft...` voltam a `pill.morphRadius`.
- `rest` opacity (1251): remover `|| pill.mode === "game"`.
- `anchors.topMargin` (414): fica `anchors.topMargin: overlay.topGap`.

- [ ] **Step 6: Validate on target**

Run: grep `gameMode|GameMode|gameBar|gameFlat` no diretório pill → deve retornar vazio.
Expected: nenhuma ocorrência; pill inicia normal.

- [ ] **Step 7: Commit**

```bash
git rm system_files/etc/quickshell/topbar/pill/Singletons/GameMode.qml
git add system_files/etc/quickshell/topbar/pill/Singletons/qmldir system_files/etc/quickshell/topbar/pill/Singletons/Flags.qml system_files/etc/quickshell/topbar/pill/shell.qml system_files/etc/quickshell/topbar/pill/Mixer.qml system_files/etc/quickshell/topbar/pill/Pill.qml
git commit -m "refactor(pill): drop gameMode"
```

---

### Task 7: Remover stash/espaços especiais

**Files:**
- Delete: `MinimizedTray.qml`, `Stash.qml`, `WorkspacesSurface.qml`, `SpaceApps.qml`, `AppPickerList.qml`, `Singletons/Spaces.qml`, `Singletons/Workspacerules.qml`
- Modify: `Singletons/qmldir` (−linhas Workspacerules e Spaces)
- Modify: `Pill.qml` — `specialView` (107-128); `surfaces` map entries stash/spaceapps/workspaces (228/229/227); props W ends `stashW`/`spaceappsW`/`workspacesW` (164-166); MinimizedTray block + hairline (1458-1474); loaders ldStash/ldSpaceapps/ldWorkspaces (2014-2051); `surface === "stash"`/`"spaceapps"`/`"workspaces"` opens (49-51); keybinds keep; `keybindsBack` keep; back-stack refs (411-432)
- Modify: `shell.qml` — remover minimize/restore já feito na Task 3; `stack.peekMon` OK.
- Modify: `Workspaces.qml` (task 8 handles dots; aqui remove `Workspacerules.byMonitor` ref)

**Nota:** `lib/monitors.js`+`monitors.test.mjs` são usados apenas por `Display.qml` (mantido, inerte); remover apenas se o Display.qml não for apresentado (o nav não abre mais). Remoção segura no escopo B.

- [ ] **Step 1: Delete files**

`rm Pill/MinimizedTray.qml Pill/Stash.qml Pill/WorkspacesSurface.qml Pill/SpaceApps.qml Pill/AppPickerList.qml Singletons/Spaces.qml Singletons/Workspacerules.qml`.

- [ ] **Step 2: qmldir**

Remover linhas 15 (`workspacerules`) e 17 (`spaces`). `Niri` já está.

- [ ] **Step 3: Pill — size props, opens, surfaces map**

Remover `stashW`/`spaceappsW`/`workspacesW` (164-166); `stashOpen`/`spaceappsOpen`/`workspacesOpen` (49-51, mas `workspacesOpen` referencia surface "workspaces" que não é mais loader → remover); em `surfaces` map remover `stash`, `spaceapps`, `workspaces` entries (226-229 region).

- [ ] **Step 4: Pill — specialView**

Remover a property `specialView` (107-128) junto com o que a dependia: em `restRow`, `restKanji` (1260) perde a condição `visible: pill.specialView === ""` (remover a linha 1261, o Item fica sempre visível); no relógio central, remover o `Text` alternativo que exibia `pill.specialView` (1324-1332) e tirar a condição `visible: pill.specialView === ""` do Text do relógio (1315, que fica sempre visível).

- [ ] **Step 5: Pill — MinimizedTray + back-stack**

Remover `MinimizedTray` (1458-1465) e a hairline (1467-1474). Em `surfaceBack` remover os blocos `stashOpen`/`spaceappsOpen` (411-424) e o `workspacesOpen` (425-427), e no condicional (429) remover `|| pill.workspacesOpen` — para `surfaceBack`, `surface === "workspaces"` simplesmente não existe mais (o `requestSurface("workspaces")` naqueles blocos também sai junto). Manter os demais opens (appearance/updates/display/input/look/idlelock/animation).

- [ ] **Step 6: Pill — loaders**

Remover `ldWorkspaces` (2014-2025), `ldStash` (2027-2038), `ldSpaceapps` (2040-2051).

- [ ] **Step 7: Workspaces.qml — remove Workspacerules import/ref**

Só remove `import ...Workspacerules` + o bloco `ruled` do `range` (33-41) neste passo; o resto da Task 8.

- [ ] **Step 8: Verify no dangling refs**

Run (no host): `grep -rn "MinimizedTray\|Stash\|WorkspacesSurface\|SpaceApps\|AppPickerList\|Spaces\.\|Workspacerules\|monitors"` em `system_files/etc/quickshell` → sem hits (exceto comentários/`workspaces` genérico e libs mantidas).
Expected: vazio.
Validar no alvo: pill sobe sem erro.

- [ ] **Step 9: Commit**

```bash
git rm system_files/etc/quickshell/topbar/pill/MinimizedTray.qml system_files/etc/quickshell/topbar/pill/Stash.qml system_files/etc/quickshell/topbar/pill/WorkspacesSurface.qml system_files/etc/quickshell/topbar/pill/SpaceApps.qml system_files/etc/quickshell/topbar/pill/AppPickerList.qml system_files/etc/quickshell/topbar/pill/Singletons/Spaces.qml system_files/etc/quickshell/topbar/pill/Singletons/Workspacerules.qml system_files/etc/quickshell/topbar/pill/lib/monitors.js system_files/etc/quickshell/topbar/pill/lib/monitors.test.mjs
git commit -m "refactor(pill): drop stash and special spaces"
```
(e os edits de Pill.qml/qmldir no mesmo commit).

---

### Task 8: Workspaces.qml — dots via Niri

**Files:**
- Modify: `system_files/etc/quickshell/topbar/pill/Workspaces.qml`

**Interfaces:**
- Consumes: `Niri.workspaceList(mon)`, `Niri.activeWorkspace(mon)`, `Niri.focusWorkspace(reference)`. Produces: `range` = array de idx ordenado; `activeWs` = idx ativo; `isActive` no delegate compara o idx do slot contra `activeWs`.

- [ ] **Step 1: Rewrite range over Niri, keep activeIndex as range position**

`slotCenterX(idx)`/`activeDotPoint` esperam a **posição dentro do range** (0-based; o loop `i === activeIndex` conta slots). Por isso `activeIndex` continua sendo `range.indexOf(...)`, não o valor do idx. Adicione uma property separada `activeWs` com o idx:

```qml
    readonly property var range: {
        var wss = Niri.workspaceList(screenName);
        var out = [];
        for (var i = 0; i < wss.length; i++)
            out.push(wss[i].idx);
        out.sort(function (a, b) { return a - b; });
        return out;
    }

    readonly property int activeWs: {
        var act = Niri.activeWorkspace(screenName);
        return act ? act.idx : -1;
    }

    // inalteradas: slotCenterX(idx) iterando i === activeIndex
    readonly property int activeIndex: range.indexOf(activeWs)
```

- [ ] **Step 2: Rewrite delegate isActive + click**

O delegate já usa `wsName: String(modelData)` (o model é `range`, logo `modelData` é o idx). Só trocar a comparação e o clique:

```qml
                readonly property bool isActive: workspaces.activeWs >= 0 && String(modelData) === String(workspaces.activeWs)
...
                    onClicked: Niri.focusWorkspace(slot.wsName)
```

- [ ] **Step 3: Remove Hyprland import & activeName string**

Remove `import Quickshell.Hyprland` (linha 5), a property `activeName` (58-64) e o logic do `range` que lia `Workspacerules.byMonitor` + `Hyprland.workspaces` (30-56). No `activeDotPoint` (82-86), remover a linha `void workspaces.activeName;` (a re-computação via `activeIndex`/`range` já cobre).

- [ ] **Step 4: Validate on target**

Run: trocar de workspace com Super+arrow; dots refletem (ativo maior/vermelho); clicar muda de workspace em ambos os monitores.
Expected: dots e clique funcionais sem Hyundai.

- [ ] **Step 5: Commit**

```bash
git add system_files/etc/quickshell/topbar/pill/Workspaces.qml
git commit -m "feat(pill): workspace dots driven by Niri"
```

---

### Task 9: Osd.qml — activeWsName e onFocusedMonitor via Niri

**Files:**
- Modify: `system_files/etc/quickshell/topbar/pill/Osd.qml`

**Interfaces:**
- Consumes: `Niri.workspaceList`, `Niri.focusedMonitorName`. Produces: `activeWsName` (string idx), `onFocusedMonitor`.

- [ ] **Step 1: activeWsName**

```qml
    readonly property string activeWsName: {
        var act = Niri.activeWorkspace(screenName);
        return act ? String(act.idx) : "";
    }
```

- [ ] **Step 2: onFocusedMonitor**

```qml
    readonly property bool onFocusedMonitor: Niri.focusedMonitorName.length === 0 || Niri.focusedMonitorName === screenName
```

- [ ] **Step 3: Remove Hyprland import & old refs**

Remove `import Quickshell.Hyprland` (3); remover o loop Hyundai (64-69).

- [ ] **Step 4: Validate on target**

Run: trocar workspace → OSD apresenta dots; volume/brightness só no monitor focado.
Expected: comportamento igual ao anterior.

- [ ] **Step 5: Commit**

```bash
git add system_files/etc/quickshell/topbar/pill/Osd.qml
git commit -m "feat(pill): osd monitor/workspace refs via Niri"
```

---

### Task 10: Power.qml — logout via Niri.quit

**Files:**
- Modify: `system_files/etc/quickshell/topbar/pill/Power.qml`

**Interfaces:**
- Consumes: `Niri.quit()` (Task 2). Produces: `dispatch` "hl.dsp.exit()" → `Niri.quit()`.

- [ ] **Step 1: logout action**

```qml
        { key: "logout",   glyph: "logout",   label: "Logout",   confirm: true,  dispatch: "",             argv: [] }
```
e em `run(a)`:
```js
    function run(a) {
        if (a.key === "logout") { Niri.quit(); }
        else if (a.dispatch && a.dispatch.length)
            Hyprland.dispatch(a.dispatch);
        else
            Quickshell.execDetached(a.argv);
        root.requestClose();
    }
```

- [ ] **Step 2: Remove Hyprland import**

`import Quickshell.Hyprland` (5) → remover; `Hyprland.dispatch` só era usado para logout → agora só Niri.

- [ ] **Step 3: Validate on target**

Run: abrir Power → segurar o tile Logout → sessão niri encerra (sem prompt "Press Enter to confirm").
Expected: logout com `-s`/`--skip-confirmation`.

- [ ] **Step 4: Commit**

```bash
git add system_files/etc/quickshell/topbar/pill/Power.qml
git commit -m "feat(pill): logout via niri IPC quit"
```

---

### Task 11: Notifs.qml — raiseWindow via Niri

**Files:**
- Modify: `system_files/etc/quickshell/topbar/pill/Singletons/Notifs.qml`

**Interfaces:**
- Consumes: `Niri.windows` (property array), `Niri.focusWindow(id)`. Produces: `raiseWindow` sem hyprctl/jq.

- [ ] **Step 1: raiseWindow via Niri**

```js
    function raiseWindow(n) {
        if (!n) return;
        var token = String(n.desktopEntry && n.desktopEntry.length ? n.desktopEntry : (n.appName || "")).toLowerCase();
        if (token.length === 0) return;
        var wins = root.niriWindows;
        for (var i = 0; i < wins.length; i++) {
            var w = wins[i];
            var cls = w.app_id ? w.app_id.toLowerCase() : "";
            if (cls.indexOf(token) !== -1) {
                Niri.focusWindow(w.id);
                return;
            }
        }
    }
```
E uma property `readonly property var niriWindows: Niri.windows`.

- [ ] **Step 2: Replace the shell command**

Remover o bloco `Quickshell.execDetached(["sh", "-c", ... "hyprctl clients" ...])` (121-123).

- [ ] **Step 3: Validate on target**

Run: com uma notificação de app aberto, clicar "abrir" → foca o app.
Expected: foca sem rodar hyprctl/jq.

- [ ] **Step 4: Commit**

```bash
git add system_files/etc/quickshell/topbar/pill/Singletons/Notifs.qml
git commit -m "feat(pill): notification raiseWindow via niri windows"
```

---

### Task 12: Settings.qml — ocultar rows Hyprland-only; launcher import morto

**Files:**
- Modify: `system_files/etc/quickshell/topbar/pill/Settings.qml`
- Modify: `system_files/etc/quickshell/topbar/launcher/shell.qml`

**Interfaces:**
- Consumes: nada. Produces: nav sem Display/Keybinds/Workspaces.

- [ ] **Step 1: Settings rows**

No array `rows` (16-26) remover as linhas `displayRow`(19), `keybindsRow`(22), `workspacesRow`(23), deixando comentário:

```js
    rows: [
        { item: appearanceRow, kind: "nav", surface: "appearance" },
        { item: lookRow, kind: "nav", surface: "look" },
        // display/keybinds/workspaces ROWS REMOVIDAS: surfaces Hyprland-only, seguem inertes no repo
        { item: inputRow, kind: "nav", surface: "input" },
        { item: animationRow, kind: "nav", surface: "animation" },
        { item: idleRow, kind: "nav", surface: "idlelock" },
        { item: updatesRow, kind: "nav", surface: "updates" }
    ]
```
Remover os três blocos `SettingsRow` (76-90 display, 126-141 keybinds, 143-158 workspaces) com comentário único no lugar.

- [ ] **Step 2: launcher/shell.qml**

`launcher/shell.qml:5` `import Quickshell.Hyprland` → remover.

- [ ] **Step 3: Validate on target (critério 5)**

Run: abrir Settings → o nav lista Appearance, Look, Input, Animation, Idle/Lock, Updates; rodar `grep -n "displayRow\|keybindsRow\|workspacesRow"` em Settings.qml → sem hits.
Expected: sem rows Hyprland-only; grep por `Quickshell.Hyprland|Hyprland.|hyprctl` em todo o projeto retorna apenas o que for intencional nos follow-ups (Look.qml/Input.qml/IdleLock.qml/AnimationSurface.qml e scripts hypr).

- [ ] **Step 4: Commit**

```bash
git add system_files/etc/quickshell/topbar/pill/Settings.qml system_files/etc/quickshell/topbar/launcher/shell.qml
git commit -m "feat(pill): hide hyprland-only settings rows"
```

---

### Task 13: Verificação final (critérios de aceite do spec)

**Files:** — verificação documental.

- [ ] **Step 1: Grep residual**

Run (no host):
`grep -rn "Quickshell.Hyprland\|Hyprland\.\|hyprctl" system_files/etc/quickshell`
Expected: só em arquivos que permanecem Hyprland-only por follow-up (Look.qml, Input.qml, Keybinds.qml, IdleLock.qml, AnimationSurface.qml, Display.qml, Appearance.qml, NightLight.qml). `Singletons/Players.qml` mantém um `import Quickshell.Hyprland` sem uso (import morto, fora do escopo B — sem refs). Sem ocorrência em shell/Pill/Workspaces/Osd/Power/Notifs/Settings/launcher.

- [ ] **Step 2: Rode os testes node no alvo**

Run (no alvo): `(cd system_files/etc/quickshell/topbar/pill/lib && node fullscreen.test.mjs)`
Expected: PASS completo.

- [ ] **Step 3: Critérios manuais no alvo**

- 1: autoHide ON → pill some em gesto leve, reaparece na faixa/hover/surface/quick.
- 2: `Mod+Shift+F` com smartHide ON → some; `Mod+F` → NÃO some.
- 3: exclusiveZone colapsa em 0 com pillHidden; janela maximizada encosta no topo.
- 4: dots, OSD, logout, raiseWindow funcionam sem Hyundai no código.
- 5: nav = Appearance, Look, Input, Animation, Idle/Lock, Updates.
- 6: grep gameMode/stash/minimizado → vazio.

- [ ] **Step 4: Commit (nada a commitar; reportar)**

Sem commit; reportar o resultado ao usuário.

---

## Self-Review (checagem rápida contra o spec)

- Spec Seção 1 (Niri singleton, stream+queries, heurística): Tasks 1-2 cobrem integralmente; envelope JSON documentado nas constraints; eventos whitelist: Task 2 (`WorkspacesChanged`, `WindowsChanged`, `Window*`, `WorkspaceActivated/Urgency`).
- Spec Seção 2 (autoHide/smartHide, máscara strip, exclusiveZone colapsável, animação reaproveitada): Task 5.
- Spec Seção 3 (remover gameMode + GameMode.qml + chip + binds): Task 6.
- Spec Seção 4 (stash/espaços/specialView/minimize/restore/monitors.js): Task 7.
- Spec Seção 5-B (Workspaces, Osd, Power, Notifs, launcher, Settings rows): Tasks 8-12.
- Critérios de aceite: Task 13.
- Placeholders: nenhum "TBD"; todo passo tem código/run concreto.
- Consistência de tipos: `Niri.requeryWindows` usado dentro do Niri (Task 2) nos eventos `Window*` que não trazem payload completo; shell não re-queries (o stream empurra tudo) — Task 3 só lê props reativas; `pillHidden` nome consistente (Task 5); `workspaceList/activeWorkspace/isFullscreen/focusWorkspace/focusWindow/quit` idênticos em todas as tasks.
- Flag confirmada: `action quit --skip-confirmation` e `focus-workspace <idx>` (FromStr: inteiro→Index, senão Name; NÃO aceita id) — consistente com `activeIndex`/`wsName` em Workspaces (idx, não id).
- `outputs` em Niri.qml é populado uma vez no connect pela query `niri msg --json outputs` (anexado em Task 2); não há evento de outputs no stream, e a heurística só precisa de `output.logical`. Hotplug de monitor não re-popula `outputs` neste escopo — delay aceito (a heurística só degrada para "não-fullscreen", e workspaces/windows do stream continuam frescos). Melhorar (re-query outputs no stream de eventos) fica como follow-up se necessário.