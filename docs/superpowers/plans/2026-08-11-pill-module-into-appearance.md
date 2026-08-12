# Módulo Pill migrado para a surface Appearance — Implementation Plan

> **Para agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para implementar este plano tarefa por tarefa. Passos usam checkbox (`- [ ]`) para rastreio.

**Goal:** Restaurar os controles da pill que viviam no `Look.qml` (removido) dentro da surface `Appearance.qml`, usando os componentes atuais e o registry de teclado do `SettingsSurface`, e dropar o flag morto `pillBlur`.

**Architecture:** `Appearance.qml` ganha 4 linhas novas (Hide mode + 3 scrubs) adicionadas ao array `rows` e ao conteúdo, imediatamente antes do row `fontRow` (que mantém `last: true`). Os scrubs usam o snapshot `base` (padrão `Input.qml`) para o undo do `ScrubValue`. Todos os controles leem flags já existentes no `Flags.qml`, então nenhum Process novo é necessário. `pillBlur` (Hyprland-only, dead) é removido do `Flags.qml`.

**Tech Stack:** Quickshell QML6, `SettingsSurface`/`SettingsRow`/`SettingsSeg`/`ScrubValue`, `Flags` singleton (JsonAdapter).

## Global Constraints

- Rede de verificação: **host de dev não tem `quickshell`/`niri`/`node`**; validação de QML é **estática** (grep/diff/leitura) no host e **visual** no sistema alvo (abrir Settings → Appearance). Não tentar rodar `node`/`quickshell` no host.
- Commands de verificação rodam **com `bash`** (zsh do host não tem `rg`; usar `grep -rn`, não `rg`).
- NÃO reintroduzir nada do `Look.qml` além das 4 linhas; **Pill blur fica fora** (decisão do spec).
- Manter o estilo dos vizinhos: docblock JC no topo das funções novas, sem comentários de bate-estaca; rows com `kind` correto (`seg`/`scrub`/`toggle`/`nav`).
- Commits por tarefa, mensagens em português, estilo do repo (`git log --oneline`).

---

## File Structure

**Editados:**
- `system_files/etc/quickshell/topbar/pill/Appearance.qml` (rows + conteúdo + snapshot `base`)
- `system_files/etc/quickshell/topbar/pill/Singletons/Flags.qml` (remove `pillBlur`)

**Não modificados:** `shell.qml`, `Pill.qml`, `Settings.qml` (já consomem os flags; nenhuma row nova de Settings index).

---

### Task 1: Linhas da pill no Appearance

**Files:**
- Modify: `system_files/etc/quickshell/topbar/pill/Appearance.qml`

**Interfaces:**
- Consumes: `Flags.hideMode` (string "smart"/"auto"), `Flags.topGap` (real), `Flags.appGap` (real), `Flags.pillOpacity` (real); `SettingsSurface.rows`; `ScrubValue.bump(dir)`; `SettingsSeg.picked(value)`.
- Produces: 4 linhas navegáveis por teclado/mouse (kinds `seg` e `scrub`) renderizadas na surface; 3 `ScrubValue` com `openValue` ativo para o glyph de undo.

- [ ] **Step 1:** Adicionar o snapshot `base` e o `onActiveChanged` logo após as propriedades existentes de cor (após a linha `readonly property string currentHex ...`). O `onActiveChanged` substitui o handler da base (mesmo padrão do `Input.qml`), então replicar o reset de `focusRowItem`/`kbIndex` no ramo inativo:

```qml
    /** Per-field values captured on each open; the ScrubValue undo glyphs revert to these. */
    property var base: ({})

    onActiveChanged: {
        if (active) {
            root.base = { topGap: Flags.topGap, appGap: Flags.appGap, pillOpacity: Flags.pillOpacity };
        } else {
            focusRowItem = null;
            kbIndex = -1;
        }
    }
```

- [ ] **Step 2:** Inserir as 4 entradas no array `rows: [...]`, imediatamente **antes** da linha `{ item: fontRow, kind: "nav", surface: "fontpicker" }`:

```qml
        { item: hideRow, kind: "seg", vals: ["smart", "auto"], get: function () { return Flags.hideMode; }, set: function (v) { Flags.hideMode = v; } },
        { item: gapRow, kind: "scrub", bump: function (d) { gapScrub.bump(d); } },
        { item: appGapRow, kind: "scrub", bump: function (d) { appGapScrub.bump(d); } },
        { item: opRow, kind: "scrub", bump: function (d) { opScrub.bump(d); } },
```

- [ ] **Step 3:** Inserir os 4 `SettingsRow` no conteúdo, imediatamente **antes** do bloco `SettingsRow { id: fontRow ... }` (que mantém `last: true`). Copiar os blocos exatos:

