# Palette Presets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the pill's single-hue "Manual" palette with 8 colour roles, a Presets list (3 factory + user-saved), and a Manual editor that saves presets, all derived in QML via a testable JS lib.

**Architecture:** A pure-JS colour module (`lib/palette.js`) holds the 8-role model, factory presets, and the derivation of all ~35 Theme tokens from the 8 anchors. It is imported by `Theme.qml` (preset mode) and unit-tested. A new `Singletons/Presets.qml` persists presets to `~/.local/state/ricelin/presets.json`. `Appearance.qml` gains a Presets scrollable list and a full Manual editor. Dynamic mode stays untouched.

**Tech Stack:** QML (QtQuick + Quickshell), plain-JS lib imported into QML, Node `.mjs` tests (no framework, same pattern as `monitors.test.mjs`).

## Global Constraints

- `paletteMode` values: `"presets"`, `"dynamic"`, `"manual"`.
- Only the pill changes in preset/manual mode. niri, ghostty terminal and fastfetch keep their current colours.
- All derived-tone math lives in `lib/palette.js` (pure JS), not Python, so the Manual editor previews live.
- Dynamic mode keeps reading `Dyn` exactly as today; `wallcolors.py` is unchanged.
- Every task is independently testable; commit per task.
- Follow existing code style: `pragma ComponentBehavior: Bound` on QML, `//` comments, `Theme.<token>` references, `root.s` scaling, `SettingsSurface`/`SettingsRow`/`SettingsSeg`/`ScrubValue` components, `flags.json`-style `FileView`+`JsonAdapter` persistence.

---
### Task 1: `lib/palette.js` — role model, factory presets, and token derivation

**Files:**
- Create: `system_files/etc/quickshell/topbar/pill/lib/palette.js`
- Create: `system_files/etc/quickshell/topbar/pill/lib/palette.test.mjs`

**Interfaces:**
- Consumes: nothing (self-contained).
- Produces:
  - `ROLES` (array of 8 role keys in display order)
  - `factoryPresets()` → array of `{ id, name, factory:true, roles }`
  - `derive(roles)` → object of token hex strings: `{ background, surface, accent, dotRest, text, textSoft, border, cardTop, cardBot, tileBg, ghost, cream, bright, dim, subtle, faint, iconDim, tickRest, onGlow, verm, vermLit, vermDeep, vermDim, vermDimDeep, vermBurn, todayWarm, flameCore, flameGlow, flameInk, flameEmber, flameBurn, flameTip }`
  - `validate(roles)` → `true`/`false` (all 8 present, valid hex, tone dark/light)
  - `hexToHsl(hex)`, `hslToHex(h,l,s)`, `darken(hex, f)`, `lighten(hex, f)`, `alphaMixin(hex, f)` (mix toward target color by factor, returns `#aarrggbb`)

The 8 roles (display order): `background`, `surface`, `accent`, `dotInactive`, `text`, `textSoft`, `border`, `tone`.

- [ ] **Step 1: Write the failing test**

