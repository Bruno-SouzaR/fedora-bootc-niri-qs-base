# Integração final com niri (swaybg + settings) — Implementation Plan

> **Para agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para implementar este plano tarefa por tarefa. Passos usam checkbox (`- [ ]`) para rastreio.

**Goal:** Trocar o backend de wallpaper para `swaybg` (ainda por output, sem vídeo), substituir `hypridle`→`swayidle` e `hyprsunset`→`gammastep`, portar os scripts para `niri msg`, e remover as surfaces Hyprland-only (`Look`, `Animation`, `Updates`) da pill em favor de `Night light` própria e `Input` editando `~/.config/niri/input.kdl`.

**Architecture:** Pacotes/units novas transbordam no Containerfile; scripts sobem para `/etc/niri/scripts` (aplicados via `system_files/`). `wallpaper.sh` vira um comando `niri msg outputs` + single-instance `swaybg`; `IdleLock.qml` escreve `~/.config/swayidle/config`; `NightLight.qml` escreve `~/.config/gammastep/config.ini`. As surfaces removidas somem de `Settings.qml`/`Pill.qml`.

**Tech Stack:** bash/sh, swaybg, swayidle, gammastep, niri-msg IPC, ImageMagick (`magick`), ffmpeg, Quickshell QML6, systemd user units.

## Global Constraints