```qml
        SettingsRow {
            id: hideRow
            surface: root
            name: "Hide mode"
            icon: "layers"

            SettingsSeg {
                s: root.s
                options: [{ label: "Smart", value: "smart" }, { label: "Auto", value: "auto" }]
                value: Flags.hideMode
                onPicked: (v) => Flags.hideMode = v
            }
        }

        SettingsRow {
            id: gapRow
            surface: root
            name: "Pill gap"
            icon: "waves"

            ScrubValue {
                id: gapScrub
                s: root.s
                value: Flags.topGap
                openValue: root.base.topGap
                from: 0; to: 2; step: 0.1; decimals: 1
                onEdited: (v) => Flags.topGap = v
            }
        }

        SettingsRow {
            id: appGapRow
            surface: root
            name: "App gap"
            icon: "monitor"

            ScrubValue {
                id: appGapScrub
                s: root.s
                value: Flags.appGap
                openValue: root.base.appGap
                from: 0; to: 2; step: 0.1; decimals: 1
                onEdited: (v) => Flags.appGap = v
            }
        }

        SettingsRow {
            id: opRow
            surface: root
            name: "Pill opacity"
            icon: "droplet"

            ScrubValue {
                id: opScrub
                s: root.s
                value: Flags.pillOpacity
                openValue: root.base.pillOpacity
                from: 0.55; to: 1.0; step: 0.05; decimals: 2
                onEdited: (v) => Flags.pillOpacity = v
            }
        }
```

- [ ] **Step 4:** Verificação estática:

```bash
bash -c "grep -n 'hideRow\|gapRow\|appGapRow\|opRow\|gapScrub\|appGapScrub\|opScrub\|root.base' system_files/etc/quickshell/topbar/pill/Appearance.qml"
```

Esperado: as 4 entradas no `rows`, os 4 `SettingsRow` com `id` correspondentes, os 3 `ScrubValue` com `openValue: root.base.*`, e o bloco `base`/`onActiveChanged` presente. Confirmar também que `fontRow` segue **após** os novos blocos (a única ocorrência de `last: true` continua nele).

- [ ] **Step 5:** Verificar que os ícones existem no dicionário do `GlyphIcon.qml` (já confirmado: `layers`, `waves`, `monitor`, `droplet` — 1 ocorrência cada):

```bash
bash -c "for ic in layers waves monitor droplet; do grep -c '\\\"$ic\\\":' system_files/etc/quickshell/topbar/pill/GlyphIcon.qml; done"
```

Esperado: `1` para cada um.

- [ ] **Step 6:** Commit.

```bash
git add system_files/etc/quickshell/topbar/pill/Appearance.qml
git commit -m "Appearance: migra o módulo Pill (hide mode, gaps, opacity) do Look removido"
```

---

### Task 2: Remove o flag morto pillBlur do Flags

**Files:**
- Modify: `system_files/etc/quickshell/topbar/pill/Singletons/Flags.qml`

**Interfaces:**
- Consumes: nada novo; nenhum código referencia `Flags.pillBlur` hoje (verificado no Step 2).
- Produces: `Flags.qml` sem `pillBlur` — a persistência continua ignorando a chave antiga do `flags.json` (JsonAdapter lê só as propriedades declaradas).

- [ ] **Step 1:** Remover o alias na seção de property aliases do Singleton (linha com `property alias pillBlur: adapter.pillBlur`):

```qml
-    property alias pillBlur: adapter.pillBlur
```

- [ ] **Step 2:** Remover a propriedade do JsonAdapter (linha `property bool pillBlur: false`):

```qml
-            property bool pillBlur: false
```

- [ ] **Step 3:** Verificação estática — `pillBlur` não deve aparecer em lugar nenhum do repo de quickshell:

```bash
bash -c "grep -rn 'pillBlur' system_files/etc/quickshell/ || echo 'pillBlur: nenhuma ocorrência (ok)'"
```

Esperado: `pillBlur: nenhuma ocorrência (ok)`.

- [ ] **Step 4:** Commit.

```bash
git add system_files/etc/quickshell/topbar/pill/Singletons/Flags.qml
git commit -m "Flags: remove pillBlur morto (era Hyprland-only)"
```

---

## Self-Review

- **Cobertura do spec:** 4 linhas (hide mode, pill gap, app gap, pill opacity) → Task 1; Pill blur droppado → Task 2; posição antes do `fontRow` sem rótulo de seção → Task 1 Steps 2-3; persistência via flags existentes → sem alteração de `Flags` além da Task 2; undo via snapshot `base` → Task 1 Step 1.
- **Placeholders:** nenhum; todos os blocos QML são literais.
- **Consistência de nomes:** ids das rows (`hideRow`, `gapRow`, `appGapRow`, `opRow`) batem entre o array `rows`, os `SettingsRow` e os `bump` dos scrubs (`gapScrub`, `appGapScrub`, `opScrub`); flags usam os nomes exatos do `Flags.qml`.