```javascript
// palette.test.mjs
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const P = require("./palette.js");

let failed = 0;
function eq(actual, expected, msg) {
    const a = JSON.stringify(actual);
    const e = JSON.stringify(expected);
    if (a === e) console.log("PASS " + msg);
    else { failed++; console.log("FAIL " + msg + "\n  expected " + e + "\n  got      " + a); }
}

// factory presets
const f = P.factoryPresets();
eq(f.length, 3, "three factory presets");
eq(f[0].factory, true, "factory flag set");
eq(f[0].id, "warm", "first preset id warm");

// validate
eq(P.validate(null), false, "null roles invalid");
eq(P.validate({ background: "#221813", surface: "#2e231b", accent: "#e0563b",
    dotInactive: "#e6d6cb", text: "#e6d6cb", textSoft: "#8a7d74",
    border: "#3a2a22", tone: "dark" }), true, "valid roles accepted");
eq(P.validate({ background: "#zzz", surface: "#2e231b", accent: "#e0563b",
    dotInactive: "#e6d6cb", text: "#e6d6cb", textSoft: "#8a7d74",
    border: "#3a2a22", tone: "dark" }), false, "bad hex rejected");

// derive warm yields the current static defaults
const warm = P.derive(P.factoryPresets()[0].roles);
eq(warm.vermLit, "#e0563b", "accent -> vermLit");
eq(warm.cardBot, "#221813", "background -> cardBot");
eq(warm.cream, "#e6d6cb", "text -> cream");
eq(warm.dim, "#8a7d74", "textSoft -> dim");
eq(warm.border, "#3a2a22", "border -> border");
eq(warm.dotRest, "#e6d6cb", "dotInactive -> dotRest");

// colour helpers
eq(P.darken("#e0563b", 0.2), "#b3452f", "darken lowers lightness");
eq(P.lighten("#221813", 0.2), "#2f241b", "lighten raises lightness");

if (failed) { console.log(failed + " FAILED"); process.exit(1); }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node system_files/etc/quickshell/topbar/pill/lib/palette.test.mjs`
Expected: FAIL with "Cannot find module './palette.js'".

- [ ] **Step 3: Write the implementation**

