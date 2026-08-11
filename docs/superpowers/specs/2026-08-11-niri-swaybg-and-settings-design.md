# Integração final com niri: swaybg, idle/lock, night light e surfaces de settings

**Data:** 2026-08-11
**Área:** `Containerfile`, `system_files/etc/niri/*`, `system_files/etc/quickshell/topbar/{pill,lock}`, `hypr/scripts/*` (conteúdo movido para `system_files/etc/niri/scripts`)
**Estado:** Design aprovado pelo usuário. Aguarda self-review → review do usuário → writing-plans.

## Objetivo

Completar a integração do projeto **fedora-bootc-niri-qs-base** com o niri, eliminando as últimas dependências de software/estado Hyprland que restam no runtime:

1. **Wallpaper**: substituir o pipeline `awww`/`mpvpaper` (Hyprland) por **`swaybg`**, imagem por imagem, sem transição e sem vídeo. A provisão de novas imagens pela pill continua funcionando (set single/random/`all`) com mapa por output persistido em estado.
2. **Idle/Lock**: trocar `hypridle` por **`swayidle`** (3-4 timeouts + `before-sleep`) e portar `lock.sh` para `niri msg`. O shell de lock quickshell passa a ser spawnado no startup (hoje não é, então o discharge do trigger não monta o lock — bug corrente).
3. **Night light**: trocar `hyprsunset` por **`gammastep`**, config-driven (`dawn-time`/`dusk-time`).
4. **Surfaces de settings**: portar `Appearance` (reload), `Input` (edita `~/.config/niri/input.kdl`), criar surface **Night light** própria; **remover** as surfaces Hyprland-only (Look, Animation) e o **módulo Updates.**

## Decisões já tomadas

- **Apenas estáticas**: vídeos (`.mp4/.webm/.mkv/.mov`) deixam o bag, o strip e o search. `wallpaper-search.sh` perde o modo `motion`; `wallpaper-thumbs.sh` para de gerar thumbs de vídeo.
- **Escopo das surfaces**: **Core + Input port** (aprovado). Surface nova *Night light* (gammastep). Look/Animation removidas (Hyprland-only). Updates removido por completo.
- **Scripts** vão para **`/etc/niri/scripts`** (mesmo local de `power-autoswitch.sh`/`battery-limit.sh`); as referências QML passam a caminhos absolutos.
- **Input** editado fica em **`~/.config/niri/input.kdl`**, `include`d no fim de `/etc/niri/config.kdl` (merge simples, watched pelo niri).
- **Reload de config** = **`niri msg action load-config-file --path /etc/niri/config.kdl`** (ação confirmada no niri-ipc 26.4+); remove `hyprctl reload`.

## Restrições verificadas (fontes oficiais, 2026-08-11)

- **swaybg**: imagem por output com `swaybg -o A -i a.png -o B -i b.png` (cada `-i` pertence à última `-o`); NÃO é singleton com auto-saída — o novo apply deve `pkill -x swaybg` antes de spawnar. Não re-lê o arquivo se o ficheiro mudar.
- **swayidle**: eventos na CLI e no config (`~/.config/swayidle/config`); `timeout <s> <cmd> [resume <cmd>]`, repetível; `before-sleep <cmd>` (com `-w` bloqueia até a lock terminar). O pacote Fedora **não** instala unit systemd — a unit é autoral (`swayidle.service`, `Type=simple`, `ExecStart=swayidle -w`).
- **gammastep**: `~/.config/gammastep/config.ini` com `[general]`; `dawn-time`/`dusk-time` (ambos obrigatórios quando setados — substituem o agendamento solar) e `temp-day`/`temp-night`. Não tem IPC; reaplica-se só **reiniciando** a unit. O pacote **instala** `/usr/lib/systemd/user/gammastep.service`.
- **niri**: `niri msg --json outputs` → objeto com chave por nome de output (`outputs()` no script = `jq keys`). `--json workspaces` tem `is_active`. **`load-config-file`** é a única ação de reload. `power-off-monitors`/`power-on-monitors` existem (DPMS). `include` é o keyword de import (vive a partir de 25.11; `optional=true` e `~` a partir de 26.04); includes são watched.
- **niri input, exato**: `accel-speed` (-1..1, pad 0), `accel-profile` ("adaptive" pad / "flat"); `keyboard { repeat-delay (600ms), repeat-rate (25/s) }`; `keyboard { xkb { layout } }`; `keyboard { numlock }` (flag, só no startup); `cursor { xcursor-theme "default", xcursor-size 24 }` no **top-level** (não dentro de `input`). Todos live-reload (numlock: só startup).
- **material na pill**: `wallcolors.py` usa `magick` (está no `wallpaper-thumbs`/`wallpaper-search`/`cliphist-thumbs` via `MAGICK_CONFIGURE_PATH`); `make_still`/`rec-thumbs` usam `ffmpeg`. Nenhum dos dois está no Containerfile hoje.

