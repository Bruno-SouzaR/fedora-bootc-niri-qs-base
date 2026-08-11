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