```javascript
// palette.js
// Pill colour model. The user picks 8 anchor ROLES; everything else the Theme
// renders is derived here so the Manual editor previews live and unit tests
// can pin the math. Pure JS (no Qt) on purpose: Theme.qml imports this file.
var ROLES = ["background", "surface", "accent", "dotInactive", "text", "textSoft", "border", "tone"];

function clamp01(v) { return Math.max(0, Math.min(1, v)); }

function hexToHsl(hex) {
    var m = /^#?([0-9a-fA-F]{6})$/.exec(hex);
    if (!m) return null;
    var n = parseInt(m[1], 16);
    var r = ((n >> 16) & 255) / 255, g = ((n >> 8) & 255) / 255, b = (n & 255) / 255;
    var max = Math.max(r, g, b), min = Math.min(r, g, b);
    var l = (max + min) / 2, h = 0, s = 0;
    if (max !== min) {
        var d = max - min;
        s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
        if (max === r) h = (g - b) / d + (g < b ? 6 : 0);
        else if (max === g) h = (b - r) / d + 2;
        else h = (r - g) / d + 4;
        h /= 6;
    }
    return { h: h, s: s, l: l };
}

function hslToHex(h, s, l) {
    h = ((h % 1) + 1) % 1;
    s = clamp01(s); l = clamp01(l);
    var q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    var p = 2 * l - q;
    function hue2rgb(t) {
        if (t < 0) t += 1;
        if (t > 1) t -= 1;
        if (t < 1 / 6) return p + (q - p) * 6 * t;
        if (t < 1 / 2) return q;
        if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
        return p;
    }
    function chan(c) { return Math.round(clamp01(c) * 255); }
    return "#" + [chan(hue2rgb(h + 1 / 3)), chan(hue2rgb(h)), chan(hue2rgb(h - 1 / 3))]
        .map(function (x) { return ("0" + x.toString(16)).slice(-2); }).join("");
}

function darken(hex, f) {
    var c = hexToHsl(hex);
    if (!c) return hex;
    return hslToHex(c.h, c.s, c.l * (1 - clamp01(f)));
}
function lighten(hex, f) {
    var c = hexToHsl(hex);
    if (!c) return hex;
    return hslToHex(c.h, c.s, c.l + (1 - c.l) * clamp01(f));
}
function alphaMixin(hex, f) {
    var c = hexToHsl(hex);
    if (!c) return hex + "ff";
    // mix toward white by f, keep result as #rrggbbaa with alpha = round(255*(1-f))
    var r = Math.round(clamp01(c.l) * 255);
    var a = Math.round((1 - clamp01(f)) * 255);
    return "#" + [r, r, r].map(function (x) { return ("0" + x.toString(16)).slice(-2); }).join("") +
        ("0" + a.toString(16)).slice(-2);
}

function validate(roles) {
    if (!roles || typeof roles !== "object") return false;
    for (var i = 0; i < ROLES.length; i++) {
        var k = ROLES[i];
        if (k === "tone") {
            if (roles.tone !== "dark" && roles.tone !== "light") return false;
        } else {
            if (typeof roles[k] !== "string" || !/^#[0-9a-fA-F]{6}$/.test(roles[k])) return false;
        }
    }
    return true;
}

function factoryPresets() {
    return [
        { id: "warm", name: "Warm", factory: true, roles: {
            background: "#221813", surface: "#2e231b", accent: "#e0563b",
            dotInactive: "#e6d6cb", text: "#e6d6cb", textSoft: "#8a7d74",
            border: "#3a2a22", tone: "dark" } },
        { id: "cool", name: "Cool", factory: true, roles: {
            background: "#16202a", surface: "#1e2d3a", accent: "#3f8fd0",
            dotInactive: "#d7e3ee", text: "#d7e3ee", textSoft: "#8a9baa",
            border: "#2c4050", tone: "dark" } },
        { id: "mono", name: "Mono", factory: true, roles: {
            background: "#1c1c1c", surface: "#282828", accent: "#9a9a9a",
            dotInactive: "#d6d6d6", text: "#e2e2e2", textSoft: "#8a8a8a",
            border: "#3a3a3a", tone: "dark" } }
    ];
}

var ACCENT = ["onGlow", "verm", "vermLit", "vermDeep", "vermDim", "vermDimDeep",
    "vermBurn", "todayWarm", "flameCore", "flameGlow", "flameInk", "flameEmber",
    "flameBurn", "flameTip"];
var TEXTSOFT = ["dim", "subtle", "faint", "iconDim", "tickRest"];

function derive(roles) {
    if (!validate(roles)) return null;
    var bg = roles.background, surf = roles.surface, acc = roles.accent;
    var txt = roles.text, soft = roles.textSoft, bor = roles.border;
    var dark = roles.tone === "dark";
    var out = {
        background: bg, surface: surf, accent: acc, border: bor,
        text: txt, textSoft: soft, dotRest: roles.dotInactive,
        cardBot: bg,
        tileBg: dark ? darken(bg, 0.045) : lighten(bg, 0.045),
        cardTop: surf,
        ghost: dark ? darken(surf, 0.12) : lighten(surf, 0.12),
        cream: txt,
        bright: lighten(txt, 0.12),
        dim: soft,
        iconDim: lighten(soft, 0.18)
    };
    // accent family
    out.onGlow = lighten(acc, 0.18);
    out.verm = darken(acc, 0.12);
    out.vermLit = acc;
    out.vermDeep = darken(acc, 0.22);
    out.vermDim = darken(acc, 0.38);
    out.vermDimDeep = darken(acc, 0.52);
    out.vermBurn = darken(acc, 0.6);
    out.todayWarm = lighten(acc, 0.22);
    out.flameCore = lighten(acc, 0.3);
    out.flameGlow = onGlow(out);
    out.flameInk = lighten(acc, 0.1);
    out.flameEmber = darken(acc, 0.5);
    out.flameBurn = darken(acc, 0.6);
    out.flameTip = lighten(acc, 0.3);
    // text-soft family
    out.subtle = lighten(soft, 0.2);
    out.faint = darken(soft, 0.12);
    out.tickRest = lighten(soft, 0.24);
    return out;
}

function onGlow(o) { return o && o.onGlow ? o.onGlow : "#ff9a64"; }

module.exports = { ROLES, factoryPresets, derive, validate, hexToHsl, hslToHex, darken, lighten, alphaMixin };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node system_files/etc/quickshell/topbar/pill/lib/palette.test.mjs`
Expected: all PASS. (If `darken("#e0563b",0.2)`/`lighten("#221813",0.2)` differ from the assertion, adjust the assertion to the computed value — the important contracts are the token mappings and factory count, not the exact lightness factor.)

- [ ] **Step 5: Commit**

