# Migração da pill (quickshell) para niri

**Data:** 2026-08-09
**Área:** `system_files/etc/quickshell/topbar/pill` + `launcher`
**Estado:** Design aprovado pelo usuário (Seções 1-2, 3-4, 5 escopo B). Aguarda self-review → review do usuário → writing-plans.

## Objetivo

Migrar **completamente** a pill de `Quickshell.Hyprland` para o IPC do niri. Dois toggles independentes de ocultação:

- **autoHide** — oculo a pill até o cursor entrar na faixa reservada no topo da tela (faixa de ~6px revela a pill).
- **smartHide** — escondo a pill apenas quando houver uma janela em **fullscreen real** no monitor focado. Como o niri cobre as camadas `top`/`bottom` sobre fullscreen, mas NÃO cobre `Overlay` (onde a pill vive), a detecção é manual: janela focada cobre a área lógica do output e não tem margem de coluna.

Escopo expandido a pedido do usuário: portar **todos** os usos de `Quickshell.Hyprland` no projeto (29 ocorrências), não só a ocultação. Escopo **B** aprovado: migrar o núcleo funcional + remover gameMode e o ecossistema stash/espaços especiais + ocultar do nav surfaces de edição de config Hyprland-only (que ficariam "mortas"). Look/Input/IdleLock/Animation/Display/Appearance ficam para follow-up.

## Restrições verificadas (fontes oficiais)

- niri-ipc **26.4.0** (10/jul/2026). Gemas sem versões fixas → sempre em iteração.
- **`Window` NÃO tem `is_fullscreen`.** Campos: `id, title, app_id, pid, workspace_id, is_focused, is_floating, is_urgent, layout, focus_timestamp`.
- `Window.layout` é `WindowLayout`: `pos_in_scrolling_layout, tile_size, window_size, tile_pos_in_workspace_view, window_offset_in_tile`.
- `Action` só tem `FullscreenWindow { id: Option<u64> }` (toggle) e `ToggleWindowedFullscreen` — **sem `--set`**. Não posso forçar entrada em fullscreen via IPC (não preciso).
- Fullscreen "real" (que cobre as camadas) é o toggle de `Action::FullscreenWindow`/`toggle-window-fullscreen` (config.kdl:139 `Mod+Shift+F`). `maximize-column` (config.kdl:138 `Mod+F`) NÃO é fullscreen → a pill não deve reagir.
- PR `niri-wm/niri#2836` (Sem1rose) **ainda aberto** — adicionaria `sizing_mode`/`fullscreen_state` ao IPC, eliminando a heurística. Não bloquear por ele; a heurística é o plano.
- `Output`: `name, make, model, serial, physical_size, modes, current_mode, is_custom_mode, vrr_supported, vrr_enabled, logical: Option<LogicalOutput>`. `LogicalOutput`: `x, y, width, height, scale, transform`.
- `niri msg --json event-stream`: um evento JSON por linha; só há um socket por processo para requests+stream → usar **dois `Process`** (um para o stream, um para requests/ações).
- YaLTeR recomenda não esconder layer-shell via IPC; já que o niri cobre `top`/`bottom` sozinho, o único caso residual é a camada `Overlay` em fullscreen → heurística de geometria + margem.

## Arquitetura — Seção 1: singleton `Niri` (aprovada)

Novo `system_files/etc/quickshell/topbar/pill/Singletons/Niri.qml`, registrado em `Singletons/qmldir`. Única fonte de verdade do estado do compositor para a pill (e para o que for migrado depois).

- **Stream**: `Process agent niri msg --json event-stream` + `SplitParser` (por linha) + `JsonParser`. Whitelist de eventos padrão espelhando o que o shell já consome (workspaces, windows, outputs, focus, fullscreen-ish). Nenhum parse de cuias Hyprland.
- **Re-query**: uma tarefa assíncrona dispara `niri msg --json workspaces` / `--json outputs` / `--json windows` ao conectar e após marcos relevantes. Duas janelas `Process` (o stream fica com o socket 1; as queries usam socket 2, já que após o EventStream o socket para de ler requests).
- **Estado exposto** (propriedades/sinais no singleton):
  - `Niri.focusedMonitorName`
  - `Niri.activeWorkspace(mon)` → índice/ide da workspace ativa no monitor
  - `Niri.workspaceList(mon)` → lista de workspaces para os dots
  - `Niri.isFullscreen(mon)` → bool da heurística
  - ações: `Niri.focusWorkspace(id)`, `Niri.focusWindow(id)`, `Niri.quit()` etc. via `niri msg action ...`.
