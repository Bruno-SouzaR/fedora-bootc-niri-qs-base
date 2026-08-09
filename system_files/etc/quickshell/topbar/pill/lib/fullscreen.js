const TOLERANCE = 1;

function isFullscreenCovering(windowLayout, logicalOutput) {
    if (!windowLayout || !logicalOutput)
        return false;
    var ws = windowLayout.window_size;
    if (!ws)
        return false;
    if (Math.abs(ws[0] - logicalOutput.width) > 2 * TOLERANCE)
        return false;
    if (Math.abs(ws[1] - logicalOutput.height) > 2 * TOLERANCE)
        return false;
    var tp = windowLayout.tile_pos_in_workspace_view;
    if (tp && tp.length >= 1 && tp[0] !== null && Math.abs(tp[0]) > TOLERANCE)
        return false;
    return true;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { isFullscreenCovering };
}