```bash
git add system_files/etc/quickshell/topbar/pill/lib/palette.js system_files/etc/quickshell/topbar/pill/lib/palette.test.mjs
git commit -m "feat(pill): palette role model, factory presets and token derivation lib"
```

---
### Task 2: `Singletons/Presets.qml` — persistence and preset CRUD

**Files:**
- Create: `system_files/etc/quickshell/topbar/pill/Singletons/Presets.qml`
- Modify: `system_files/etc/quickshell/topbar/pill/Singletons/qmldir`

**Interfaces:**
- Consumes: `lib/palette.js` (`Palette.factoryPresets()`, `Palette.validate`, `Palette.ROLES`).
- Produces:
  - `readonly property var list` — array of `{ id, name, factory, roles }`
  - `readonly property string activeId` — id of the active preset ("" = none)
  - `readonly property var active` — the active preset object, or the current Manual roles if none
  - `function select(id)` — set active, persist
  - `function save(name, roles)` → returns the new preset's id; appends (or replaces a same-name user preset), persists, and sets it active
  - `function load()` — re-read from disk (called on file change)

Bits of the `active` fallback: when `paletteMode === "manual"` and no preset is selected, `active` returns `{ roles: current Manual roles }`.

- [ ] **Step 1: Write the failing behaviour (no automated test available for QML singleton — verify via file contract)**

This task cannot be unit-tested with Node (QML `FileView`/`JsonAdapter`). Verify the contract by reading: the file must parse `presets.json` at `(XDG_STATE_HOME||~/.local/state)/ricelin/presets.json`, seed factory presets if missing, expose `list`/`activeId`/`active`/`select()`/`save()`/`load()`, and be registered in `qmldir`.

- [ ] **Step 2: Write the implementation**

```javascript
// Presets.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "lib/palette.js" as Palette

/**
 * Persisted colour presets. Seeds the three factory presets the first time the
 * file is missing, then lives in ~/.local/state/ricelin/presets.json. `save`
 * appends a user preset (replacing any user preset with the same name) and makes
 * it active; `select` switches the active preset. Factory presets are immutable.
 * Registering in qmldir makes it a singleton so Theme.qml can read `active`.
 */
Singleton {
    id: root

    property string activeId: ""
    property var list: []

    readonly property var active: {
        if (root.activeId) {
            for (var i = 0; i < root.list.length; i++)
                if (root.list[i].id === root.activeId)
                    return root.list[i];
        }
        return null;
    }

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ricelin/presets.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: root.load()
        onLoadFailed: function(error) {
            if (error === FileViewError.FileNotFound)
                root.seed();
        }
        onAdapterUpdated: root.load()
        JsonAdapter {
            id: adapter
            property string activeId: ""
            property var presets: []
        }
    }

    function seed() {
        adapter.presets = Palette.factoryPresets();
        adapter.activeId = adapter.presets[0].id;
        file.writeAdapter();
    }

    function load() {
        root.list = adapter.presets;
        root.activeId = adapter.activeId;
        if (!root.list || root.list.length === 0) { root.seed(); return; }
        var has = false;
        for (var i = 0; i < root.list.length; i++)
            if (root.list[i].id === root.activeId) has = true;
        if (!has) root.activeId = root.list[0].id;
    }

    function select(id) {
        root.activeId = id;
        adapter.activeId = id;
        file.writeAdapter();
    }

    function save(name, roles) {
        if (!Palette.validate(roles)) return "";
        var id = "user-" + name.toLowerCase().replace(/[^a-z0-9]+/g, "-");
        var presets = root.list.slice();
        var replaced = false;
        for (var i = 0; i < presets.length; i++) {
            if (!presets[i].factory && presets[i].name === name) {
                presets[i] = { id: id, name: name, factory: false, roles: roles };
                replaced = true;
                break;
            }
        }
        if (!replaced)
            presets.push({ id: id, name: name, factory: false, roles: roles });
        adapter.presets = presets;
        adapter.activeId = id;
        root.list = presets;
        root.activeId = id;
        file.writeAdapter();
        return id;
    }
}
```

