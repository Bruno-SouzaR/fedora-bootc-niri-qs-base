# Migrar o módulo Pill do Look (removido) para a surface Appearance

**Data:** 2026-08-11
**Área:** `system_files/etc/quickshell/topbar/pill/Appearance.qml`, `system_files/etc/quickshell/topbar/pill/Singletons/Flags.qml`
**Estado:** Design aprovado pelo usuário. Aguarda self-review → review do usuário → writing-plans.

## Objetivo

O commit `2cd2dbf` removeu a surface `Look.qml` inteira (incluindo o grupo `pillGrp`, que configurava a própria pill). O usuário queria o menu Look fora, mas **não** queria perder os controles da pill que viviam nele. Restaurar esses controles dentro da surface **Appearance** já existente, usando os componentes atuais (`SettingsRow`, `SettingsSeg`, `ScrubValue`) e o registry de teclado do `SettingsSurface`.

## Decisões já tomadas

- **Menu Look permanece removido** — nada a restaurar além das 4 linhas da pill.
- **Pill blur é droppado** — era Hyprland-only (escrevia `layer_rule` em `decoration.lua` + `hyprctl reload`); no niri o blur é engine global e o toggle não mapeia de forma limpa. Não migrar.
- **Posição:** as 4 linhas entram no fim da lista do Appearance, imediatamente antes do row `fontRow` (que mantém `last: true`). Sem rótulo de seção, mantendo o visual plano atual.
- **Persistência:** reutilizar flags existentes no `Flags.qml` (`topGap`, `appGap`, `pillOpacity`, `hideMode`) — todas já lidas por `shell.qml`/`Pill.qml` e persistidas no JsonAdapter. Sem Process novo.

## Linhas a adicionar em `Appearance.qml`

| Ordem | Row | Controle | Flag | Range/valores |
|---|---|---|---|---|
| 1 | Hide mode | `SettingsSeg` | `Flags.hideMode` | Smart / Auto (`"smart"`, `"auto"`) |
| 2 | Pill gap | `ScrubValue` | `Flags.topGap` | `from: 0; to: 2; step: 0.1; decimals: 1` |
| 3 | App gap | `ScrubValue` | `Flags.appGap` | `from: 0; to: 2; step: 0.1; decimals: 1` |
| 4 | Pill opacity | `ScrubValue` | `Flags.pillOpacity` | `from: 0.55; to: 1.0; step: 0.05; decimals: 2` |

Valores e ranges replicam exatamente os do antigo `Look.qml` (`pillGapRow`/`appGapRow`/`pillOpRow`/`hideModeRow`).

### Registry de teclado (`rows:` do `SettingsSurface`)

Adicionar as 4 entradas, nos kinds que o `SettingsSurface` já suporta:

- Hide mode → `kind: "seg"`, `vals: ["smart", "auto"]`, get/set em `Flags.hideMode`.
- Pill gap / App gap / Pill opacity → `kind: "scrub"`, com `bump: function (d) { xxxScrub.bump(d); }`.

Mesmo padrão do `Input.qml:31-40`.

### Undo dos scrubs

Seguir o padrão do `Input.qml` (`base` snapshot em `onActiveChanged`): capturar `topGap`/`appGap`/`pillOpacity` quando a surface abrir, e passá-los como `openValue` aos `ScrubValue`, para o glyph de undo funcionar. (Hoje o `Appearance.qml` não tem esse snapshot; adicionar.)

### Icons

Usar glyphs já existentes no `GlyphIcon.qml`:

- Hide mode → `layers`
- Pill gap → `waves`
- App gap → `monitor`
- Pill opacity → `droplet`

(Confirmar nomes exatos no plano de implementação; todos existem no dicionário do `GlyphIcon.qml`.)

## Cleanup opcional (acordado)

Remover o flag morto `pillBlur` do `Flags.qml` (property alias + property no JsonAdapter). Não é lido por nenhum outro código hoje (verificado: só `Flags.qml` referencia). Incluir na mesma mudança para não deixar dead code.

## Fora de escopo

- Reabrir o menu Look ou qualquer outra surface Hyprland-only.
- Portar Pill blur para `layer-rule` do niri.
- Mudanças de comportamento da pill (`shell.qml`/`Pill.qml` já consomem os flags).

## Verificação

- QML parse-check dos arquivos tocados (via `quickshell --validate` ou ferramenta equivalente disponível no repo, se houver).
- `grep` para confirmar que `pillBlur` não é mais referenciado em lugar nenhum.
- Sem testes automatizados de QML no repo para essa surface; validar visualmente abrindo Settings → Appearance.
