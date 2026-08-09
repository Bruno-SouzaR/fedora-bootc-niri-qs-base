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