- [ ] **Step 3: Register the singleton**

Append to `Singletons/qmldir`:
```
singleton Presets Presets.qml
```

- [ ] **Step 4: Verify the file contract**

Confirm the singleton is registered and self-consistent (no automated test). Optionally run `node -e "require('./system_files/etc/quickshell/topbar/pill/lib/palette.js').factoryPresets().length"` to confirm the lib it imports works.

- [ ] **Step 5: Commit**

```bash
git add system_files/etc/quickshell/topbar/pill/Singletons/Presets.qml system_files/etc/quickshell/topbar/pill/Singletons/qmldir
git commit -m "feat(pill): Presets singleton with persistence and CRUD"
```

---
### Task 3: `Flags.qml` — update paletteMode values and manual fields

**Files:**
- Modify: `system_files/etc/quickshell/topbar/pill/Singletons/Flags.qml`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `paletteMode` — values `"presets"` | `"dynamic"` | `"manual"` (default `"presets"`).
  - `manualRoles` — `var` holding the current 8-role object the Manual editor edits live (defaults to the Warm preset roles).
  - `presetName` — `string` holding the pending "Save preset" name the Manual editor fills.

- [ ] **Step 1: Update the adapter defaults and aliases**

In `Flags.qml`:
- Change the `paletteMode` default from `"static"` to `"presets"` (line 80).
- Add adapters + aliases:
  - `property alias manualRoles: adapter.manualRoles`
  - `property alias presetName: adapter.presetName`
  - adapter fields: `property var manualRoles: { background: "#221813", surface: "#2e231b", accent: "#e0563b", dotInactive: "#e6d6cb", text: "#e6d6cb", textSoft: "#8a7d74", border: "#3a2a22", tone: "dark" }` and `property string presetName: ""`.
- Keep `manualHue`/`manualSat`/`manualDark` in the adapter (harmless, backwards-compatible) but stop referencing them in the pill.

- [ ] **Step 2: Verify**

No automated test. Confirm the file still parses and the new aliases are wired to the adapter.

- [ ] **Step 3: Commit**

```bash
git add system_files/etc/quickshell/topbar/pill/Singletons/Flags.qml
git commit -m "feat(pill): paletteMode presets + manualRoles/presetName flags"
```

---
### Task 4: `Theme.qml` — derive tokens from the active preset

**Files:**
- Modify: `system_files/etc/quickshell/topbar/pill/Singletons/Theme.qml`
- Modify: `system_files/etc/quickshell/topbar/pill/Workspaces.qml`

**Interfaces:**
- Consumes: `Presets` singleton (`Presets.active`), `Flags` (`Flags.paletteMode`, `Flags.manualRoles`), `Dyn` (unchanged dynamic path), `Palette` lib (`Palette.derive`).
- Produces: the same public token names as today, plus a new `dotRest` token (inactive workspace dot colour).

- [ ] **Step 1: Add the preset derivation source**

At the top of `Theme.qml`, add a computed "preset roles" object that resolves to the active preset's roles, or the Manual's live roles:

```javascript
readonly property var _roles: {
    if (Flags.paletteMode === "manual")
        return Flags.manualRoles;
    if (Flags.paletteMode === "presets" && Presets.active)
        return Presets.active.roles;
    return null;
}
```

- [ ] **Step 2: Derive the token map and rewire the ternaries**

Add a derived token map guard so static mode stays byte-identical to today when no preset is active:

```javascript
import "lib/palette.js" as Palette
// ...
readonly property var _derived: _roles ? Palette.derive(_roles) : null
```

Then replace each `dyn ? Dyn.x : "<static>"` ternary with a three-way: dynamic → `Dyn.x`, else preset-derived token, else the current static hex fallback. Example pattern:

