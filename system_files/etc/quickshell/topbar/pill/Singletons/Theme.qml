pragma Singleton
import QtQuick
import Quickshell
import "../lib/palette.js" as Palette

/**
 * Pill palette. Two sources: the curated washi/flame hex below is the identity
 * and the default, used whenever the dynamic-palette flag is off. With the flag
 * on, the surfaces and the whole accent ramp follow the wallpaper through the
 * matugen-fed `Dyn` singleton, while the text family, light veils and shadow
 * stay locked here so copy keeps its contrast on any generated background. Each
 * token is a single ternary, so static mode renders byte-identical to the fixed
 * theme and only the colours that should breathe with the wallpaper do.
 */
Singleton {
    /**
     * True only in "dynamic" mode, where matugen-fed `Dyn` supplies the accent
     * ramp and surfaces. In "presets"/"manual" mode the token list below derives
     * from the active preset's (or the Manual's) eight roles via Palette.derive.
     */
    readonly property bool dyn: Flags.paletteMode === "dynamic"

    /**
     * Source roles for derived tokens: the Manual's live roles in "manual" mode,
     * the active preset's roles in "presets" mode, otherwise null (static hex).
     */
    readonly property var _roles: {
        if (Flags.paletteMode === "manual")
            return Flags.manualRoles;
        if (Flags.paletteMode === "presets" && Presets.active)
            return Presets.active.roles;
        return null;
    }

    /** Derived token map from the active roles; null (fallback hex) when no roles. */
    readonly property var _derived: _roles ? Palette.derive(_roles) : null

    /**
     * Bright warm pop shared by the flame glow, charging glyphs, the recording
     * countdown, the unread inbox dot, the calendar's today cell and the held
     * power tile. The dynamic branch uses the wallpaper accent (Dyn.primary):
     * matugen's on-primary-container does not populate here and collapses the
     * token to black, while the accent always loads and contrasts the pill
     * surface. Static mode keeps the fixed warm hex.
     */
    readonly property color onGlow: dyn ? Dyn.primary : (_derived ? _derived.onGlow : "#ff9a64")

    readonly property color verm:     dyn ? Qt.darker(Dyn.primary, 1.18) : (_derived ? _derived.verm : "#c0442b")
    readonly property color vermLit:  dyn ? Dyn.primary : (_derived ? _derived.vermLit : "#e0563b")
    readonly property color vermDeep: dyn ? Dyn.primaryContainer : (_derived ? _derived.vermDeep : "#a3371f")
    readonly property color cream:    dyn ? Dyn.cream : (_derived ? _derived.cream : "#e6d6cb")
    readonly property color bright:   dyn ? Dyn.bright : (_derived ? _derived.bright : "#fff6f0")
    readonly property color dim:      dyn ? Dyn.dim : (_derived ? _derived.dim : "#8a7d74")
    readonly property color cardTop:  dyn ? Dyn.surfaceContainerHigh : (_derived ? _derived.cardTop : "#2e231b")
    readonly property color cardBot:  dyn ? Dyn.surfaceContainerLow : (_derived ? _derived.cardBot : "#221813")
    readonly property color border:   dyn ? Dyn.outlineVariant : (_derived ? _derived.border : "#3a2a22")
    readonly property color shadow:     Qt.rgba(0, 0, 0, 0.55)
    readonly property color tileBg:   dyn ? Dyn.surface : (_derived ? _derived.tileBg : "#211711")
    readonly property color subtle:   dyn ? Dyn.subtle : (_derived ? _derived.subtle : "#b9a99e")
    readonly property color faint:    dyn ? Dyn.faint : (_derived ? _derived.faint : "#6f635b")
    readonly property color iconDim:  dyn ? Dyn.iconDim : (_derived ? _derived.iconDim : "#cdbfb4")
    readonly property color hair:     Qt.alpha(cream, 0.13)
    readonly property color hairSoft: Qt.alpha(cream, 0.08)
    readonly property color sheen:    Qt.alpha(cream, 0.07)
    readonly property color vermDim:   dyn ? Qt.darker(Dyn.primary, 1.5) : (_derived ? _derived.vermDim : "#8a5440")
    readonly property color vermDimDeep: dyn ? Qt.darker(Dyn.primary, 2.2) : (_derived ? _derived.vermDimDeep : "#5a3526")
    readonly property color vermBurn:  dyn ? Qt.darker(Dyn.primaryContainer, 1.1) : (_derived ? _derived.vermBurn : "#8a2c14")
    readonly property color tickRest:  dyn ? Dyn.tickRest : (_derived ? _derived.tickRest : "#cbb6a3")
    readonly property color threadBg:  Qt.alpha(cream, 0.13)
    readonly property color flameCore: dyn ? Qt.lighter(onGlow, 1.03) : (_derived ? _derived.flameCore : "#ffd9c2")
    readonly property color flameGlow: dyn ? onGlow : (_derived ? _derived.flameGlow : "#ff9a64")

    /**
     * Flame canvas ramp: literal hex strings (color type won't work), fed
     * directly to Canvas addColorStop/strokeStyle. A color property serializes
     * to #aarrggbb and corrupts the gradient render, so the dynamic branch passes
     * matugen's raw hex strings through untouched rather than any Qt.darker math.
     */
    readonly property string flameInk:   dyn ? Dyn.primary : (_derived ? _derived.flameInk : "#f0795a")
    readonly property string flameEmber: dyn ? Dyn.primaryContainer : (_derived ? _derived.flameEmber : "#7e2812")
    readonly property string flameBurn:  dyn ? Dyn.primaryContainer : (_derived ? _derived.flameBurn : "#8a2c14")
    readonly property string flameTip:   dyn ? Dyn.onPrimaryContainer : (_derived ? _derived.flameTip : "#ffb38a")
    readonly property color todayWarm: dyn ? onGlow : (_derived ? _derived.todayWarm : "#ffb38a")
    readonly property color ghost:     dyn ? Dyn.surfaceContainerHighest : (_derived ? _derived.ghost : "#594636")
    readonly property color dotRest: dyn ? Dyn.tickRest : (_derived ? _derived.dotRest : "#e6d6cb")
    readonly property color frameBg:      Qt.alpha(cream, 0.055)
    readonly property color frameBorder:  Qt.alpha(cream, 0.10)
    readonly property color creamMenu:     Qt.alpha(cream, 0.82)
    readonly property real shadowOpacity: 0.5
    /**
     * Snapshot of the system families, not a binding: Qt.fontFamilies() is not
     * notifiable, so a font dropped onto the pill re-registers through
     * refreshFonts() once its FontLoader is ready.
     */
    property var fontFamilies: Qt.fontFamilies()
    function refreshFonts() { fontFamilies = Qt.fontFamilies(); }
    readonly property string font: (Flags.uiFont.length > 0 && fontFamilies.indexOf(Flags.uiFont) >= 0) ? Flags.uiFont : "Inter"
    readonly property string fontJp: "Zen Kaku Gothic New"

    /**
     * MPRIS trackArtists arrives as a JS array from some players and as a
     * plain string from others (Spotify); calling join on the string throws
     * and kills the whole binding. Handles both, falls back to trackArtist.
     */
    function joinArtists(artists, single) {
        if (artists && typeof artists.join === "function" && artists.length > 0)
            return artists.join(", ");
        if (artists && String(artists).length > 0)
            return String(artists);
        return single ? String(single) : "";
    }
}