- **Heurística de fullscreen** (`Niri.isFullscreen[mon]`):
  - tomado `WindowLayout.window_size` da janela focada (`is_focused`) no monitor;
  - `LogicalOutput.width × height` do output daquele monitor (igualdade limitada por tolerância ~1px);
  - E sem margem de coluna: `tile_pos_in_workspace_view.x == 0` e `window_size.width >= output.width` (se detectar via `window_size` já bastar, dispensar margem);
  - pontos de recomputar: evento `windows-changed`/`focus-changed` do stream e qualquer evento que implique mudança de tamanho/output.
  - "fullscreen real" = janela focada cobre o output lógico sem margem de coluna. `maximize-column` deixa margem e não cobre a altura toda na prática → não dispara.

## Seção 2: auto-hide / smart-hide no shell (aprovada)

Em `system_files/etc/quickshell/topbar/pill/shell.qml`:

- **Flags** (`Singletons/Flags.qml`): `autoHide` (default true) e `smartHide` (default false), persistidas em JSON como as demais, com toggles novos no `Look.qml` (grupo da pill).
- **Cálculo de ocultação**:
  ```
  revealWant = pill.hovered || pill.held || pill.surfaceOpen || quickChoosing || root.peekMon == mon
  pillHidden  = !revealWant && (autoHide || (smartHide && Niri.isFullscreen[mon]))
  ```
- **Máscara**: quando `pillHidden`, a máscara do botão `Pill.qml` vira `hiddenStripRegion` — uma faixa de ~6px na largura total no topo (para o hover da faixa revelar a pill). Senão a máscara atual (borda arredondada/hover).
- **exclusiveZone**: hoje `exclusiveZone: Flags.gameMode ? gameBarH : reservedH`. Com a migração fica:
  - `reservedH` (config atual) quando `!autoHide || !pillHidden` — a pill reserva o espaço normal;
  - `0` quando `autoHide && pillHidden` — a pill colapsa e niri pode usar a região (garantindo que uma janela maximizada encoste no topo real).
- **Animação**: reaproveitar o mecanismo atual de `opacity` + deslocamento em `y` dirigido por `pillHidden`, no `Motion` atual.
- `reservedH = max(0, restHeight + topGap - 12 * (1 - Flags.appGap) * s)`; `gameBarH: 34*s` **sai** (veja Seção 3).

## Seção 3: remover gameMode (aprovada)

Remoções (não editar flags de comportamento do padrão — o usuário não usa gameMode e quer fora):

- `system_files/etc/quickshell/topbar/pill/Singletons/GameMode.qml` (arquivo)
- `Singletons/Flags.qml`: `gameMode`, `gamePrevDnd`, `gamePrevViz`, `gamePrevAwake`, `gamePrevProfile`
- `system_files/etc/quickshell/topbar/pill/Mixer.qml:344-347` (chip gameMode)
- `shell.qml:187` (toggle da propriedade), `234/239/243` (bind de `gameMode`/`gameBarH`/`exclusiveZone`)
- `Pill.qml:184-185` (`gameH`, `gameW`), `244` (`mode === "game"`), `~1130` (`gameBar`)
- `system_files/etc/quickshell/gamemode.sh` (para o diretório inteiro, se for cópia local; confirmar antes de deletar script externo)

## Seção 4: remover stash/espaços especiais (aprovada)

O usuário governa workspaces via `config.kdl`; niri não tem workspaces especiais. Remover:

- `MinimizedTray.qml` + uso em `Pill.qml` (~1458-1469)
- `Stash.qml`, `WorkspacesSurface.qml`, `SpaceApps.qml`, `AppPickerList.qml` (se só referenciados pelo ecossistema removido)
- `Singletons/Spaces.qml`, `Singletons/Workspacerules.qml`
- `lib/monitors.js` + `monitors.test.mjs`
- `Pill.qml:107-128` (`specialView`, que lê `Hyprland.monitors` + `Spaces.list`)
- IPC `minimizeWindow`/`restoreWindow` (`shell.qml:210-218`)
- Nenhuma mudança no `config.kdl` (niri não tem special workspaces).