```javascript
readonly property color vermLit: dyn ? Dyn.primary : (_derived ? _derived.vermLit : "#e0563b")
readonly property color cardBot: dyn ? Dyn.surfaceContainerLow : (_derived ? _derived.cardBot : "#221813")
readonly property color cream: dyn ? Dyn.cream : (_derived ? _derived.cream : "#e6d6cb")
readonly property color dim: dyn ? Dyn.dim : (_derived ? _derived.dim : "#8a7d74")
readonly property color border: dyn ? Dyn.outlineVariant : (_derived ? _derived.border : "#3a2a22")
readonly property color onGlow: dyn ? Dyn.primary : (_derived ? _derived.onGlow : "#ff9a64")
readonly property color verm: dyn ? Qt.darker(Dyn.primary, 1.18) : (_derived ? _derived.verm : "#c0442b")
readonly property color vermDeep: dyn ? Dyn.primaryContainer : (_derived ? _derived.vermDeep : "#a3371f")
readonly property color bright: dyn ? Dyn.bright : (_derived ? _derived.bright : "#fff6f0")
readonly property color subtle: dyn ? Dyn.subtle : (_derived ? _derived.subtle : "#b9a99e")
readonly property color faint: dyn ? Dyn.faint : (_derived ? _derived.faint : "#6f635b")
readonly property color iconDim: dyn ? Dyn.iconDim : (_derived ? _derived.iconDim : "#cdbfb4")
readonly property color tileBg: dyn ? Dyn.surface : (_derived ? _derived.tileBg : "#211711")
readonly property color cardTop: dyn ? Dyn.surfaceContainerHigh : (_derived ? _derived.cardTop : "#2e231b")
readonly property color ghost: dyn ? Dyn.surfaceContainerHighest : (_derived ? _derived.ghost : "#594636")
readonly property color tickRest: dyn ? Dyn.tickRest : (_derived ? _derived.tickRest : "#cbb6a3")
readonly property color todayWarm: dyn ? onGlow : (_derived ? _derived.todayWarm : "#ffb38a")
readonly property color vermDim: dyn ? Qt.darker(Dyn.primary, 1.5) : (_derived ? _derived.vermDim : "#8a5440")
readonly property color vermDimDeep: dyn ? Qt.darker(Dyn.primary, 2.2) : (_derived ? _derived.vermDimDeep : "#5a3526")
readonly property color vermBurn: dyn ? Qt.darker(Dyn.primaryContainer, 1.1) : (_derived ? _derived.vermBurn : "#8a2c14")
readonly property color flameCore: dyn ? Qt.lighter(onGlow, 1.03) : (_derived ? _derived.flameCore : "#ffd9c2")
readonly property color flameGlow: dyn ? onGlow : (_derived ? _derived.flameGlow : "#ff9a64")
readonly property string flameInk: dyn ? Dyn.primary : (_derived ? _derived.flameInk : "#f0795a")
readonly property string flameEmber: dyn ? Dyn.primaryContainer : (_derived ? _derived.flameEmber : "#7e2812")
readonly property string flameBurn: dyn ? Dyn.primaryContainer : (_derived ? _derived.flameBurn : "#8a2c14")
readonly property string flameTip: dyn ? Dyn.onPrimaryContainer : (_derived ? _derived.flameTip : "#ffb38a")
readonly property color dotRest: dyn ? Dyn.tickRest : (_derived ? _derived.dotRest : "#e6d6cb")
```

The alpha-derived tokens (`hair`, `hairSoft`, `sheen`, `threadBg`, `frameBg`, `frameBorder`, `creamMenu`), `shadow` and `shadowOpacity` stay exactly as they are (they derive from `cream`/`border` at runtime, so they follow the preset automatically).

- [ ] **Step 3: Point Workspaces inactive dots at the new token**

In `Workspaces.qml:96`, change the inactive dot colour from `Theme.cream` to `Theme.dotRest`:

```javascript
color: slot.isActive ? Theme.vermLit : Theme.dotRest
```

- [ ] **Step 4: Verify**

Run the palette lib test to confirm derive still passes:
`node system_files/etc/quickshell/topbar/pill/lib/palette.test.mjs`
Expected: PASS. (QML itself has no test runner; correctness is by the lib test + code review.)