## Mudanças

### 1. Containerfile (pacotes)

Adicionar a `dnf install`:

- `swayidle`
- `gammastep`
- `ImageMagick` (binário `magick`)
- `ffmpeg-free` (binário `ffmpeg`)

(`swaybg` e `grim` já estão instalados.)

### 2. Unidades systemd (user) e spawn

- **Autoriais** em `system_files/etc/systemd/user/`: `swayidle.service` (`ExecStart=/usr/bin/swayidle -w`, lê `~/.config/swayidle/config`) e `gammastep.service` (idem ao unit enviado pelo pacote, apontando para `~/.config/gammastep/config.ini`).
- Habilitar na build: `systemctl enable swayidle.service gammastep.service`.
- `/etc/niri/config.kdl`: trocar `spawn-at-startup "swww-daemon"` por:
  - `/etc/niri/scripts/wallpaper.sh init` (restaura o mapa de wallpapers; encerra caso nenhum),
  - spawn do quickshell do lock (surface em `/etc/quickshell/topbar/lock/shell.qml`) **antes** da pill — corrige o bug atual em que `ricelin-lock-trigger` nunca monta o lock,
  - spawn de `swayidle` e `gammastep` quando os units não estiverem ativos no ciclo de sessão (fallback; o caminho canônico é o user-unit).
- Binds niri: `Mod+Alt+L` passa a invocar `/etc/niri/scripts/lock.sh` (hoje shelf de hyprlock inexistente).

### 3. Scripts em `/etc/niri/scripts`

Copiar de `hypr/scripts/`: `wallpaper.sh` (portado), `lock.sh` (portado), `wallpaper-thumbs.sh`, `wallpaper-search.sh`, `app-install.sh`, `appimage-install.sh`, `rec-thumbs.sh`, `cliphist-thumbs.sh`, `wallcolors.py`, `magick-policy/`.

