pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "Singletons"

/**
 * 操 INPUT sub-surface: edits the pointer, keyboard and cursor settings, writing
 * the whole profile to `~/.config/niri/input.kdl` (a KDL snippet the niri config
 * includes, so it survives a restart and is live-reloaded by niri's config
 * watcher). Any pointer or keyboard pick regenerates the file wholesale and
 * reloads niri as a belt-and-braces apply; the layout row cycles a curated list
 * of common layouts. Cursor size and theme persist through the same file as the
 * `cursor` block, with no separate live apply. The theme list is scanned from
 * the installed icon themes that carry a `cursors/` folder. Reached from the
 * settings index; morphs back on the back chevron.
 */
SettingsSurface {
    id: root

    backSurface: "settings"
    implicitHeight: content.implicitHeight

    /**
     * Row registry; scrub rows expose a bump that steps their ScrubValue one
     * increment. The layout row's vals gain the current layout at the end when it
     * is not in the curated list, so an exotic layout shows as-is and a click
     * wraps around to the start of the list.
     */
    rows: [
        { item: sensRow, kind: "scrub", bump: function (d) { sensScrub.bump(d); } },
        { item: accelRow, kind: "seg", vals: ["flat", "adaptive"], get: function () { return root.accelProfile; }, set: function (v) { root.accelProfile = v; root.writeInput(); } },
        { item: layoutRow, kind: "seg", vals: root.kbLayoutVals, get: function () { return root.kbLayout; }, set: function (v) { root.setKbLayout(v); } },
        { item: rateRow, kind: "scrub", bump: function (d) { rateScrub.bump(d); } },
        { item: delayRow, kind: "scrub", bump: function (d) { delayScrub.bump(d); } },
        { item: numlockRow, kind: "toggle", get: function () { return root.numlockOn; }, set: function (v) { root.numlockOn = v; root.writeInput(); } },
        { item: sizeRow, kind: "scrub", bump: function (d) { sizeScrub.bump(d); } },
        { item: themeRow, kind: "toggle", get: function () { return root.themeOpen; }, set: function (v) { root.themeOpen = v; } }
    ]

    property string note: ""

    readonly property string inputPath: Quickshell.env("HOME") + "/.config/niri/input.kdl"

    property real sensitivity: 0
    property string accelProfile: "flat"
    property string kbLayout: "de"
    property int repeatRate: 25
    property int repeatDelay: 600
    property bool numlockOn: false
    property int cursorSize: 24
    property string cursorTheme: "Bibata-Modern-Ice"
    property var cursorThemes: []
    property bool themeOpen: false

    /** Per-field values captured on each open; the ScrubValue undo glyphs revert to these. */
    property var base: ({})

    readonly property var accelOptions: [
        { label: "Flat", value: "flat" },
        { label: "Adaptive", value: "adaptive" }
    ]

    readonly property var kbLayouts: ["de", "us", "gb", "fr", "es", "it", "tr"]
    readonly property var kbLayoutVals: kbLayouts.indexOf(kbLayout) >= 0 ? kbLayouts : kbLayouts.concat([kbLayout])

    /**
     * Pulls the value after a `name` line out of the KDL snippet: a double-quoted
     * string is returned unquoted, any bare run (number, keyword) is returned
     * trimmed. Returns "" when the field is absent.
     */
    function kdlField(text, name) {
        var re = new RegExp(name + "\\s+(?:\"([^\"]*)\"|([^\\s}]+))");
        var m = re.exec(text);
        if (!m)
            return "";
        return m[1] !== undefined ? m[1] : m[2];
    }

    onActiveChanged: {
        if (active) {
            inputFile.reload();
            seed();
            themeProc.running = true;
        } else {
            themeOpen = false;
            focusRowItem = null;
            kbIndex = -1;
        }
    }

    /**
     * Seeds every control from the current input.kdl snippet. Numbers fall back
     * to the defaults when a field is missing so a partially hand-edited config
     * never leaves a control blank.
     */
    function seed() {
        var k = inputFile.text();

        var sens = parseFloat(root.kdlField(k, "accel-speed"));
        root.sensitivity = isNaN(sens) ? 0 : sens;
        var ap = root.kdlField(k, "accel-profile");
        root.accelProfile = ap.length > 0 ? ap : "flat";
        var kl = root.kdlField(k, "layout");
        root.kbLayout = kl.length > 0 ? kl : "de";
        var rr = parseInt(root.kdlField(k, "repeat-rate"), 10);
        root.repeatRate = isNaN(rr) ? 25 : rr;
        var rd = parseInt(root.kdlField(k, "repeat-delay"), 10);
        root.repeatDelay = isNaN(rd) ? 600 : rd;
        root.numlockOn = root.kdlField(k, "numlock") === "true";

        var cs = parseInt(root.kdlField(k, "xcursor-size"), 10);
        root.cursorSize = isNaN(cs) ? 24 : cs;
        var ct = root.kdlField(k, "xcursor-theme");
        root.cursorTheme = ct.length > 0 ? ct : "Bibata-Modern-Ice";

        root.base = {
            sensitivity: root.sensitivity,
            repeatRate: root.repeatRate,
            repeatDelay: root.repeatDelay,
            cursorSize: root.cursorSize
        };
    }

    function buildConfig() {
        var out = "// Gerado pela pill — edite pela surface Input.\n";
        out += "input {\n";
        out += "    mouse {\n";
        out += "        accel-speed " + root.sensitivity + "\n";
        out += "        accel-profile \"" + root.accelProfile + "\"\n";
        out += "    }\n";
        out += "    keyboard {\n";
        out += "        repeat-delay " + root.repeatDelay + "\n";
        out += "        repeat-rate " + root.repeatRate + "\n";
        out += "        xkb { layout \"" + root.kbLayout + "\" }\n";
        out += "        numlock " + (root.numlockOn ? "true" : "false") + "\n";
        out += "    }\n";
        out += "    touchpad {\n";
        out += "        tap\n";
        out += "        natural-scroll\n";
        out += "    }\n";
        out += "}\n";
        out += "cursor {\n";
        out += "    xcursor-theme \"" + root.cursorTheme + "\"\n";
        out += "    xcursor-size " + root.cursorSize + "\n";
        out += "}\n";
        return out;
    }

    /** Regenerates the whole profile from the current properties and reloads
     * niri (debounced) so the change lands at once. */
    function writeInput() {
        inputWriter.setText(buildConfig());
        reloadTimer.restart();
    }

    function setKbLayout(v) {
        root.kbLayout = v;
        root.writeInput();
    }

    FileView {
        id: inputFile
        path: root.inputPath
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: inputWriter
        path: root.inputPath
        atomicWrites: true
        printErrors: false
    }

    /**
     * Reload is debounced so a scrub drag writes the file per step but reloads
     * niri once, and captured so a failed reload surfaces as the inline note
     * instead of vanishing with a detached process. niri's config watcher is
     * live-reloading the included snippet on save; this is belt-and-braces.
     */
    Timer {
        id: reloadTimer
        interval: 250
        repeat: false
        onTriggered: reloadProc.running = true
    }

    Process {
        id: reloadProc
        command: ["niri", "msg", "action", "load-config-file", "--path", "/etc/niri/config.kdl"]
        onExited: function (exitCode) {
            root.note = exitCode === 0 ? "" : "niri reload failed. The change is saved but not applied.";
        }
    }

    Process {
        id: themeProc
        command: ["sh", "-c", "{ printf '%s\\n' \"$HOME/.icons\" \"$HOME/.local/share/icons\" /usr/share/icons; printf '%s' \"${XDG_DATA_DIRS:-/usr/local/share:/usr/share}\" | tr ':' '\\n' | sed 's#/*$#/icons#'; } | sort -u | while IFS= read -r d; do [ -d \"$d\" ] || continue; for t in \"$d\"/*/; do [ -d \"$t/cursors\" ] && basename \"$t\"; done; done | sort -u"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n").filter(function (l) { return l.trim().length > 0; });
                root.cursorThemes = lines;
            }
        }
    }

    component GroupLabel: Text {
        topPadding: 16 * root.s
        bottomPadding: 6 * root.s
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 8.5 * root.s
        font.weight: Font.Bold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1.2 * root.s
    }

    /**
     * One settings line. At rest it is an icon + label + control row; hovering or
     * keyboard-focusing the row folds its grey caption open below the label so
     * the tab stays compact by default. The row feeds the surface registry: hover
     * moves the soul seam and a click anywhere on the line drives its control via
     * activateRow.
     */
    component FieldRow: Item {
        id: frow
        property string label: ""
        property string caption: ""
        property string icon: ""
        default property alias control: ctrl.data

        readonly property bool focused: root.focusRowItem === frow
        readonly property bool expanded: fhover.hovered || frow.focused
        readonly property real rowH: 30 * root.s
        readonly property real capH: 14 * root.s

        width: parent ? parent.width : 0
        height: frow.rowH + (frow.expanded ? frow.capH : 0)
        clip: true
        Behavior on height { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

        HoverHandler {
            id: fhover
            onHoveredChanged: root.reportRowHover(frow, hovered)
        }

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 3 * root.s
            anchors.bottomMargin: 3 * root.s
            radius: 9 * root.s
            color: (fhover.hovered || frow.focused) ? Theme.frameBg : "transparent"
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.activateRow(frow)
        }

        GlyphIcon {
            id: rowIcon
            anchors.left: parent.left
            anchors.leftMargin: 9 * root.s
            anchors.verticalCenter: parent.verticalCenter
            visible: frow.icon.length > 0
            width: 15 * root.s
            height: 15 * root.s
            name: frow.icon
            color: frow.focused ? Theme.cream : Theme.subtle
            stroke: 1.8
        }

        Column {
            anchors.left: rowIcon.visible ? rowIcon.right : parent.left
            anchors.leftMargin: 9 * root.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2 * root.s

            Text {
                text: frow.label
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 12.5 * root.s
                font.weight: Font.Medium
            }

            Text {
                visible: frow.expanded && frow.caption.length > 0
                text: frow.caption
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 9 * root.s
                font.weight: Font.Medium
            }
        }

        Item {
            id: ctrl
            anchors.right: parent.right
            anchors.rightMargin: 9 * root.s
            anchors.verticalCenter: parent.verticalCenter
            width: childrenRect.width
            height: childrenRect.height
        }
    }

    Column {
        id: content
        z: 100
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0
        height: root.height + root.mBottom * root.s
        clip: true

        SettingsHeader {
            s: root.s
            glyph: "操"
            title: "INPUT"
            showBack: true
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 12 * root.s
            anchors.rightMargin: 12 * root.s
            spacing: 0

            GroupLabel { text: "Pointer" }

            FieldRow {
                id: sensRow
                label: "Sensitivity"
                caption: "Pointer speed offset"
                icon: "mouse"
                ScrubValue {
                    id: sensScrub
                    s: root.s
                    value: root.sensitivity
                    openValue: root.base.sensitivity
                    from: -1; to: 1; step: 0.1; decimals: 1
                    onEdited: v => {
                        root.sensitivity = v;
                        root.writeInput();
                    }
                }
            }

            FieldRow {
                id: accelRow
                label: "Acceleration"
                caption: "How pointer speed follows motion"
                icon: "bolt"
                SettingsSeg {
                    s: root.s
                    options: root.accelOptions
                    value: root.accelProfile
                    onPicked: (v) => {
                        root.accelProfile = v;
                        root.writeInput();
                    }
                }
            }

            GroupLabel { text: "Keyboard" }

            FieldRow {
                id: layoutRow
                label: "Layout"
                caption: "Click to cycle common layouts"
                icon: "language"

                Rectangle {
                    width: layoutLbl.implicitWidth + 20 * root.s
                    height: 22 * root.s
                    radius: 9 * root.s
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.hairSoft

                    Text {
                        id: layoutLbl
                        anchors.centerIn: parent
                        text: root.kbLayout
                        color: Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 11 * root.s
                        font.weight: Font.DemiBold
                    }
                }
            }

            FieldRow {
                id: rateRow
                label: "Repeat rate"
                caption: "Key repeats per second when held"
                icon: "keyboard"
                ScrubValue {
                    id: rateScrub
                    s: root.s
                    value: root.repeatRate
                    openValue: root.base.repeatRate
                    from: 10; to: 80; step: 1; unit: "Hz"
                    onEdited: v => {
                        root.repeatRate = v;
                        root.writeInput();
                    }
                }
            }

            FieldRow {
                id: delayRow
                label: "Repeat delay"
                caption: "Hold time before a key repeats"
                icon: "stopwatch"
                ScrubValue {
                    id: delayScrub
                    s: root.s
                    value: root.repeatDelay
                    openValue: root.base.repeatDelay
                    from: 150; to: 1000; step: 25; unit: "ms"
                    onEdited: v => {
                        root.repeatDelay = v;
                        root.writeInput();
                    }
                }
            }

            FieldRow {
                id: numlockRow
                label: "Numlock"
                caption: "Numlock on at startup"
                icon: "lock"
                LinkToggle {
                    s: root.s
                    on: root.numlockOn
                    onToggled: {
                        root.numlockOn = !root.numlockOn;
                        root.writeInput();
                    }
                }
            }

            GroupLabel { text: "Cursor" }

            FieldRow {
                id: sizeRow
                label: "Size"
                caption: "Cursor size in pixels"
                icon: "cursor"
                ScrubValue {
                    id: sizeScrub
                    s: root.s
                    value: root.cursorSize
                    openValue: root.base.cursorSize
                    from: 12; to: 96; step: 4; unit: "px"
                    onEdited: v => {
                        root.cursorSize = v;
                        root.writeInput();
                    }
                }
            }

            Item { width: 1; height: 8 * root.s }

            /**
             * DisplayPicker draws its own chip and dropdown, so the wrapper only
             * adds what the registry needs: hover for the soul seam and a
             * fall-through click that toggles the picker like the chip does.
             */
            Item {
                id: themeRow
                width: parent ? parent.width : 0
                height: themePick.implicitHeight

                HoverHandler {
                    onHoveredChanged: root.reportRowHover(themeRow, hovered)
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.activateRow(themeRow)
                }

                DisplayPicker {
                    id: themePick
                    s: root.s
                    label: "Theme"
                    options: root.cursorThemes.map(function (t) { return { label: t, value: t }; })
                    value: root.cursorTheme
                    open: root.themeOpen
                    onRequestToggle: root.themeOpen = !root.themeOpen
                    onPicked: (v) => {
                        root.cursorTheme = v;
                        root.themeOpen = false;
                        root.writeInput();
                    }
                }
            }

            Text {
                width: parent.width
                topPadding: 8 * root.s
                visible: root.note.length > 0
                text: root.note
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.weight: Font.Medium
                wrapMode: Text.WordWrap
                lineHeight: 1.25
            }

            Item { width: 1; height: 10 * root.s }
        }
    }
}