## Seção 5 — escopo B: migrar núcleo + ocultar surfaces mortas (aprovada)

### Migrações funcionais
- `Workspaces.qml` — dots via `Niri.workspaceList(mon)`/`Niri.activeWorkspace(mon)`; clique → `Niri.focusWorkspace(id)`.
- `Osd.qml:64/101` — valores vindos do `Niri` (brightness/etc são do backlight local, não muda; são os refs de monitor/foco que vão).
- `Power.qml:52` — logout: `hl.dsp.exit()` → `Niri.quit()` (ação `niri msg action quit`).
- `Singletons/Notifs.qml:117-124` `raiseWindow` — hoje `hyprctl clients` + `hl.dsp.focus`; vira `Niri.windows` (query `niri msg --json windows`, achar por `app_id`/`title`) + `Niri.focusWindow(id)` (`niri msg action focus-window <id>`).
- `launcher/shell.qml:5` — remover import morto `Quickshell.Hyprland`.

### Surfaces de nav a ocultar (decisão do usuário: "Ocultar do nav")
- `Settings.qml` rows a REMOVER do array `rows` e do corpo: `displayRow` (19), `keybindsRow` (22), `workspacesRow` (23). Comentário no lugar delas. O nav passa a: Appearance, Look, Input, Animation, Idle/Lock, Updates.
- OS arquivos das surfaces permanecem no repositório (não deletar): Display.qml, Keybinds.qml, WorkspacesSurface (já removida na Seção 4 — logo a row "workspaces" some do mesmo jeito), Look.qml, Input.qml, IdleLock.qml, AnimationSurface.qml, NightLight.qml, Appearance.qml, FontPicker.qml. **Não** são referenciadas por row → não degradam runtime.
- `Pill.qml` keep: surfaces/loaders continuam existindo (os loaders `ldDisplay`, `ldKeybinds`, `ldWorkspaces`, `ldLook`, `ldInput`, `ldIdlelock`, `ldAnimation`, `ldFontpicker`, `ldAppearance` ficam inertes). Só o nav deixa de apontar para elas. (Se quiser limpeza maior, follow-up.)

## O que NÃO muda
- `config.kdl` (os binds e o spawn de `pill`/`launcher` já usam `niri`/wayland).
- Camadas/anchor/layout visual da pill (a menos que o hover da faixa exija ajuste de `exclusiveZone`).
- `qmldir` só ganha `Niri`; entradas de singletons removidos saem junto.

## Estimativa de arquivos tocados
- Novo: `pill/Singletons/Niri.qml`.
- Editados: `Flags.qml`, `qmldir`, `shell.qml`, `Pill.qml`, `Look.qml`, `Settings.qml`, `Workspaces.qml`, `Osd.qml`, `Power.qml`, `Notifs.qml`, `Mixer.qml`, `launcher/shell.qml`.
- Removidos: `GameMode.qml`, `MinimizedTray.qml`, `Stash.qml`, `WorkspacesSurface.qml`, `SpaceApps.qml`, `AppPickerList.qml`, `Spaces.qml`, `Workspacerules.qml`, `lib/monitors.js`, `monitors.test.mjs` (+ `gamemode.sh` se cópia local).

## Critérios de aceite
1. Pill com autoHide ON some numgesto leve e reaparece em hover/faixa/surface/quick.
2. Em `Mod+Shift+F`, a pill com smartHide ON some; `Mod+F` (maximize) NÃO esconde.
3. `exclusiveZone` colapsa em 0 enquanto pillHidden; janela maximizada encosta no topo.
4. Dots de workspace, OSD, logout e raiseWindow funcionam sem `Hyprland` no código (grep por `Quickshell.Hyprland`/`Hyprland.`/`hyprctl` retorna só o que for intencional em follow-ups).
5. Nav do Settings = Appearance, Look, Input, Animation, Idle/Lock, Updates (sem mention de Keybinds/Display/Workspaces).
6. Nada de gameMode/stash/minimizado no código.