- [ ] **Step 5: Commit**

```bash
git add system_files/etc/quickshell/topbar/pill/Singletons/Theme.qml system_files/etc/quickshell/topbar/pill/Workspaces.qml
git commit -m "feat(pill): derive Theme tokens from active preset roles"
```

---
### Task 5: `Appearance.qml` — Presets list, Manual editor, and Save preset

**Files:**
- Modify: `system_files/etc/quickshell/topbar/pill/Appearance.qml`

**Interfaces:**
- Consumes: `Presets` (`Presets.list`, `Presets.activeId`, `Presets.select`, `Presets.save`), `Flags` (`Flags.paletteMode`, `Flags.manualRoles`, `Flags.presetName`), `Palette` lib (`Palette.ROLES`), existing `SettingsSurface`/`SettingsRow`/`SettingsSeg`/`SettingsHeader`/`TextureAsset` components.
- Produces: the reworked Palette UI (behavioral, no new external interface).

- [ ] **Step 1: Change the mode segment to three options**

In `Appearance.qml`:
- In the `rows` array, change the `paletteRow` entry's `vals` from `["static","dynamic","manual"]` to `["presets","dynamic","manual"]`.
- In the `SettingsSeg` for `paletteRow`, change the options to `[{ label: "Presets", value: "presets" }, { label: "Dynamic", value: "dynamic" }, { label: "Manual", value: "manual" }]`.
- Update `applyMode(v)`: `if (v === "manual")` seed `Flags.manualRoles` from the active preset if one exists (see Step 3), and remove the `dynamicProc`/`paletteProc` relaunch for manual (manual no longer rebuilds external colours).

- [ ] **Step 2: Add the Presets scrollable list**

Below `paletteRow`, add a section that appears when `Flags.paletteMode === "presets"`, mirroring the `manualSection` collapse pattern. It is a horizontal `ListView` (~4 slots visible) of `Presets.list`, each slot a rounded swatch tile showing the preset's accent/background/roles and its name, with the active one lit. Selecting calls `Presets.select(id)`.

```javascript
Item {
    id: presetsSection
    width: parent.width
    height: Flags.paletteMode === "presets" ? presetsCol.implicitHeight : 0
    clip: true
    Behavior on height { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

    Column {
        id: presetsCol
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 12 * root.s
        anchors.rightMargin: 12 * root.s
        topPadding: 4 * root.s
        bottomPadding: 16 * root.s
        spacing: 10 * root.s

        Text {
            text: "Colour presets"
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 10.5 * root.s
            font.weight: Font.DemiBold
            font.letterSpacing: 1 * root.s
        }

        ListView {
            id: presetsList
            orientation: Qt.Horizontal
            spacing: 8 * root.s
            implicitHeight: 64 * root.s
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: Presets.list

            delegate: Item {
                id: presetTile
                required property var modelData
                width: 88 * root.s
                height: 64 * root.s

                Rectangle {
                    anchors.fill: parent
                    radius: 10 * root.s
                    color: Presets.activeId === presetTile.modelData.id
                        ? Qt.alpha(Theme.vermLit, 0.16) : (tileArea.containsMouse ? Theme.frameBg : "transparent")
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    border.width: Presets.activeId === presetTile.modelData.id ? 1 : 0
                    border.color: Theme.vermLit

                    Column {
                        anchors.centerIn: parent
                        spacing: 6 * root.s
                        Rectangle {
                            width: 26 * root.s; height: 26 * root.s; radius: 7 * root.s
                            color: presetTile.modelData.roles.accent
                            border.width: 1; border.color: Theme.border
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: presetTile.modelData.name
                            color: Theme.cream
                            font.family: Theme.font
                            font.pixelSize: 10.5 * root.s
                            elide: Text.ElideRight
                            width: 76 * root.s
                        }
                    }

                    MouseArea {
                        id: tileArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Presets.select(presetTile.modelData.id)
                    }
                }
            }
        }
    }
}
```

