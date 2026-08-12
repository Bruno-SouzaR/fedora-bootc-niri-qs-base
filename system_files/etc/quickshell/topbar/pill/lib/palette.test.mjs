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
eq(f[0].factory, true, "warm factory flag set");
eq(f[0].id, "warm", "first preset id warm");
eq(f[1].factory, true, "cool factory flag set");
eq(f[1].id, "cool", "second preset id cool");
eq(f[2].factory, true, "mono factory flag set");
eq(f[2].id, "mono", "third preset id mono");
eq(P.validate(f[0].roles), true, "warm roles valid");
eq(P.validate(f[1].roles), true, "cool roles valid");
eq(P.validate(f[2].roles), true, "mono roles valid");

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
eq(P.darken("#e0563b", 0.2), "#c33a1f", "darken lowers lightness");
eq(P.lighten("#221813", 0.2), "#5d4134", "lighten raises lightness");

if (failed) { console.log(failed + " FAILED"); process.exit(1); }