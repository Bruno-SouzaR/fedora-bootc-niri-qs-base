pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Shared session flags persisted to a small JSON file and watched for external
 * change, so every Ricelin daemon (pill, lock) reads and writes the same
 * Do-Not-Disturb and Keep-Awake state live without a second notification server
 * or idle inhibitor. Toggling in one surface updates the others on the next file
 * event, and the state survives a daemon restart.
 */
Singleton {
    id: root

    /**
     * True once the persisted flags file has been read (or written on first
     * boot). The layer-shell reserve window keys its exclusive zone off this so
     * it never claims space with the unloaded "smart" default before the real
     * hideMode is known, which would leave a stale reserved band after a reboot
     * in auto-hide mode.
     */
    property bool ready: false

    property alias dnd: adapter.dnd
    property alias keepAwake: adapter.keepAwake
    property alias time12h: adapter.time12h
    property alias clockSeconds: adapter.clockSeconds
    property alias showGlyphs: adapter.showGlyphs
    property alias paletteMode: adapter.paletteMode
    property alias manualRoles: adapter.manualRoles
    property alias presetName: adapter.presetName
    property alias wallpaperDir: adapter.wallpaperDir
    property alias randomScope: adapter.randomScope
    property alias uiScale: adapter.uiScale
    property alias reduceMotion: adapter.reduceMotion
    property alias manualHue: adapter.manualHue
    property alias manualDark: adapter.manualDark
    property alias manualSat: adapter.manualSat
    property alias uiFont: adapter.uiFont
    property alias pillOpacity: adapter.pillOpacity
    property alias topGap: adapter.topGap
    property alias appGap: adapter.appGap
    property alias hideMode: adapter.hideMode
    /**
     * Derived from hideMode so shell.qml keeps reading the same two booleans:
     * "smart" (default) hides only in real fullscreen, "auto" stays hidden
     * until the pointer touches the top edge.
     */
    readonly property bool autoHide: hideMode === "auto"
    readonly property bool smartHide: hideMode === "smart"
    property alias recordCountdown: adapter.recordCountdown
    property alias recordDir: adapter.recordDir
    property alias recordFps: adapter.recordFps
    property alias recordQuality: adapter.recordQuality
    property alias recordCursor: adapter.recordCursor
    property alias recordMic: adapter.recordMic
    property alias recordDesktop: adapter.recordDesktop
    property alias recordClearedBefore: adapter.recordClearedBefore
    property alias idleLockMin: adapter.idleLockMin
    property alias idleScreenOffMin: adapter.idleScreenOffMin
    property alias idleSuspendMin: adapter.idleSuspendMin
    property alias weatherCity: adapter.weatherCity
    property alias musicViz: adapter.musicViz
    property alias nightLightMode: adapter.nightLightMode
    property alias nightLightTemp: adapter.nightLightTemp
    property alias nightLightOnMin: adapter.nightLightOnMin
    property alias nightLightOffMin: adapter.nightLightOffMin

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ricelin/flags.json"
        blockLoading: true
        watchChanges: true
        printErrors: false

        onFileChanged: reload()
        onLoaded: root.ready = true
        onAdapterUpdated: { root.ready = true; writeAdapter(); }
        onLoadFailed: function(error) {
            if (error === FileViewError.FileNotFound)
                writeAdapter();
        }

        JsonAdapter {
            id: adapter
            property bool dnd: false
            property bool keepAwake: false
            property bool time12h: false
            property bool clockSeconds: false
            property bool showGlyphs: true
            property string paletteMode: "presets"
            /** 8-role object the Manual editor edits live; defaults to the Warm preset roles. */
            property var manualRoles: ({ background: "#221813", surface: "#2e231b", accent: "#e0563b", dotInactive: "#e6d6cb", text: "#e6d6cb", textSoft: "#8a7d74", border: "#3a2a22", tone: "dark" })
            /** Pending "Save preset" name filled by the Manual editor. */
            property string presetName: ""
            /** Explicit wallpaper folder override. Empty means autodetect: the dir wallpaper.sh last resolved (ricelin-wallpaper-dir state file), then ~/Ricelin/wallpapers. Lives in user state so an in-app update never clobbers a custom folder. */
            property string wallpaperDir: ""
            /** Super+B random target: "all" repaints every monitor, "cursor" only the one under the pointer. */
            property string randomScope: "all"
            property real uiScale: 1.0
            property bool reduceMotion: false
            property int manualHue: 30
            property bool manualDark: true
            property real manualSat: 0.5
            property string uiFont: ""
            property real pillOpacity: 1.0
            /** Top margin as a fraction of the shipped 8px. 0 sits the pill flush to the screen edge. */
            property real topGap: 1.0
            /** Pill-to-window band as a fraction of the shipped 12px. 0 tucks the windows flush under the pill. */
            property real appGap: 1.0
            /** "smart" hides only in real fullscreen; "auto" hides until the top edge is touched. */
            property string hideMode: "smart"
            property int recordCountdown: 5
            property string recordDir: ""
            property int recordFps: 60
            property string recordQuality: "high"
            property bool recordCursor: true
            property bool recordMic: true
            property bool recordDesktop: true
            property real recordClearedBefore: 0
            property int idleLockMin: 5
            property int idleScreenOffMin: 6
            property int idleSuspendMin: 0
            property string weatherCity: ""
            property bool musicViz: true
            property string nightLightMode: "off"
            property int nightLightTemp: 4000
            property int nightLightOnMin: 1260
            property int nightLightOffMin: 450
        }
    }
}