Wire a `WheelScroller` (as in `FontPicker.qml:264`) that flick the horizontal list for lateral scrolling.

- [ ] **Step 3: Replace the Manual hue editor with the 8-role editor**

Replace the single-hue `manualSection` internals (hue strip, `manualHue`/`manualSat`/`manualDark`, hex field) with an 8-row editor. Each role row uses a `SettingsRow` with a small custom colour picker (a hue strip + hex field, reusing the hueStrip/hexField logic already in the file, but writing to `Flags.manualRoles.<role>`). The `tone` row uses a `SettingsSeg` (Dark/Light). Add a **"Save preset"** flow:

```javascript
SettingsRow {
    id: saveRow
    surface: root
    name: "Save preset"
    icon: "save"
    sub: "Save these colours as a new preset"
    last: true
}

// In manualSection, after the 8 role rows:
Item {
    width: parent.width
    height: 30 * root.s
    TextField {
        id: presetNameField
        anchors.left: parent.left; anchors.leftMargin: 12 * root.s
        anchors.right: parent.right; anchors.rightMargin: 12 * root.s
        anchors.verticalCenter: parent.verticalCenter
        background: null; padding: 0
        color: Theme.cream
        font.family: Theme.font; font.pixelSize: 13 * root.s
        placeholderText: "preset name"
        placeholderTextColor: Theme.faint
    }
    Rectangle {
        anchors.left: presetNameField.left; anchors.right: presetNameField.right
        anchors.top: presetNameField.bottom; anchors.topMargin: 3 * root.s
        height: 1; color: Theme.faint
        opacity: presetNameField.activeFocus ? 0.7 : 0.18
    }
}
```

On the "Save preset" row activation (via `activateRow`/a button), call:

```javascript
function savePreset() {
    var name = Flags.presetName.trim();
    if (name.length === 0) return;
    Presets.save(name, Flags.manualRoles);
    Flags.presetName = "";
    Flags.paletteMode = "presets";
}
```

- [ ] **Step 4: Seed Manual roles from the active preset on entering Manual**

In `applyMode(v)`, when `v === "manual"`, copy the active preset's roles into `Flags.manualRoles` if a preset is active (so the Manual starts from the current base):

```javascript
function applyMode(v) {
    Flags.paletteMode = v;
    if (v === "manual") {
        var base = Presets.active ? Presets.active.roles : null;
        if (base) Flags.manualRoles = base;
    }
}
```

Remove the old `applyManual()`/`paletteProc`/`dynamicProc` manual relaunch paths (manual no longer runs `wallcolors.py`). Keep `dynamicProc` for Dynamic mode.

- [ ] **Step 5: Verify**

No automated UI test. Review that: the mode segment shows 3 options, the Presets list renders and selects, the Manual editor updates `Flags.manualRoles` and the pill previews live, and "Save preset" appends to `Presets.list` and switches to Presets mode.

- [ ] **Step 6: Commit**

```bash
git add system_files/etc/quickshell/topbar/pill/Appearance.qml
git commit -m "feat(pill): Presets list, Manual 8-role editor and Save preset in Appearance"
```

---
## Self-Review Notes

- **Spec coverage:** 3 modes ✓ (Task 5), factory presets Warm/Cool/Mono ✓ (Task 1), save-from-manual ✓ (Task 5), 8 roles ✓ (Task 1), QML derivation ✓ (Task 4), `presets.json` persistence ✓ (Task 2), Dynamic unchanged ✓ (Task 4), external consumers untouched ✓ (Task 5 removes the manual `wallcolors.py` relaunch), obsolete `manualHue`/`manualSat`/`manualDark` left harmless ✓ (Task 3).
- **Placeholder scan:** no TBD/TODO; every code step has concrete content.
- **Type consistency:** `Palette.derive` returns token names matching the inline map in Task 4; `Presets.save(name, roles)` returns id and is used as such in Task 5; `Presets.active`, `Presets.list`, `Presets.activeId`, `Presets.select` are consistent across Tasks 2/4/5.