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

module.exports = { ROLES, factoryPresets, derive, validate, hexToHsl, hslToHex, darken, lighten };