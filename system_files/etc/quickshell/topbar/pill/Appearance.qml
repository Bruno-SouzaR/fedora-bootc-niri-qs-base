pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell.Io
import "Singletons"
import "lib/palette.js" as Palette

/**
 * 相 APPEARANCE sub-surface: the clock format and seconds, the Japanese-glyph
 * toggle that gates every surface header, the palette mode (stored presets, a
 * dynamic per-wallpaper palette, or a manual eight-role editor), the UI scale
 * and a reduce-motion switch. Reached from the settings index and morphs back
 * to it on an empty click or the back chevron.
 *
 * Presets mode reveals a scrollable strip of saved palettes; picking one
 * selects it. Manual mode reveals the eight-role editor — each role gets a hue
 * strip and a hex field writing straight to Flags.manualRoles so the pill
 * previews live — plus a dark/light tone choice and a "Save preset" flow that
 * appends the working colours to the preset list and snaps back to Presets.
 */
SettingsSurface {
    id: root

    backSurface: "settings"
    implicitHeight: content.implicitHeight

    /** Per-field values captured on each open; the ScrubValue undo glyphs revert to these. */
    property var base: ({})

    /** The seven colour roles, in order, with their descriptive English labels. */
    readonly property var roleRows: [
        { role: "background", label: "Pill background" },
        { role: "surface", label: "Menu surface" },
        { role: "accent", label: "Accent (selection & active dot)" },
        { role: "dotInactive", label: "Inactive workspace dots" },
        { role: "text", label: "Primary text" },
        { role: "textSoft", label: "Secondary text" },
        { role: "border", label: "Border" }
    ]

    onActiveChanged: {
        if (active) {
            root.base = { topGap: Flags.topGap, appGap: Flags.appGap, pillOpacity: Flags.pillOpacity };
        } else {
            focusRowItem = null;
            kbIndex = -1;
        }
    }

    /**
     * Write a single Manual role with a whole-object reassignment of
     * Flags.manualRoles: Theme._roles only recomputes when the var is replaced
     * as a new object, so a fresh shallow copy is made on every change and the
     * pill previews follow live.
     */
    function setRole(role, hex) {
        var r = {};
        var src = Flags.manualRoles;
        for (var k in src)
            r[k] = src[k];
        r[role] = hex;
        Flags.manualRoles = r;
    }

    function setTone(v) {
        setRole("tone", v);
    }

    /** Current hue of a role in degrees 0..359, for the strip thumb position. */
    function roleHue(role) {
        var hsl = Palette.hexToHsl(Flags.manualRoles[role]);
        return hsl ? Math.round(hsl.h * 359) : 0;
    }

    /** Drag on a role's hue strip: keep its saturation/lightness, swap the hue. */
    function pickRoleHue(role, mx, width) {
        var hsl = Palette.hexToHsl(Flags.manualRoles[role]);
        if (!hsl)
            return;
        var s = hsl.s < 0.05 ? 0.5 : hsl.s;
        var h = Math.max(0, Math.min(1, mx / width));
        setRole(role, Palette.hslToHex(h, s, hsl.l));
    }

    /** Saturation of a role 0..1, for the SV box thumb x. */
    function roleSat(role) {
        var hsl = Palette.hexToHsl(Flags.manualRoles[role]);
        return hsl ? hsl.s : 0;
    }

    /** Lightness of a role 0..1, for the SV box thumb y (inverted). */
    function roleLight(role) {
        var hsl = Palette.hexToHsl(Flags.manualRoles[role]);
        return hsl ? hsl.l : 0;
    }

    /**
     * Drag on a role's saturation/lightness square: keep its hue, set
     * saturation from x and lightness from y (top = light). This is how a user
     * reaches whites, blacks and dark desaturated tones like #214C42.
     */
    function pickRoleSV(role, mx, my, width, height) {
        var hsl = Palette.hexToHsl(Flags.manualRoles[role]);
        if (!hsl)
            return;
        var s = Math.max(0, Math.min(1, mx / width));
        var l = Math.max(0, Math.min(1, 1 - my / height));
        setRole(role, Palette.hslToHex(hsl.h, s, l));
    }

    /** Commit a typed hex on a role, ignoring anything that isn't #rrggbb. */
    function commitRole(role, raw) {
        var clean = String(raw).trim();
        if (clean.charAt(0) === "#")
            clean = clean.slice(1);
        if (/^[0-9a-fA-F]{6}$/.test(clean))
            setRole(role, "#" + clean.toLowerCase());
    }

    /** Guard the name, append the working roles to the preset list, snap to Presets. */
    function savePreset() {
        var name = String(Flags.presetName || "").trim();
        if (name.length === 0)
            return;
        Presets.save(name, Flags.manualRoles);
        Flags.presetName = "";
        if (presetNameField)
            presetNameField.text = "";
        Flags.paletteMode = "presets";
    }

    function applyMode(v) {
        Flags.paletteMode = v;
        if (v === "manual") {
            var base = Presets.active ? Presets.active.roles : null;
            if (base)
                Flags.manualRoles = base;
        } else if (v === "dynamic") {
            dynamicProc.running = true;
        }
    }

    Process {
        id: dynamicProc
        command: ["sh", "-c",
            "f=\"${XDG_STATE_HOME:-$HOME/.local/state}/ricelin-wallpaper\"; pic=$(cat \"$f\" 2>/dev/null); [ -f \"$pic\" ] && python3 /etc/niri/scripts/wallcolors.py \"$pic\" >/dev/null 2>&1; niri msg action load-config-file --path /etc/niri/config.kdl >/dev/null 2>&1; busctl --user call com.mitchellh.ghostty /com/mitchellh/ghostty org.gtk.Actions Activate \"sava{sv}\" reload-config 0 0 >/dev/null 2>&1 || true"]
    }

    rows: [
        { item: timeRow, kind: "seg", vals: [false, true], get: function () { return Flags.time12h; }, set: function (v) { Flags.time12h = v; } },
        { item: secRow, kind: "toggle", get: function () { return Flags.clockSeconds; }, set: function (v) { Flags.clockSeconds = v; } },
        { item: glyphRow, kind: "toggle", get: function () { return Flags.showGlyphs; }, set: function (v) { Flags.showGlyphs = v; } },
        { item: vizRow, kind: "toggle", get: function () { return Flags.musicViz; }, set: function (v) { Flags.musicViz = v; } },
        { item: paletteRow, kind: "seg", vals: ["presets", "dynamic", "manual"], get: function () { return Flags.paletteMode; }, set: function (v) { root.applyMode(v); } },
        { item: randomRow, kind: "seg", vals: ["all", "cursor"], get: function () { return Flags.randomScope; }, set: function (v) { Flags.randomScope = v; } },
        { item: scaleRow, kind: "seg", vals: [0.9, 1.0, 1.1, 1.25], get: function () { return Flags.uiScale; }, set: function (v) { Flags.uiScale = v; } },
        { item: motionRow, kind: "toggle", get: function () { return Flags.reduceMotion; }, set: function (v) { Flags.reduceMotion = v; } },
        { item: hideRow, kind: "seg", vals: ["smart", "auto"], get: function () { return Flags.hideMode; }, set: function (v) { Flags.hideMode = v; } },
        { item: gapRow, kind: "scrub", bump: function (d) { gapScrub.bump(d); } },
        { item: appGapRow, kind: "scrub", bump: function (d) { appGapScrub.bump(d); } },
        { item: opRow, kind: "scrub", bump: function (d) { opScrub.bump(d); } },
        { item: fontRow, kind: "nav", surface: "fontpicker" }
    ]

    Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        SettingsHeader {
            s: root.s
            glyph: "相"
            title: "APPEARANCE"
            showBack: true
        }

        Item { width: 1; height: 12 * root.s }

        SettingsRow {
            id: timeRow
            surface: root
            name: "Time format"
            icon: "clock"

            SettingsSeg {
                s: root.s
                options: [{ label: "24H", value: false }, { label: "12H", value: true }]
                value: Flags.time12h
                onPicked: (v) => Flags.time12h = v
            }
        }

        SettingsRow {
            id: secRow
            surface: root
            name: "Clock seconds"
            icon: "stopwatch"

            LinkToggle {
                s: root.s
                on: Flags.clockSeconds
                onToggled: Flags.clockSeconds = !Flags.clockSeconds
            }
        }

        SettingsRow {
            id: glyphRow
            surface: root
            name: "Japanese glyphs"
            icon: "language"

            LinkToggle {
                s: root.s
                on: Flags.showGlyphs
                onToggled: Flags.showGlyphs = !Flags.showGlyphs
            }
        }

        SettingsRow {
            id: vizRow
            surface: root
            name: "Music visualizer"
            icon: "music"

            LinkToggle {
                s: root.s
                on: Flags.musicViz
                onToggled: Flags.musicViz = !Flags.musicViz
            }
        }

        SettingsRow {
            id: paletteRow
            surface: root
            name: "Palette"
            icon: "palette"

            SettingsSeg {
                s: root.s
                options: [{ label: "Presets", value: "presets" }, { label: "Dynamic", value: "dynamic" }, { label: "Manual", value: "manual" }]
                value: Flags.paletteMode
                onPicked: (v) => root.applyMode(v)
            }
        }

        /**
         * Presets strip, folded shut unless the palette is on Presets. A
         * horizontal list of swatch tiles, one per saved/stock palette, with the
         * active one lit; a button-less wheel bridge flicks it sideways.
         */
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
                    width: presetsCol.width
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

            /**
             * Wheel bridge for the preset strip, a sibling of the presets
             * column so the column's implicitHeight is not collapsed (QML
             * forbids anchors.fill on a direct Column child, which zeroed
             * presetsCol's implicitHeight and kept the submenu closed). Stays
             * pinned over the strip to translate wheel notches into
             * horizontal contentX steps.
             */
            MouseArea {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 21 * root.s
                height: 64 * root.s
                acceptedButtons: Qt.NoButton
                cursorShape: Qt.PointingHandCursor
                property real acc: 0
                onWheel: (event) => {
                    acc += event.angleDelta.y / 120;
                    const notches = Math.trunc(acc);
                    if (notches !== 0) {
                        const max = Math.max(0, presetsList.contentWidth - presetsList.width);
                        presetsList.contentX = Math.max(0, Math.min(max, presetsList.contentX + notches * 48 * root.s));
                        acc -= notches;
                    }
                    event.accepted = true;
                }
            }
        }

        /**
         * Manual eight-role editor, folded shut unless the palette is on Manual.
         * The seven colour roles live in a vertically scrollable list showing
         * about three at a time, so the editor never grows past the screen; the
         * tone choice, the preset name and the Save row stay pinned below the
         * scrolling roles. Each role row pairs a swatch + hex field with a
         * draggable hue strip and a saturation/lightness square.
         */
        Item {
            id: manualSection
            width: parent.width
            height: Flags.paletteMode === "manual" ? manualCol.implicitHeight : 0
            clip: true
            Behavior on height { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

            Column {
                id: manualCol
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 12 * root.s
                anchors.rightMargin: 12 * root.s
                topPadding: 4 * root.s
                bottomPadding: 16 * root.s
                spacing: 4 * root.s

                Text {
                    text: "Edit the eight roles"
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 10.5 * root.s
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1 * root.s
                }

                Item {
                    id: rolesScroll
                    width: parent.width
                    height: Math.min(rolesList.contentHeight, 3 * 102 * root.s)
                    implicitHeight: height

                    ListView {
                        id: rolesList
                        anchors.fill: parent
                        clip: true
                        spacing: 4 * root.s
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.roleRows
                        delegate: roleEditor
                    }

                    WheelScroller {
                        anchors.fill: parent
                        s: root.s
                        flick: rolesList
                    }
                }

                SettingsRow {
                    id: toneRow
                    surface: root
                    name: "Tone"
                    sub: "Dark or light base"

                    SettingsSeg {
                        s: root.s
                        options: [{ label: "Dark", value: "dark" }, { label: "Light", value: "light" }]
                        value: Flags.manualRoles.tone
                        onPicked: (v) => root.setTone(v)
                    }
                }

                Item {
                    width: parent.width
                    height: 30 * root.s

                    Text {
                        id: saveHint
                        anchors.left: parent.left
                        anchors.leftMargin: 12 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Preset name"
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 11 * root.s
                        font.weight: Font.DemiBold
                    }

                    TextField {
                        id: presetNameField
                        anchors.left: saveHint.right
                        anchors.leftMargin: 10 * root.s
                        anchors.right: parent.right
                        anchors.rightMargin: 12 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        background: null
                        padding: 0
                        color: Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 13 * root.s
                        text: Flags.presetName
                        onTextEdited: Flags.presetName = text
                        placeholderText: "e.g. Sunset"
                        placeholderTextColor: Theme.faint
                        selectByMouse: true
                        selectionColor: Theme.verm
                        maximumLength: 24
                    }

                    Rectangle {
                        anchors.left: presetNameField.left
                        anchors.right: presetNameField.right
                        anchors.top: presetNameField.bottom
                        anchors.topMargin: 3 * root.s
                        height: 1
                        color: Theme.faint
                        opacity: presetNameField.activeFocus ? 0.7 : 0.18
                        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
                    }
                }

                SettingsRow {
                    id: saveRow
                    surface: root
                    name: "Save preset"
                    icon: "download"
                    sub: "Save these colours as a new preset"
                    last: true

                    Rectangle {
                        id: saveBtn
                        width: saveLabel.implicitWidth + 28 * root.s
                        height: 26 * root.s
                        radius: 8 * root.s
                        color: saveArea.containsMouse ? Theme.vermLit : Theme.verm
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        Text {
                            id: saveLabel
                            anchors.centerIn: parent
                            text: "Save"
                            color: Theme.cream
                            font.family: Theme.font
                            font.pixelSize: 10.5 * root.s
                            font.weight: Font.Bold
                            font.letterSpacing: 0.4 * root.s
                        }

                        MouseArea {
                            id: saveArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.savePreset()
                        }
                    }
                }
            }
        }

        SettingsRow {
            id: randomRow
            surface: root
            name: "Random wallpaper"
            icon: "monitor"

            SettingsSeg {
                s: root.s
                options: [{ label: "All screens", value: "all" }, { label: "Cursor screen", value: "cursor" }]
                value: Flags.randomScope
                onPicked: (v) => Flags.randomScope = v
            }
        }

        SettingsRow {
            id: scaleRow
            surface: root
            name: "UI scale"
            icon: "scaling"

            SettingsSeg {
                s: root.s
                options: [{ label: "90%", value: 0.9 }, { label: "100%", value: 1.0 }, { label: "110%", value: 1.1 }, { label: "125%", value: 1.25 }]
                value: Flags.uiScale
                onPicked: (v) => Flags.uiScale = v
            }
        }

        SettingsRow {
            id: motionRow
            surface: root
            name: "Reduce motion"
            icon: "waves"

            LinkToggle {
                s: root.s
                on: Flags.reduceMotion
                onToggled: Flags.reduceMotion = !Flags.reduceMotion
            }
        }

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

        SettingsRow {
            id: fontRow
            surface: root
            name: "Font"
            icon: "type"
            sub: Flags.uiFont.length > 0 ? Flags.uiFont : "Inter"
            last: true

            GlyphIcon {
                width: 16 * root.s
                height: 16 * root.s
                name: "chevron-right"
                color: root.focusRowItem === fontRow ? Theme.cream : Theme.iconDim
                stroke: 1.9
            }
        }
    }

    Component {
        id: roleEditor

        SettingsRow {
            required property var modelData
            surface: root
            name: modelData.label

            Item {
                width: 104 * root.s
                height: 90 * root.s

                Rectangle {
                    id: roleSwatch
                    anchors.left: parent.left
                    anchors.top: parent.top
                    width: 16 * root.s
                    height: 16 * root.s
                    radius: 5 * root.s
                    color: Flags.manualRoles[modelData.role]
                    border.width: 1
                    border.color: Theme.border
                }

                TextField {
                    id: roleHex
                    anchors.left: roleSwatch.right
                    anchors.leftMargin: 6 * root.s
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 18 * root.s
                    verticalAlignment: Text.AlignVCenter
                    background: null
                    padding: 0
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 10.5 * root.s
                    font.features: { "tnum": 1 }
                    placeholderText: Flags.manualRoles[modelData.role].toUpperCase()
                    placeholderTextColor: Theme.faint
                    selectByMouse: true
                    selectionColor: Theme.verm
                    maximumLength: 7

                    onActiveFocusChanged: if (!activeFocus) text = ""

                    function commit() {
                        root.commitRole(modelData.role, text);
                        text = "";
                        focus = false;
                    }

                    onAccepted: commit()
                    onEditingFinished: commit()
                }

                Rectangle {
                    id: roleHueStrip
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: roleHex.bottom
                    anchors.topMargin: 5 * root.s
                    height: 12 * root.s
                    radius: 6 * root.s
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.hsla(0.0, 0.7, 0.5, 1) }
                        GradientStop { position: 1 / 6; color: Qt.hsla(1 / 6, 0.7, 0.5, 1) }
                        GradientStop { position: 2 / 6; color: Qt.hsla(2 / 6, 0.7, 0.5, 1) }
                        GradientStop { position: 3 / 6; color: Qt.hsla(3 / 6, 0.7, 0.5, 1) }
                        GradientStop { position: 4 / 6; color: Qt.hsla(4 / 6, 0.7, 0.5, 1) }
                        GradientStop { position: 5 / 6; color: Qt.hsla(5 / 6, 0.7, 0.5, 1) }
                        GradientStop { position: 1.0; color: Qt.hsla(1.0, 0.7, 0.5, 1) }
                    }

                    Rectangle {
                        id: roleThumb
                        width: 12 * root.s
                        height: 12 * root.s
                        radius: width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        x: (root.roleHue(modelData.role) / 359) * (roleHueStrip.width - width)
                        color: Flags.manualRoles[modelData.role]
                        border.width: 2 * root.s
                        border.color: Theme.cream
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        function setHue(mx) { root.pickRoleHue(modelData.role, mx, roleHueStrip.width); }
                        onPressed: (m) => setHue(m.x)
                        onPositionChanged: (m) => setHue(m.x)
                    }
                }

                /**
                 * Saturation/lightness square for the current hue: drag across
                 * it to move saturation (x) and lightness (y, top = light). This
                 * is what reaches whites, blacks and dark desaturated greens.
                 * The background blends white -> pure hue horizontally, then
                 * fades to black vertically via a second overlay layer.
                 */
                Rectangle {
                    id: roleSv
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: roleHueStrip.bottom
                    anchors.topMargin: 5 * root.s
                    height: 34 * root.s
                    radius: 6 * root.s
                    clip: true

                    Rectangle {
                        id: roleSvHue
                        anchors.fill: parent
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "#ffffff" }
                            GradientStop { position: 1.0; color: Qt.hsla(root.roleHue(modelData.role) / 359, 1.0, 0.5, 1) }
                        }
                    }

                    Rectangle {
                        id: roleSvShade
                        anchors.fill: parent
                        gradient: Gradient {
                            orientation: Gradient.Vertical
                            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 1) }
                        }
                    }

                    Rectangle {
                        id: roleSvThumb
                        width: 12 * root.s
                        height: 12 * root.s
                        radius: width / 2
                        x: root.roleSat(modelData.role) * (roleSv.width - width)
                        y: (1 - root.roleLight(modelData.role)) * (roleSv.height - height)
                        color: Flags.manualRoles[modelData.role]
                        border.width: 2 * root.s
                        border.color: Theme.cream
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.CrossCursor
                        function setSv(mx, my) { root.pickRoleSV(modelData.role, mx, my, roleSv.width, roleSv.height); }
                        onPressed: (m) => setSv(m.x, m.y)
                        onPositionChanged: (m) => setSv(m.x, m.y)
                    }
                }
            }
        }
    }
}