- **`wallpaper.sh` portado**: `outputs()` vira `niri msg -j outputs | jq -r 'keys[]'`; `cursor_output()` deixa de usar `hyprctl cursorpos` (falha suave para `focused`); `apply_visual()` = `pkill -x swaybg; spawn `swaybg -o <out> -i <pic>` (todos os outputs num único spawn); **sem** vídeo (`is_video`/`mpvpaper`/`make_still`/`sync_videos` removidos) e **sem** transition; `palette_update()` igual, mas troca `hyprctl reload` por `niri msg action load-config-file`, mantendo o `busctl` do ghostty.
  - Índice "resolve": manter (QML do strip usa o dir resolvido para listar o `wpdir`).
- **`lock.sh` portado**: `hyprctl monitors -j` → `niri msg -j outputs | jq -r 'keys[]'`; `grim -o "$out"` e trigger file inalterados.
- **`wallpaper-thumbs.sh` / `wallpaper-search.sh`**: caminho do `magick-policy` relativo ao novo `$(dirname "$0")` (continua funcionando); excluir extensões de vídeo da lista; remover o modo `motion`.
- **`app-install.sh`/`appimage-install.sh`/`rec-thumbs.sh`/`cliphist-thumbs.sh`/`wallcolors.py`**: só mudam os paths internos em relação a `dirname "$0"` e não referenciam Hyprland — vão como estão.

### 4. QML — paths e `Settings`

- Trocar em todos os QML `Quickshell.env("HOME") + "/.config/hypr/scripts/<x>"` por `"/etc/niri/scripts/<x>"`, inclusive `Launcher.qml` (appinstall), `Pill.qml` (install), `IdleLock.qml`, `Power.qml` (lock), `ScreenRec.qml`/`Singletons/ScreenRec.qml` (rec-thumbs), `Cliphist.qml` (cliphist-thumbs), `Walls.qml` (wallpaper/thumbs), `Wallpaper.qml` (search), `Appearance.qml` (wallcolors).
- **`Settings.qml`**: rows = `Appearance`, `Input`, `Idle / Lock`, **`Night light`** (nova). Removidas: `Look`, `Animation`, `Updates` (e a row já comentada de Display). Update helpEntries/`Table` que apontavam para files Hyprland.
- **`Pill.qml`**: remover os `LoadedComponent`/lógicos de `Look`, `AnimationSurface`, `Updates` (e Display/Keybinds já inertes se referenciados).
- **`Appearance.qml`**: comando de re-apply de paleta troca `hyprctl reload` por `niri msg action load-config-file --path /etc/niri/config.kdl`; mantém `busctl … ghostty reload-config`. Se a surface exibir um path de config, apontar para `/etc/niri/config.kdl`.

### 5. Idle/Lock → swayidle

- **`IdleLock.qml`** reescrito: gera `~/.config/swayidle/config` a partir dos 3 flags (lock, screen-off, suspend):
  ```
  timeout <lockMin*60> /etc/niri/scripts/lock.sh
  timeout <screenOffMin*60> niri msg action power-off-monitors resume niri msg action power-on-monitors
  timeout <suspendMin*60> systemctl suspend
  before-sleep /etc/niri/scripts/lock.sh
  ```
  (timeouts zero ficam de fora; `before-sleep` sempre, se lock ativada), e aplica com `systemctl --user restart swayidle.service`.
- Flags persistentes (heurs) ficam em `flags.json` como hoje; o `IdleLock` continua sendo surface `SettingsSurface` com a mesma UI de 3 `SettingsSeg`.

### 6. Night light → gammastep

- **`Singletons/NightLight.qml`** reescrito: states `off/on/scheduled` (Flags atuais); `on` grava `temp-day = temp-night = nightLightTemp`; `scheduled` grava `dawn-time = onMin`, `dusk-time = offMin`, `temp-day = 6500`, `temp-night = nightLightTemp`; `off` usa `temp-day = temp-night = 6500` (identity). Aplica com `systemctl --user restart gammastep.service`.
- Nova **surface** `NightLightSurface.qml` (ou rows reaproveitadas na `Appearance` — decisão do plano) com mode/temp/on/off; registrada no `Settings.qml` e no `Pill.qml`.

### 7. Remoção do módulo Updates

- Deletar `system_files/etc/quickshell/topbar/pill/Updates.qml`; remover referências em `Settings.qml` e `Pill.qml`; remover `system_files/etc/niri/scripts/ricelin-update.py` (e `test_ricelin_update.py`) do copiável.
- Atualizações passam a ser responsabilidade do bootc (`bootc upgrade`), coerente com a imagem imutável.

### 8. Outros ajustes de arch expostos

- `lib/monitors.js`, `lib/setInput.js`, `lib/setDeco.js`, `lib/setAnim.js`, `lib/binds.js`: os dois últimos `setDeco`/`setAnim` morrem com Look/Animation. `setInput.js` é substituído por escrita do include; `monitors.js` só é usado por Display (removida) → podem ser deletados.
- `Display.qml`, `Keybinds.qml`, `Workspaces.qml`, `AppPickerList.qml`/ecossistema stash: não reachable; remover se o plano confirmar que `Pill.qml` não os referencia ativamente.

## Exclusões (fora de escopo)

- Cor/layout dinâmico do **niri config via wallcolors** (focus-ring/etc. continuam as cores atuais do `config.kdl`). Deixar claro como follow-up.
- `Keybinds.qml` portado para o niri (binds já editados à mão no `config.kdl`).
- Suporte a vídeos como wallpaper (decisão "stills only").
- Gestão de atualização in-app (substituída por bootc).

## Riscos e mitigação

1. **`include` em config**: se a `niri` em uso no COPR não tiver `include` (≤25.11) ou `~` (≤26.04), o Input surface não aplica. Mitigação: verificar a versão no build e, se necessário, usar caminho absoluto fixo `/etc/niri/input.kdl` gravável pelos QML (chown/chmod via imagem) — decisão de implementação a registrar.
2. **`numlock`/cursor theme** mudam apenas no reload total: são reaplicadas no `load-config-file`, então o apply funciona; numlock é aplicado "apenas no startup" segundo a documentação do niri — revisar no teste real.
3. **swayidle/gammastep sob ciclo de sessão**: se `graphical-session.target` não for iniciado pelo sddm-niri, os spawns do §2 fazem fallback. Sem risco de dois daemons: `pkill` antes do spawn no script de boot.
4. **swaybg antigo**: `pkill -x swaybg` no apply; nada de singleton no swaybg (verificado).
5. **Remoção do Updates**: nenhum outro código referencia `Updates.qml` além de `Settings.qml`/`Pill.qml` a remover.

## Follow-ups (documentados, não implementados agora)

- Deixar o `config.kdl` temático via wallcolors (gerar paleta por include).
- Night light dentro do `Appearance` como grupo da propia surface (reduz 1 row).
- Portar `Keybinds.qml` para editar `binds` do niri por IPC.