- Rede de verificação: **host de dev não tem `quickshell`/`niri`/`node`/`jq`/`swaybg`**; validação de QML/scripts acontece no **sistema alvo** (bootc image) ou por inspeção estática (grep/diff). Se `node --version` falhar no host, pule os passos que exigem node (os testes `.mjs` são bônus e void no CI do host).
- Todos os commands de shell de verificação neste plano rodam **com `bash`** (o zsh do host não tem `rg` etc. — usar `grep -rn`, não `rg`).
- NÃO usar `awww`/`mpvpaper`/`swww`/`hyprctl`/`hypridle`/`hyprsunset` em código novo/lived. Grep final (`grep -rn 'hyprctl\|awww\|mpvpaper\|hypridle\|hyprsunset\|swww' system_files/etc`) deve mostrar só comentários/nomes de arquivos auxiliares internos permitidos.
- `config.kdl` NÃO é mais readonly neste plano: vamos editá-lo (spawns, binds).
- Scripts no container são **root-owned, read-only** (`/etc/niri/scripts`); QMLs escrevem apenas sob `$XDG_CONFIG_HOME`/`$XDG_STATE_HOME` do usuário (configs de swayidle/gammastep/input.kdl).
- Quando um test code acabar em comentário: manter o estilo dos vizinhos (JC/## docs no topo), sem comentários de bate-estaca.
- Commits por tarefa, mensagens em português, estilo do repo (`git log --oneline`).

---

## File Structure

**Criados:**
- `system_files/etc/systemd/user/swayidle.service`
- `system_files/etc/niri/scripts/{wallpaper.sh,lock.sh,wallpaper-thumbs.sh,wallpaper-search.sh,app-install.sh,appimage-install.sh,rec-thumbs.sh,cliphist-thumbs.sh,wallcolors.py,magick-policy/policy.xml}` (movidos de `hypr/scripts/`, portados conforme as tasks)
- `system_files/etc/quickshell/topbar/pill/NightLightSurface.qml`
- (opcional, offline) `system_files/etc/quickshell/topbar/pill/lib/wallapply.js` + `wallapply.test.mjs` — testes do resolver de piada; só se `node` existir no host.

**Editados:**
- `Containerfile` (pacotes + enable units)
- `system_files/etc/niri/config.kdl` (spawns swaybg/lock/daemons; binds)
- `system_files/etc/niri/scripts/*` (paths do `magick-policy`, appimage-install, QML não — ver tasks)
- `hypr/scripts/` — **remover o diretório inteiro** do repo
- `system_files/etc/quickshell/topbar/pill/{Walls.qml,Wallpaper.qml,Appearance.qml,IdleLock.qml,Input.qml,Settings.qml,Pill.qml}`
- `system_files/etc/quickshell/topbar/pill/Singletons/{NightLight.qml,Flags.qml}`
- `system_files/etc/quickshell/topbar/pill/{Look.qml,AnimationSurface.qml,Updates.qml}` → **deletados**
- `system_files/etc/quickshell/topbar/pill/lib/{setDeco.js,setAnim.js}` → **deletados**

---

### Task 1: Pacotes, units e enable no Containerfile

**Files:**
- Modify: `Containerfile` (bloco `dnf install`, apex do `RUN systemctl enable`)

**Interfaces:**
- Produces: binarys `swayidle`, `gammastep`, `magick`, `ffmpeg` presentes na imagem na hora do runtime; units `swayidle.service` e `gammastep.service` instaladas em `/etc/systemd/user/`.

- [ ] **Step 1:** Adicionar 4 pacotes ao `dnf install` do Containerfile (manter ordem atual, inserir antes de `power-profiles-daemon`):

```diff
     pipewire-pulseaudio \
     polkit-kde-agent-1 \
     fprintd-pam \
+    swayidle \
+    gammastep \
+    ImageMagick \
+    ffmpeg-free \
     ghostty \
```

- [ ] **Step 2:** Habilitar as units no `RUN systemctl enable` final:

```diff
-RUN systemctl enable sddm.service power-profiles-daemon.service
+RUN systemctl enable sddm.service power-profiles-daemon.service swayidle.service gammastep.service
```

- [ ] **Step 3:** Verificar staticamente sem pacote instalado (não há `dnf` no host de dev): conferir que os 4 nomes batem com os do spec (swayidle, gammastep, ImageMagick, ffmpeg-free) e que `swaybg`/`grim` já constam na lista (não adicionar duplicado).

- [ ] **Step 4:** Commit.

```bash
git add Containerfile
git commit -m "Containerfile: instala swayidle, gammastep, ImageMagick e ffmpeg-free e habilita as units de usuário"
```

---

### Task 2: Units systemd de usuário (swayidle + gammastep)

**Files:**
- Create: `system_files/etc/systemd/user/swayidle.service`
- Create: `system_files/etc/systemd/user/gammastep.service`

**Interfaces:**
- Produces: units que `systemctl --user restart swayidle.service|gammastep.service` (usado por IdleLock/NightLight nas Tasks 8/9) conseguem reaplicar. Cada unit lê o proprio config do usuário por default.

- [ ] **Step 1:** Criar `swayidle.service`:

```
[Unit]
Description=Sway idle daemon - autolock and screen blanking
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/swayidle -w
Restart=on-failure

[Install]
WantedBy=graphical-session.target
```

- [ ] **Step 2:** Criar `gammastep.service` (espelho do unit enviado pelo pacote; `-w` não aplica — manter só `ExecStart=/usr/bin/gammastep`; o daemon lê `~/.config/gammastep/config.ini` por default):

```
[Unit]
Description=Display colour temperature adjustment
PartOf=graphical-session.target
After=graphical-session.target

[Service]
ExecStart=/usr/bin/gammastep
Restart=on-failure

[Install]
WantedBy=graphical-session.target
```

- [ ] **Step 3:** Verificação estática: `grep -c 'WantedBy=graphical-session.target' system_files/etc/systemd/user/*.service` → 2; os [Unit] não têm ordens inventadas.

- [ ] **Step 4:** Commit.

```bash
git add system_files/etc/systemd/user/swayidle.service system_files/etc/systemd/user/gammastep.service
git commit -m "systemd: units de usuário para swayidle e gammastep"
```

---

### Task 3: Copiar scripts para `/etc/niri/scripts` e remover `hypr/`

**Files:**
- Create (cópia literal): `system_files/etc/niri/scripts/{app-install.sh,appimage-install.sh,rec-thumbs.sh,cliphist-thumbs.sh,wallpaper-search.sh,wallcolors.py,magick-policy/policy.xml}`
- Delete: `hypr/` (todo o diretório — scripts-fonte untracked do pipeline antigo)

**Interfaces:**
- Produces: caminho único e root-owned `/etc/niri/scripts/*`. As Tasks 5/6 portam `wallpaper.sh`/`lock.sh`; `wallpaper-search.sh` é republicado na Task 7.

- [ ] **Step 1:** Copiar de `hypr/scripts/` para `system_files/etc/niri/scripts/` os arquivos **sem mudança de conteúdo**: `app-install.sh`, `appimage-install.sh`, `rec-thumbs.sh`, `cliphist-thumbs.sh`, `wallcolors.py`, `wallpaper-search.sh` (refeito na Task 7), `magick-policy/policy.xml`. Rodar com `git mv` para manter o histórico por arquivo e revisar o diff depois:

```bash
mkdir -p system_files/etc/niri/scripts/magick-policy
git mv hypr/scripts/app-install.sh system_files/etc/niri/scripts/
git mv hypr/scripts/appimage-install.sh system_files/etc/niri/scripts/
git mv hypr/scripts/rec-thumbs.sh system_files/etc/niri/scripts/
git mv hypr/scripts/cliphist-thumbs.sh system_files/etc/niri/scripts/
git mv hypr/scripts/wallcolors.py system_files/etc/niri/scripts/
git mv hypr/scripts/wallpaper-search.sh system_files/etc/niri/scripts/
git mv hypr/scripts/magick-policy/policy.xml system_files/etc/niri/scripts/magick-policy/
git mv hypr/scripts/wallpaper-thumbs.sh system_files/etc/niri/scripts/
```

- [ ] **Step 2 (Vital):** adaptar **todos** os scripts que derivam o dir de si próprios. Nenhum script usa `$HOME` para localizar o próprio dir — apenas `$(dirname "$0")`. Conferir:

```bash
grep -rn 'dirname "$0"' system_files/etc/niri/scripts
```

Cada hit que aponte para `/magick-policy` ou para um script irmão permanece correto: como tudo vive no mesmo dir (`/etc/niri/scripts`), o `dirname "$0"` já resolve para `magick-policy`, `appimage-install.sh`, etc.

- [ ] **Step 3:** Remover o `hypr/` restante (script de teste do update engine e orfãos não usados) do repo:

```bash
git rm -r hypr/ 2>/dev/null || rm -rf hypr/
```

Se `hypr/` não estiver no índice (untracked), `git rm` falha — usar `rm -rf hypr/` e seguir.

- [ ] **Step 4:** Commit.

```bash
git add -A
git commit -m "scripts: move pipeline para /etc/niri/scripts e remove hypr/"
```

---

### Task 4: Portar `config.kdl` — spawns e bind de lock

**Files:**
- Modify: `system_files/etc/niri/config.kdl` (bloco `spawn-at-startup`, binds)

**Interfaces:**
- Produces: `wallpaper.sh init` restaura wallpaper no boot; quickshell lock surface spawnado (corrige `ricelin-lock-trigger` que hoje não monta o lock); `swayidle`/`gammastep` iniciados quando os units ainda não estão no ciclo do SDDM; `Mod+Alt+L` chama `lock.sh`.

- [ ] **Step 1:** Trocar o `spawn-at-startup "swww-daemon"` (linha ~30) por quatro spawns: o `wallpaper.sh init` (antes do quickshell), o spawn do lock shell, e os dois daemons:

```diff
-// Inicializações do sistema
-spawn-at-startup "swww-daemon"
+// Inicializações do sistema
+spawn-at-startup "/etc/niri/scripts/wallpaper.sh" "init"
+spawn-at-startup "systemctl" "--user" "start" "swayidle" "gammastep"
+spawn-at-startup "quickshell" "-c" "/etc/quickshell/topbar/lock/shell.qml"
 spawn-at-startup "/etc/niri/scripts/power-autoswitch.sh"
 spawn-at-startup "quickshell" "--path" "/etc/quickshell/topbar/pill"
 spawn-at-startup "quickshell" "--path" "/etc/quickshell/topbar/launcher"
```

> Nota: se o `systemctl --user start` falhar porque a sessão do SDDM não ativa `graphical-session.target`, o spawn morre quieto e a Task 11 introduz o `niri-session.target`. Não bloquear aqui.

- [ ] **Step 2:** Reapontar o bind de lock (linha ~163):

```diff
-    Mod+Alt+L { spawn "sh" "-c" "quickshell -b qylock -c ~/.config/quickshell/qylock/main.qml"; }
+    Mod+Alt+L { spawn "/etc/niri/scripts/lock.sh"; }
```

- [ ] **Step 3:** Verificação estática: `grep -n 'swayidle\|gammastep\|wallpaper.sh\|quickshell.*lock\|lock.sh' system_files/etc/niri/config.kdl` → 5 hits esperados. Nada de `swww-daemon|hyprlock|qylock`.

- [ ] **Step 4:** Commit.

```bash
git add system_files/etc/niri/config.kdl
git commit -m "niri config: spawns de wallpaper/lock/daemons e bind de bloqueio via lock.sh"
```

---

### Task 5: Portar `wallpaper.sh` para swaybg (stills-only)

**Files:**
- Create: `system_files/etc/niri/scripts/wallpaper.sh` (substitui o origem do pipeline antigo; o antigo é removido na Task 3 — criar aqui o novo conteúdo)
- (opcional) Create: `system_files/etc/quickshell/topbar/pill/lib/wallapply.js` + `lib/wallapply.test.mjs` — resolver de "piada do dia" testável em node

**Interfaces:**
- Consumes: `niri msg -j outputs` (objeto chaveado por output name); `flags.json` (`randomScope`, `paletteMode`, `wallpaperDir`, `manualHue`, `manualDark`); `wallcolors.py`; `grim` não (só no lock.sh).
- Produces: saída via `stdout` do `set`/`resolve`; grava `$XDG_STATE_HOME/ricelin-wallpaper` (still atual), `ricelin-wallpaper-bag` (fila shuffle), `ricelin-wallpaper-map` (output→pic), `ricelin-wallpaper-dir`, e para `niri msg action load-config-file`.
- O QML `Walls.qml` consome: `set <pic> [out]` e `resolve` (interface inalterada).

- [ ] **Step 1 (offline, só se `node` existe no host):** escrever um teste node para a regra de ramificação do scroll (a piada "nunca repete o atual"): o resolver puro recebe `(bag, current, scope, outputs)` e devolve a próxima piada + flag de refill. Teste:

```js
// lib/wallapply.test.mjs
import test from "node:test";
import assert from "node:assert";
import { pickNext } from "./wallapply.js";

test("still bag: never returns the current first", () => {
  const bag = ["a.jpg", "b.jpg", "c.jpg"];
  assert.equal(pickNext(bag, "a.jpg", "all", ["DP-1", "eDP-1"]).next, "b.jpg");
});
test("when the bag only has the current, it repeats it", () => {
  assert.equal(pickNext(["a.jpg"], "a.jpg", "all", ["DP-1"]).next, "a.jpg");
});
test("empty bag yields empty", () => {
  assert.equal(pickNext([], "a.jpg", "all", ["DP-1"]).next, "");
});
```

- [ ] **Step 2:** rodar o teste e confirmar que falha (`lib/wallapply.js` inexistente):

Run: `node system_files/etc/quickshell/topbar/pill/lib/wallapply.test.mjs`
Expected: FAIL com módulo não encontrado.

- [ ] **Step 3:** escrever `lib/wallapply.js` (função pura; sem depender de `niri`):

```js
"use strict";

/** Picks the next still wallpaper from a shuffle bag, never repeating the
 * current one when the bag holds more than just it. Used by wallpaper.sh. */
export function pickNext(bag, current, _scope, outputs) {
  if (!bag || bag.length === 0) return { next: "", bag: bag };
  const rest = bag.filter((p) => p !== current);
  const next = rest.length > 0 ? rest[0] : bag[0];
  return { next, bag };
}
```

- [ ] **Step 4:** rodar o teste de novo → DELETE.

Run: `node system_files/etc/quickshell/topbar/pill/lib/wallapply.test.mjs` → PASS (3/3).
Se `node` não existir no host, pular passos 1-4 sem deixar resquício.

- [ ] **Step 5:** escrever o `wallpaper.sh` não-gerado completo, substituindo o anterior. Conteúdo:

```bash
#!/usr/bin/env bash
set -euo pipefail

flags_file="${XDG_STATE_HOME:-$HOME/.local/state}/ricelin/flags.json"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/ricelin-wallpaper"
MAP="${XDG_STATE_HOME:-$HOME/.local/state}/ricelin-wallpaper-map"
BAG="${XDG_STATE_HOME:-$HOME/.local/state}/ricelin-wallpaper-bag"
WLOG="${XDG_STATE_HOME:-$HOME/.local/state}/ricelin/wallcolors.log"

WPDIR=$(jq -r '.wallpaperDir // ""' "$flags_file" 2>/dev/null || echo "")
if [ -z "$WPDIR" ]; then
    for cand in "$HOME/Pictures/Wallpapers" "$HOME/Pictures/wallpapers" "$HOME/Wallpapers" "$HOME/wallpapers"; do
        [ -d "$cand" ] || continue
        n=$(find "$cand" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.webp' \) | head -2 | wc -l)
        if [ "$n" -ge 2 ]; then WPDIR="$cand"; break; fi
    done
    [ -n "$WPDIR" ] || WPDIR="$HOME/Ricelin/wallpapers"
fi
printf '%s\n' "$WPDIR" > "${XDG_STATE_HOME:-$HOME/.local/state}/ricelin-wallpaper-dir"
[ "${1:-}" = "resolve" ] && exit 0

list_pics() {
    find "$WPDIR" -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.webp' \)
}

refill_bag() {
    local current="" shuffled
    mkdir -p "$(dirname "$BAG")"
    [ -r "$STATE" ] && current=$(cat "$STATE")
    shuffled=$(list_pics | shuf)
    [ -n "$shuffled" ] || return 0
    if [ "$(printf '%s\n' "$shuffled" | head -n1)" = "$current" ] && [ "$(printf '%s\n' "$shuffled" | wc -l)" -gt 1 ]; then
        shuffled=$(printf '%s\n' "$shuffled" | tail -n +2; printf '%s\n' "$current")
    fi
    printf '%s\n' "$shuffled" > "$BAG"
}

pop_bag() {
    local line refilled=false
    mkdir -p "$(dirname "$BAG")"
    (
        flock 9
        while :; do
            if [ ! -s "$BAG" ]; then
                [ "$refilled" = true ] && exit 1
                refill_bag
                refilled=true
                [ -s "$BAG" ] || exit 1
            fi
            line=$(head -n1 "$BAG")
            tail -n +2 "$BAG" > "$BAG.tmp" && mv "$BAG.tmp" "$BAG"
            if [ -f "$line" ]; then
                printf '%s\n' "$line"
                exit 0
            fi
        done
    ) 9>"$BAG.lock"
}

outputs() {
    niri msg -j outputs 2>/dev/null | jq -r 'keys[]'
}

map_get() {
    awk -F'\t' -v o="$1" '$1 == o { print $2; exit }' "$MAP" 2>/dev/null || true
}

map_put() {
    mkdir -p "$(dirname "$MAP")"
    { awk -F'\t' -v o="$1" '$1 != o' "$MAP" 2>/dev/null || true; printf '%s\t%s\n' "$1" "$2"; } > "$MAP.tmp"
    mv "$MAP.tmp" "$MAP"
}

map_put_all() {
    local o
    mkdir -p "$(dirname "$MAP")"
    : > "$MAP.tmp"
    for o in $(outputs); do
        printf '%s\t%s\n' "$o" "$1" >> "$MAP.tmp"
    done
    mv "$MAP.tmp" "$MAP"
}

# swaybg is not an auto-singleton: a fresh apply must kill the previous one
# before spawning, otherwise two instances fight over the same buffers.
apply_visual() {
    pkill -x swaybg 2>/dev/null || true
    for _ in $(seq 1 20); do pgrep -x swaybg >/dev/null 2>&1 || break; sleep 0.1; done
    local o pic args=()
    for o in $(outputs); do
        pic=$(map_get "$o")
        [ -n "$pic" ] || pic="$1"
        args+=(-o "$o" -i "$pic")
    done
    [ "${#args[@]}" -gt 0 ] || return 0
    setsid -f swaybg "${args[@]}" >/dev/null 2>&1 || true
}

# The palette follows the focused monitor, matched by name.
focused_output() {
    niri msg -j focused-output 2>/dev/null | jq -r '.name // empty'
}

# The palette follows the focused monitor: whatever hangs there drives matugen,
# the global state file and the global still.
palette_update() {
    local pmode focused pic mh md
    focused=$(focused_output)
    pic=""
    [ -n "$focused" ] && pic=$(map_get "$focused")
    [ -n "$pic" ] || pic=$(cat "$STATE" 2>/dev/null || true)
    [ -n "$pic" ] && [ -f "$pic" ] || return 0
    mkdir -p "$(dirname "$STATE")"
    printf '%s\n' "$pic" > "$STATE"
    pmode=$(jq -r '.paletteMode // "static"' "$flags_file" 2>/dev/null || echo static)
    mkdir -p "$(dirname "$WLOG")"
    if [ "$pmode" = "manual" ]; then
        mh=$(jq -r '.manualHue // 30' "$flags_file" 2>/dev/null || echo 30)
        md=$(jq -r 'if .manualDark == false then "light" else "dark" end' "$flags_file" 2>/dev/null || echo dark)
        python3 "$(dirname "$0")/wallcolors.py" --hue "$mh" "$md" >>"$WLOG" 2>&1 || true
    else
        python3 "$(dirname "$0")/wallcolors.py" "$pic" >>"$WLOG" 2>&1 || true
    fi
    niri msg action load-config-file --path /etc/niri/config.kdl >/dev/null 2>&1 || true
    busctl --user call com.mitchellh.ghostty /com/mitchellh/ghostty org.gtk.Actions \
        Activate "sava{sv}" reload-config 0 0 >/dev/null 2>&1 || true
}

restore_all() {
    local o pic any=false
    for o in $(outputs); do
        pic=$(map_get "$o")
        [ -n "$pic" ] && [ -f "$pic" ] || pic=$(cat "$STATE" 2>/dev/null || true)
        [ -n "$pic" ] && [ -f "$pic" ] || pic=$(pop_bag) || continue
        map_put "$o" "$pic"
        any=true
    done
    [ "$any" = true ] || exit 0
    apply_visual ""
    palette_update
    exit 0
}

cmd="${1:-}"
target=""

if [ "$cmd" = "init" ]; then
    if [ ! -s "$MAP" ] && [ -s "$STATE" ]; then
        pic=$(cat "$STATE")
        [ -f "$pic" ] && map_put_all "$pic"
    fi
    restore_all
elif [ "$cmd" = "set" ]; then
    pic="${2:-}"
    [ -f "$pic" ] || exit 1
    target="${3:-}"
    [ "$target" = "all" ] && target=""
else
    scope=$(jq -r '.randomScope // "all"' "$flags_file" 2>/dev/null || echo all)
    if [ "$scope" = "cursor" ]; then
        target=$(focused_output)
    fi
    pic=$(pop_bag) || exit 0
fi

[ -n "$pic" ] || exit 0

if [ -n "$target" ]; then
    map_put "$target" "$pic"
else
    map_put_all "$pic"
fi

apply_visual "$pic"
palette_update
```

- [ ] **Step 6:** Verificação estática (sem niri/swaybg no host): `bash -n system_files/etc/niri/scripts/wallpaper.sh` → sem erro de sintaxe; e `grep -c 'awww\|mpvpaper\|swww\|hyprctl' system_files/etc/niri/scripts/wallpaper.sh` → 0. Se node existe, rodar `node .../lib/wallapply.test.mjs`:

Run: `bash -n system_files/etc/niri/scripts/wallpaper.sh`
Expected: exit 0.

- [ ] **Step 7:** Commit (inclui o `lib/wallapply.js`+teste se criado):

```bash
git add system_files/etc/niri/scripts/wallpaper.sh system_files/etc/quickshell/topbar/pill/lib/wallapply.js system_files/etc/quickshell/topbar/pill/lib/wallapply.test.mjs
git commit -m "wallpaper.sh: porta para swaybg (stills-only) via niri msg"
```

---

### Task 6: Portar `lock.sh` para `niri msg` + grim por output

**Files:**
- Create: `system_files/etc/niri/scripts/lock.sh` (substitui o do pipeline antigo, já movido na Task 3)

**Interfaces:**
- Produces: grava clock de captura + toca `$XDG_RUNTIME_DIR/ricelin-lock-trigger`. Consumido por `Power.qml` e pelos timeouts de `swayidle`.

- [ ] **Step 1:** escrever o `lock.sh` (a única mudança é a listagem de outputs):

```sh
#!/bin/sh
umask 077
dir="${XDG_RUNTIME_DIR:-/tmp}"

# Grab every monitor first so the desktop is captured while it is still live and
# on screen, then lock. The lock surface reveals onto these grabs, so they must
# exist before it mounts.
for out in $(niri msg -j outputs 2>/dev/null | jq -r 'keys[]'); do
    [ -n "$out" ] || continue
    rm -f "$dir/ricelin-lock-$out.png"
    grim -o "$out" "$dir/ricelin-lock-$out.png" 2>/dev/null &
done
wait

# Poke the lock daemon through its file watch instead of spawning a whole qs client.
date +%s%N > "$dir/ricelin-lock-trigger"
```

- [ ] **Step 2:** Verificação: `sh -n system_files/etc/niri/scripts/lock.sh` → exit 0; `grep -c hyprctl system_files/etc/niri/scripts/lock.sh` → 0.

- [ ] **Step 3:** Commit.

```bash
git add system_files/etc/niri/scripts/lock.sh
git commit -m "lock.sh: lista outputs via niri msg e mantém o trigger do lock quickshell"
```

---

### Task 7: `wallpaper-search.sh` — remover o modo motion/vídeo

**Files:**
- Modify: `system_files/etc/niri/scripts/wallpaper-search.sh`

**Interfaces:**
- Produces: `search <q>` devolve só resultados estáticos (`.gif` excluído), `download <url>` mantido idêntico; argumento `kind` removido. Consumido por `Wallpaper.qml` (Task 10).

- [ ] **Step 1:** remover a função `search_moewalls()` e o ramo `[ "$kind" = "motion" ]`; a função `search` fica:

```bash
search() {
    local query="${1:-}"
    [ -n "$query" ] || { printf '[]\n'; return 0; }

    local enc vqd raw
    enc=$(jq -rn --arg q "$query" '$q|@uri') || { printf '[]\n'; return 0; }

    vqd=$(curl -s --max-time 10 "https://duckduckgo.com/?q=${enc}&iax=images&ia=images" -A "$UA" \
        | grep -oP 'vqd=\\?"?\K[0-9-]+' | head -1)
    [ -n "$vqd" ] || { printf '[]\n'; return 0; }

    raw=$(curl -s --max-time 10 \
        "https://duckduckgo.com/i.js?l=us-en&o=json&q=${enc}&vqd=${vqd}&f=type:photo&p=-1" \
        -A "$UA" -H "Referer: https://duckduckgo.com/")
    [ -n "$raw" ] || { printf '[]\n'; return 0; }

    printf '%s' "$raw" | jq -c '
        (.results // [])
        | map(select(.image // "" | test("\\.gif(\\?|$)"; "i") | not))
        | map(select(.image != null and .image != ""))
        | .[0:60] | map({
            image: .image,
            thumb: (.thumbnail // .image),
            w: (.width // 0 | if . == null then 0 else . end),
            h: (.height // 0 | if . == null then 0 else . end)
          })
    ' 2>/dev/null || printf '[]\n'
}
```

- [ ] **Step 2:** ajustar o case final (remover o segundo arg):

```bash
case "${1:-}" in
    search)   search "${2:-}" ;;
    download) download "${2:-}" ;;
    *)        printf '[]\n'; exit 0 ;;
esac
```

Manter `UA` e `download()` intactos (inclusive o `magick-policy`).

- [ ] **Step 3:** Verificação: `bash -n system_files/etc/niri/scripts/wallpaper-search.sh` → 0; `grep -c moewalls system_files/etc/niri/scripts/wallpaper-search.sh` → 0.

- [ ] **Step 4:** Commit.

```bash
git add system_files/etc/niri/scripts/wallpaper-search.sh
git commit -m "wallpaper-search: only stills (sem moewalls/motion)"
```

---

### Task 8: `IdleLock.qml` → `swayidle`

**Files:**
- Modify: `system_files/etc/quickshell/topbar/pill/IdleLock.qml` (buildConf, apply, confPath, restart)

**Interfaces:**
- Consumes: `Flags.idleLockMin|idleScreenOffMin|idleSuspendMin`; `/etc/niri/scripts/lock.sh`; actions niri `power-off-monitors`/`power-on-monitors`.
- Produces: `~/.config/swayidle/config` + `systemctl --user restart swayidle.service`. A UI (rows/labels/seg) não muda.

- [ ] **Step 1:** editar as duas propriedades de estado:

```diff
-    readonly property string confPath: Quickshell.env("HOME") + "/.config/hypr/hypridle.conf"
-    readonly property string lockScript: Quickshell.env("HOME") + "/.config/hypr/scripts/lock.sh"
+    readonly property string confPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/swayidle/config"
+    readonly property string lockScript: "/etc/niri/scripts/lock.sh"
```

- [ ] **Step 2:** substituir `buildConf()` (páginas 52-79) pela versão swayidle:

```js
    /** Builds ~/.config/swayidle/config from the three flag values. Each
     * timeout only appears for its non-zero minute setting; the resume clause
     * that re-powers the monitors rides on the screen-off timeout, and
     * before-sleep always locks so a lid/suspend can't skip the gate. */
    function buildConf() {
        var out = "";
        if (Flags.idleLockMin > 0)
            out += "timeout " + (Flags.idleLockMin * 60) + " " + root.lockScript + "\n";
        if (Flags.idleScreenOffMin > 0)
            out += "timeout " + (Flags.idleScreenOffMin * 60)
                + " niri msg action power-off-monitors"
                + " resume niri msg action power-on-monitors\n";
        if (Flags.idleSuspendMin > 0)
            out += "timeout " + (Flags.idleSuspendMin * 60) + " systemctl suspend\n";
        if (Flags.idleLockMin > 0)
            out += "before-sleep " + root.lockScript + "\n";
        return out;
    }
```

- [ ] **Step 3:** trocar o restart:

```diff
     Process {
         id: restartProc
-        command: ["systemctl", "--user", "restart", "hypridle"]
+        command: ["systemctl", "--user", "restart", "swayidle"]
     }
```

- [ ] **Step 4:** atualizar o comentário de topo do arquivo (linhas 8-16) para "three idle events that drive swayidle ... restarts swayidle" — texto adaptado, sem mencionar hypridle.

- [ ] **Step 5:** Verificação: `grep -c 'hypridle\|hyprctl' system_files/etc/quickshell/topbar/pill/IdleLock.qml` → 0; `grep -c 'power-off-monitors' system_files/etc/quickshell/topbar/pill/IdleLock.qml` → 2 (buildConf + comentário opcional ok).

- [ ] **Step 6:** Commit.

```bash
git add system_files/etc/quickshell/topbar/pill/IdleLock.qml
git commit -m "IdleLock: gera swayidle config e reinicia swayidle"
```

---

### Task 9: `NightLight` singleton → `gammastep` + nova `NightLightSurface.qml`

**Files:**
- Modify: `system_files/etc/quickshell/topbar/pill/Singletons/NightLight.qml`
- Create: `system_files/etc/quickshell/topbar/pill/NightLightSurface.qml`

**Interfaces:**
- Consumes: `Flags.nightLightMode|nightLightTemp|nightLightOnMin|nightLightOffMin`; `systemctl --user restart gammastep`.
- Produces: `~/.config/gammastep/config.ini`; claims `NightLight.setMode|setTemp|setOnMin|setOffMin` (nomes iguais aos do singleton atual, no qual _não_ vamos mexer na interface). A `NightLightSurface.qml` é a única calçada que consome.

- [ ] **Step 1:** reescrever `Singletons/NightLight.qml` (independente de compositor; as Flags e o capacitor de setTemp/setOnMin/setOffMin permanecem):

```qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * 灯 Night-light controller over gammastep. Every change rewrites
 * ~/.config/gammastep/config.ini from the Flags and restarts the user unit, so
 * the tint follows the clock on its own and survives a logout. Scheduled mode
 * maps dawn (day start) to the user's "off" clock and dusk (night start) to
 * their "on" clock — night is between on and off, day is the rest.
 */
Singleton {
    id: root

    readonly property string confPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/gammastep/config.ini"

    function clampTemp(t) {
        return Math.max(2200, Math.min(6500, Math.round(t)));
    }

    function hhmm(min) {
        var h = Math.floor(min / 60);
        var m = min % 60;
        return h + ":" + (m < 10 ? "0" + m : m);
    }

    /** gammastep config.ini for the current Flags. Off and On are one all-day
     * profile; Scheduled uses dawn-time/dusk-time so the daemon flips alone. */
    function buildConf() {
        var out = "[general]\n";
        if (Flags.nightLightMode === "scheduled") {
            out += "dawn-time=" + root.hhmm(Flags.nightLightOffMin) + "\n"
                + "dusk-time=" + root.hhmm(Flags.nightLightOnMin) + "\n"
                + "temp-day=6500\n"
                + "temp-night=" + root.clampTemp(Flags.nightLightTemp) + "\n";
        } else {
            var t = Flags.nightLightMode === "on" ? root.clampTemp(Flags.nightLightTemp) : 6500;
            out += "temp-day=" + t + "\n"
                + "temp-night=" + t + "\n";
        }
        return out;
    }

    function commit(restart) {
        writer.setText(root.buildConf());
        if (restart)
            restartProc.running = true;
    }

    function setMode(m) {
        Flags.nightLightMode = m;
        root.commit(true);
    }

    function setTemp(t) {
        Flags.nightLightTemp = root.clampTemp(t);
        root.commit(Flags.nightLightMode === "scheduled");
    }

    function setOnMin(v) {
        Flags.nightLightOnMin = v;
        root.commit(Flags.nightLightMode === "scheduled");
    }

    function setOffMin(v) {
        Flags.nightLightOffMin = v;
        root.commit(Flags.nightLightMode === "scheduled");
    }

    FileView {
        id: writer
        path: root.confPath
        atomicWrites: true
        printErrors: false
    }

    Process {
        id: restartProc
        command: ["systemctl", "--user", "restart", "gammastep"]
    }
}
```

- [ ] **Step 2:** criar `NightLightSurface.qml`: espelho estrutural do `IdleLock.qml` (SettingsSurface, SettingsHeader, settings segs). Reutilizar o componente `IdleRow`—no plano final, copiar a classe `IdleRow` do IdleLock para cá (não importar via `import` de IdleLock, que é um surface). Rows: mode (`off/on/scheduled`), temp (scrub range 2200-6500), on-time, off-time (scrub 0-1439, minutos). O seg de mode usa `onPicked: (v) => NightLight.setMode(v)`.

```qml
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "Singletons"

/**
 * 灯 NIGHT LIGHT sub-surface: the gammastep controls (on/off/scheduled, warmth,
 * and the two clock gates). Every change rewrites the config and restarts the
 * unit through the NightLight singleton, so the tint lands at once and survives
 * a logout. Reached from the settings index; morphs back on the back chevron.
 */
SettingsSurface {
    id: root

    backSurface: "settings"
    implicitHeight: content.implicitHeight

    readonly property var modeOptions: [
        { label: "Off", value: "off" }, { label: "On", value: "on" }, { label: "Scheduled", value: "scheduled" }
    ]

    rows: [
        { item: modeRow, kind: "seg", vals: root.modeOptions.map(function (o) { return o.value; }), get: function () { return Flags.nightLightMode; }, set: function (v) { NightLight.setMode(v); } },
        { item: tempRow, kind: "scrub", bump: function (d) { return NightLight.clampTemp(Flags.nightLightTemp + d); } },
        { item: onRow, kind: "scrub", bump: function (d) { return Math.max(0, Math.min(1439, Flags.nightLightOnMin + d)); } },
        { item: offRow, kind: "scrub", bump: function (d) { return Math.max(0, Math.min(1439, Flags.nightLightOffMin + d)); } }
    ]

    Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        SettingsHeader {
            s: root.s
            glyph: "灯"
            title: "NIGHT LIGHT"
            showBack: true
        }

        // (copiar aqui as IdleRow de IdleLock.qml, rotuladas Mode/Warmth/On/Off,
        //  com SettingsSeg/SettingsScrubValue pela interface padrão das settings)
    }
}
```

> Detalhe de implementação do executor: usar os mesmos componentes que IdleLock `SettingsSeg` para mode e `SettingsRow`/scrub (procurar em `SettingsScrub*` na árvore `pill/`) para temp/times, no mesmo cadinho visual. O bloco _content_ deve completar a coluna antes do fechamento.

- [ ] **Step 3:** Verificação: `grep -c 'hyprsunset\|hyprctl' system_files/etc/quickshell/topbar/pill/Singletons/NightLight.qml` → 0; `grep -c 'gammastep' system_files/etc/quickshell/topbar/pill/Singletons/NightLight.qml` → ≥ 2.

- [ ] **Step 4:** Commit.

```bash
git add system_files/etc/quickshell/topbar/pill/Singletons/NightLight.qml system_files/etc/quickshell/topbar/pill/NightLightSurface.qml
git commit -m "NightLight: porta para gammastep e adiciona surface própria"
```

---

### Task 10: `Wallpaper.qml` + `Walls.qml` — dropar striptease de vídeo e o filter de kind

**Files:**
- Modify: `system_files/etc/quickshell/topbar/pill/Walls.qml`
- Modify: `system_files/etc/quickshell/topbar/pill/Wallpaper.qml`

**Interfaces:**
- Consumes: `wallpaper-thumbs.sh` (não lista mais vídeos), `wallpaper-search.sh search <q>` (kind removido).
- Produces:  strip local e search **apenas** com estáticas; `kindFilter`/`isMotion`/preview de vídeo somem.

- [ ] **Step 1 (Walls.qml):** remover as extensões de vídeo do `listProc` (linha 129): o filtro passa a

```qml
        command: ["sh", "-c", "find \"$1\" -type f \\( -iname '*.jpg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.webp' \\) -printf '%T@\\t%p\\n' | sort -rn", "_", root.wpDir]
```

- [ ] **Step 2 (Walls.qml):** apontar os scripts para o novo local (linhas 39-40):

```qml
    readonly property string thumbScript: "/etc/niri/scripts/wallpaper-thumbs.sh"
    readonly property string setScript: "/etc/niri/scripts/wallpaper.sh"
```

e atualizar o comentário do topo que menciona transição awww ("blocks through the whole transition (awww wave, matugen, reload)" → "blocks through the whole apply (swaybg respawn, matugen, reload)").

- [ ] **Step 3 (Wallpaper.qml):** remover o `kindFilter`, `isMotion()`, e simplificar `localItems` (linhas 46-96) para

```qml
    readonly property var localItems: Walls.entries
```

e removê-lo da expressão `items` (linha 118) → `readonly property var items: (searching && query.length > 0) ? ddgResults : Walls.entries` (manter `onItemsChanged` do foco). Remover o handler `onKindFilterChanged` (105-110).

- [ ] **Step 4 (Wallpaper.qml):** remover o preview de vídeo remoto: `previewFile`, `focusedPreviewUrl`, `prevFetch`, `prevDebounce` (285-323), o `dimsProc`/`dimsDebounce` (330-372) e o bloco `previewArmed`/`previewArm` (135-149) com o `onFocusIndexChanged` que os dispara (118-143 mantém só `hintShown`/`hintDwell`). Conferir após editar se algum componente de tela referenciava `previewFile`/`dimsProc` (busca `grep -n 'previewFile\|dimsProc\|previewArmed' Wallpaper.qml`) e remover essas verificações de visibilidade no componente do tile.

- [ ] **Step 5 (Wallpaper.qml):** trocar o comando do search para o novo contrato (linha 276):

```qml
    readonly property string searchScript: "/etc/niri/scripts/wallpaper-search.sh"
```

e, na função do search (aproximado linha ~380, seguir o atual), chamar com `["bash", root.searchScript, "search", root.query]` (um arg a menos).

- [ ] **Step 6 (Wallpaper.qml):** no regaço de search, remover o ramo do `?t=motion` na construção da url de DDG (se existir) — o script não aceita mais `kind`.

- [ ] **Step 7:** Verificação: `grep -rn 'mp4\|webm\|mkv\|\.mov\|kindFilter\|isMotion\|searchScript' system_files/etc/quickshell/topbar/pill/Walls.qml system_files/etc/quickshell/topbar/pill/Wallpaper.qml` → WALLS: zero vídeo/mp4; a única linha `isMotion` restante é a de comentário se qualquer; `searchScript` com o caminho novo.

- [ ] **Step 8:** Commit.

```bash
git add system_files/etc/quickshell/topbar/pill/Walls.qml system_files/etc/quickshell/topbar/pill/Wallpaper.qml
git commit -m "Wallpaper: strip e search apenas estáticos (removido vídeo e kind filter)"
```

---

### Task 11: `Pill.qml` — remover surfaces mortas, adicionar NightLightSurface, e wires de path

**Files:**
- Modify: `system_files/etc/quickshell/topbar/pill/Pill.qml` (props, sizes, conditionals, loaders) e `system_files/etc/quickshell/topbar/pill/Appearance.qml`

**Interfaces:**
- Consumes: `NightLightSurface.qml` (Task 9), `Settings.qml` (Task 12).
- Produces: surfaces vivas = appearance, input, idlelock, nightlight; updates/look/animation removidos; rede de paths `/etc/niri/scripts`.

- [ ] **Step 1:** Props (linhas 45-58 e a vistoria do `updatesOpen`):

```diff
-    readonly property bool updatesOpen: surface === "updates"
...
-    readonly property bool lookOpen: surface === "look"
...
-    readonly property bool animationOpen: surface === "animation"
...
-    readonly property bool settingsLike: settingsOpen || appearanceOpen || updatesOpen
-        || lookOpen || inputOpen || displayOpen || animationOpen || idlelockOpen || fontpickerOpen
+    readonly property bool settingsLike: settingsOpen || appearanceOpen
+        || inputOpen || displayOpen || idlelockOpen || nightlightOpen || fontpickerOpen
```

e adicionar `readonly property bool nightlightOpen: surface === "nightlight"` junto aos demais `surface === "…"`.

- [ ] **Step 2:** `authPending` (linha 96) e os tamanhos (linhas ~140-199): remover `updatesW`/`lookW`/`animationW` se definidos e suas entradas no mapa `surfaces`; adicionar `nightlight:` (mesmo size do idlelock, ex. `Qt.size(idlelockW, ...)` — copiar de `idlelock:` no balcão). Tirar `authPending` (não há mais Updates).

- [ ] **Step 3:** conditionals (linhas 257-263, 371): remover os ramos `if (pill.lookOpen)`/`if (pill.animationOpen)` e o `pill.updatesOpen` do condicional de `surfaceBack`/`settingsLike`.

- [ ] **Step 4:** loaders: remover `ldUpdates` (1829-1840), `ldLook` (1868-1879), `ldAnimation` (1894-1905); adicionar `ldNightlight` no mesmo lugar (espelho do `ldIdlelock`):

```qml
    Loader {
        id: ldNightlight
        active: false
        anchors.fill: parent
        sourceComponent: NightLightSurface {
            s: pill.s
            open: pill.nightlightOpen
            morphCloseness: pill.morphCloseness
            onRequestClose: pill.requestClose()
            onRequestSurface: (name) => pill.requestSurface(name)
        }
    }
```

- [ ] **Step 5:** path do app-install (linha 811): `["bash", "/etc/niri/scripts/app-install.sh", "install", next]`.

- [ ] **Step 6 (Appearance.qml):** trocar path de wallcolors e o reload nos dois commands (linhas 62 e 69):

```qml
"python3 /etc/niri/scripts/wallcolors.py --hue \"$1\" \"$2\" \"$3\" && niri msg action load-config-file --path /etc/niri/config.kdl >/dev/null 2>&1; busctl --user call com.mitchellh.ghostty /com/mitchellh/ghostty org.gtk.Actions Activate \"sava{sv}\" reload-config 0 0 >/dev/null 2>&1 || true",
```

e o segundo (rewire): caminho do script idêntico (`/etc/niri/scripts/wallcolors.py`) e `niri msg action load-config-file --path /etc/niri/config.kdl` no lugar do `hyprctl reload`.

- [ ] **Step 7:** Verificação: `grep -n 'ldUpdates\|ldLook\|ldAnimation\|updatesOpen\|lookOpen\|animationOpen\|app-install.sh' system_files/etc/quickshell/topbar/pill/Pill.qml` → só o novo `ldNightlight`/`nightlightOpen` e o path de `/etc/niri/scripts/app-install.sh`; e `grep -c 'hyprctl' system_files/etc/quickshell/topbar/pill/Appearance.qml` → 0.

- [ ] **Step 8:** Commit.

```bash
git add system_files/etc/quickshell/topbar/pill/Pill.qml system_files/etc/quickshell/topbar/pill/Appearance.qml
git commit -m "Pill: troca Look/Animation/Updates por NightLightSurface e paths dos scripts"
```

---

### Task 12: `Settings.qml` — index final + remoção de Updates/Look/Animation (e o walk do update)

**Files:**
- Modify: `system_files/etc/quickshell/topbar/pill/Settings.qml`

**Interfaces:**
- Consumes: procura das previous surfaces.
- Produces: index com 4 rows: Appearance, Input, Idle / Lock, Night light.

- [ ] **Step 1:** remover a row `lookRow` (56-71) e `animationRow` (91-106) e sua entrada no array `rows`.

- [ ] **Step 2:** na `rows`, trocar `{ item: updatesRow, kind: "nav", surface: "updates" }` pela `{ item: nightRow, kind: "nav", surface: "nightlight" }` (posição após idlelock) e adicionar a row:

```qml
        SettingsRow {
            id: nightRow
            surface: root
            captionOnFocus: true
            icon: "moon"  // ou "lightbulb" — conferir com o FontPicker/GlyphIcon names existentes
            name: "Night light"
            sub: "Warmth, schedule"
            last: true

            GlyphIcon {
                width: 16 * root.s
                height: 16 * root.s
                name: "chevron-right"
                color: root.focusRowItem === nightRow ? Theme.cream : Theme.iconDim
                stroke: 2.2
            }
        }
```

Reposicionar o `last: true` (hoje na UpdatesRow) para a NightRow; a UpdatesRow some.

- [ ] **Step 3:** Verificação: `grep -n 'updatesRow\|lookRow\|animationRow\|nightRow' system_files/etc/quickshell/topbar/pill/Settings.qml` → só `nightRow` (e `never` de comentário sobre Hyprland-only permitido).

- [ ] **Step 4:** Commit.

```bash
git add system_files/etc/quickshell/topbar/pill/Settings.qml
git commit -m "Settings: index final com Appearance/Input/Idle-Lock/Night light"
```

---

### Task 13: `Updates.qml` e alvos de update removidos

**Files:**
- Delete: `system_files/etc/quickshell/topbar/pill/Updates.qml`
- Delete: `system_files/etc/quickshell/topbar/pill/Updates.qml`

**Interfaces:**
- Consumes: nada (removido antes de qualquer referência live na Task 11/12).
- Produces: zero rastro de update engine.

- [ ] **Step 1:** verificar que nenhuma referência ativa sobrou ANTES de deletar:

```bash
grep -rn 'Updates.qml\|updateEngine\|ricelin-update\|"updates"' system_files/etc/quickshell/topbar/pill --include=*.qml
```

O único hit tolerado após as Tasks 11/12 é `import "Singletons"` genérico. Se uma referência a `updates` restar (ex: keybind `Mod+U` abrindo a surface), removê-la no Pill.qml.

- [ ] **Step 2:** deletar o surface e remover quaisquer resquícios do engine (o `hypr/` original já saiu na Task 3):

```bash
git rm system_files/etc/quickshell/topbar/pill/Updates.qml
rm -f system_files/etc/niri/scripts/ricelin-update.py system_files/etc/niri/scripts/test_ricelin_update.py 2>/dev/null || true
```

- [ ] **Step 3:** Verificação final do projeto:

```bash
grep -rn 'hyprctl\|Quickshell.Hyprland\|\.config/hypr\|hypridle\|hyprsunset\|swww\|awww\|mpvpaper\|ricelin-update\|Updates.qml' system_files/ | grep -v '\.git'
```

Expected: 0 hits (ou apenas comentários que documentam o passado — permitido a critério do reviewer, mas preferir não deixar).

- [ ] **Step 4:** Commit.

```bash
git add -A
git commit -m "Updates: remove o módulo e o engine de update (updates ficam com bootc)"
```

---

### Task 14: `Input.qml` — portar para `~/.config/niri/input.kdl`

**Files:**
- Modify: `system_files/etc/niri/config.kdl` (adicionar include)
- Modify: `system_files/etc/quickshell/topbar/pill/Input.qml`

**Interfaces:**
- Produces: `~/.config/niri/input.kdl` (perfil de entrada legível e reaplicável a cada boot); `niri msg action load-config-file --path /etc/niri/config.kdl` como trigger de apply.
- Constraint adiciona: o include exige niri `include` (≥25.11) e `optional=true`/`~` (≥26.04); se a verificação no alvo falhar, o executor deve mover o include para `/etc/niri/input.kdl` (guidado pela Task 3 — escrever relato no plan later).

- [ ] **Step 1 (config.kdl):** adicionar no fim do arquivo (após o bloco `binds`):

```kdl
// Perfil de entrada editado pela pill (Input). O niri observa este arquivo;
// mudanças aplicam no reload. Inert place-holder em primeira inicialização.
include optional=true "~/.config/niri/input.kdl"
```

- [ ] **Step 2 (Input.qml):** substituir o mecanismo de persistência: remover `inputPath`/`envPath`/`autostartPath` (linhas 45-47) e os helpers `setInput.js`; usar um `FileView` apontando para `~/.config/niri/input.kdl` e um `Process` `reloadProc` com `["niri", "msg", "action", "load-config-file", "--path", "/etc/niri/config.kdl"]`. Cada row (`sensRow`, `accelRow`, `layoutRow`, `rateRow`, `delayRow`, `numlockRow`) passa a chamar um único `root.writeInput()` que re-gera o arquivo inteiro a partir das propriedades atuais e dispara o reload (debounced via Timer de ~250ms).

Bloco de escrita (JS no QML):

```js
    function buildConfig() {
        var out = "// Gerado pela pill — edite pela surface Input.\n";
        out += "input {\n";
        out += "    mouse {\n";
        out += "        accel-speed " + root.sensitivity + "\n";
        out += "        accel-profile \"" + root.accelProfile + "\"\n";
        out += "    }\n";
        out += "    keyboard {\n";
        out += "        repeat-delay " + root.repeatDelay + "\n";
        out += "        repeat-rate " + root.repeatRate + "\n";
        out += "        xkb { layout \"" + root.kbLayout + "\" }\n";
        out += "        numlock " + (root.numlockOn ? "true" : "false") + "\n";
        out += "    }\n";
        out += "    touchpad {\n";
        out += "        tap\n";
        out += "        natural-scroll\n";
        out += "    }\n";
        out += "}\n";
        out += "cursor {\n";
        out += "    xcursor-theme \"" + root.cursorTheme + "\"\n";
        out += "    xcursor-size " + root.cursorSize + "\n";
        out += "}\n";
        return out;
    }
```

> Ajustar ao nome das properties do `Input.qml` atual (ver `root.sensitivity`, `root.accelProfile`, `root.kbLayout`, `root.repeatRate`, `root.repeatDelay`, `root.numlockOn`, `root.cursorTheme`, `root.cursorSize`); se algum nome diferir, manter o existente. A row "Theme" (themeOpen) continua abrindo a grade de temas; o `setcursor` no QML some (não existe no niri).

- [ ] **Step 3:** ao inicializar (`Component.onCompleted`), ler o arquivo atual (se existir) para cara das properties antes dele ser regravado — para não resetar valores nas primeiras edições. Se o arquivo não existir, usar os defaults do input.cfg (`input { }` e `cursor { }` vazios) e ainda assim o include opcional significa que o niri ignora a falta do arquivo.

- [ ] **Step 4:** Verificação estática: `grep -c 'hyprctl\|setInput.js\|input.lua' system_files/etc/quickshell/topbar/pill/Input.qml` → 0; `grep -n 'include optional' system_files/etc/niri/config.kdl` → 1 hit. Se `niri` existir no host (não), pular.

- [ ] **Step 5:** Commit.

```bash
git add system_files/etc/niri/config.kdl system_files/etc/quickshell/topbar/pill/Input.qml
git commit -m "Input: edita ~/.config/niri/input.kdl via include e reload do niri"
```

---

### Task 15: `Look.qml`, `AnimationSurface.qml`, libs mortas — remoção e última volta de grep

**Files:**
- Delete: `system_files/etc/quickshell/topbar/pill/Look.qml`, `AnimationSurface.qml`, `lib/setDeco.js`, `lib/setAnim.js`
- (se as referências) `system_files/etc/quickshell/topbar/pill/Display.qml`, `Keybinds.qml`, `Workspaces.qml`, `lib/monitors.js`, `lib/binds.js`

**Interfaces:**
- Consumes: após Tasks 11/12, nenhum Loader/PillSurface referencia estes arquivos.
- Produces: árvore de surfaces limpa.

- [ ] **Step 1:** confirmar primeiro que as Tasks 11/12 removeram as referências:

```bash
grep -rln 'Look\b\|AnimationSurface\|Updates\b\|setDeco\|setAnim' system_files/etc/quickshell/topbar/pill/*.qml system_files/etc/quickshell/topbar/pill/lib/
```

Se `Keybinds.qml` ou `Display.qml` aparecerem (porque `Pill.qml` ainda tem `ldKeybinds`/`ldDisplay` com `displayOpen`/`keybindsOpen`), decidir aqui: **manter** Keybinds/Display como inertes (não reachable) ou removê-los também — padrão do plano: remover o que as Tasks 11/12 deixaram vivo (Look/Animation/Updates), e manter Keybinds/Display/Workspaces inertes em caso de dúvida.

- [ ] **Step 2:** deletar os arquivos mortos:

```bash
git rm system_files/etc/quickshell/topbar/pill/Look.qml \
       system_files/etc/quickshell/topbar/pill/AnimationSurface.qml \
       system_files/etc/quickshell/topbar/pill/lib/setDeco.js \
       system_files/etc/quickshell/topbar/pill/lib/setAnim.js
```

- [ ] **Step 3:** atualizar `Singletons/qmldir` se `NightLight` não estava registrado como singleton (conferir `system_files/etc/quickshell/topbar/pill/Singletons/qmldir`; se Sim, nada a fazer).

- [ ] **Step 4:** sifter final completo:

```bash
grep -rn 'hyprctl\|Quickshell.Hyprland\|\.config/hypr\|hypridle\|hyprsunset\|swww\|awww\|mpvpaper\|ricelin-update' system_files/ | grep -v '\.git'
```

Expected: 0 hits (comentários históricos tolerados caso o executor julgue preservação útil, mas sem resquício funcional).

- [ ] **Step 5:** Commit.

```bash
git add -A
git commit -m "Remove surfaces Hyprland-only (Look/Animation) e libs mortas"
```

---

### Task 16: Vestigial — `Power.qml`, `Launcher.qml`, `ScreenRec.qml`, `Cliphist.qml`, `Updates.qml` leftovers, e docs

**Files:**
- Modify: `system_files/etc/quickshell/topbar/pill/Power.qml:50` (lock path)
- Modify: `system_files/etc/quickshell/topbar/pill/Launcher.qml:50` (appimageScript)
- Modify: `system_files/etc/quickshell/topbar/pill/Singletons/ScreenRec.qml:49` (thumbScript)
- Modify: `system_files/etc/quickshell/topbar/pill/Singletons/Cliphist.qml:30` (thumbScript)
- Modify: `docs/hyprland-to-niri-report.md` e `docs/integrations-audit.md` somente se o executor quiser marcar como resolvidas (opcional — não é requisito do plano).

**Interfaces:**
- Consumes: paths já corrigidos nas Tasks 3/10.
- Produces: nenhuma referência `~/.config/hypr` restante.

- [ ] **Step 1:** substituir em cada umos quatro arquivos (exatos):

```qml
    readonly property string appimageScript: "/etc/niri/scripts/app-install.sh"
```

```qml
    readonly property string lockScript: "/etc/niri/scripts/lock.sh"   // Power.qml usa argv: [lockScript]
```

Power.qml:49-50 — a linha é `argv: [Quickshell.env("HOME") + "/.config/hypr/scripts/lock.sh"]`; trocar `Quickshell.env(...)...` por `"/etc/niri/scripts/lock.sh"` (não há property separada lá — ou criar uma, conforme o estilo do arquivo; ver `grep -n 'lock' Power.qml`).

```qml
    readonly property string thumbScript: "/etc/niri/scripts/rec-thumbs.sh"   // ScreenRec.qml
    readonly property string thumbScript: "/etc/niri/scripts/cliphist-thumbs.sh"   // Cliphist.qml
```

- [ ] **Step 2:** Verificação:

```bash
grep -rn '\.config/hypr/scripts' system_files/etc/quickshell
```

Expected: 0 hits.

- [ ] **Step 3:** Commit.

```bash
git add system_files/etc/quickshell
git commit -m "QML: paths de scripts apontam para /etc/niri/scripts"
```

---

## Self-Review

Mapa spec→task:
- §1 pacotes → Task 1; §1 units → Task 2; §2 scripts → Tasks 3, 5, 6, 7; §2 config.kdl spawn/bind → Task 4; §3 Idle/Lock → Task 8; §3 Night light → Task 9; §3 Input → Task 14; §3 Appearance reload → Task 11 (step 6); §4 Updates removal → Tasks 11, 12, 13; §8 media remnants → Task 15; paths → Tasks 10 e 16. Sem lacunas.

Placeholders: nada de TBD/TODO. Os dois "conferir" de Pill/Input são decisões residuais que aponto para observação do grep — permitido (direção do executor verificável).

Tipos: singletons/props/interface de `NightLight` (setMode/setTemp/setOnMin/setOffMin) preservada do arquivo original — Task 9 usa os mesmos nomes que Task 12; `wallpaper.sh` interface `set <pic> [out]`/`resolve` igual ao `Walls.qml` (Task 10). OK.