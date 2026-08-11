pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "Singletons"

/**
 * 灯 NIGHT LIGHT sub-surface: the gammastep controls (on/off/scheduled, warmth,
 * and the two clock gates). Every change rewrites the config and restarts the
 * unit through the NightLight singleton, so the tint lands at once and survives
 * a logout. Reached from the settings index; morphs back on the back chevron.
 */
SettingsSurface {
    id: root

    backSurface: "settings"
    implicitHeight: content.implicitHeight

    readonly property var modeOptions: [
        { label: "Off", value: "off" }, { label: "On", value: "on" }, { label: "Scheduled", value: "scheduled" }
    ]

    /** Minutes-since-midnight rendered as HH:MM for the schedule scrubs. */
    function fmtClock(v) {
        var h = Math.floor(v / 60);
        var m = v % 60;
        return h + ":" + (m < 10 ? "0" + m : m);
    }

    rows: [
        { item: modeRow, kind: "seg", vals: root.modeOptions.map(function (o) { return o.value; }), get: function () { return Flags.nightLightMode; }, set: function (v) { NightLight.setMode(v); } },
        { item: tempRow, kind: "scrub", bump: function (d) { tempScrub.bump(d); } },
        { item: onRow, kind: "scrub", bump: function (d) { onScrub.bump(d); } },
        { item: offRow, kind: "scrub", bump: function (d) { offScrub.bump(d); } }
    ]

    /**
     * One night-light row: name and caption on their own full-width line with the
     * control stacked below. Hover lights the row and feeds the soul seam,
     * matching the rest of the settings rows.
     */
    component IdleRow: Item {
        id: irow
        property string name: ""
        property string caption: ""
        property bool last: false
        default property alias seg: segSlot.data
        readonly property real s: root.s

        width: parent ? parent.width : 0
        height: col.implicitHeight + 22 * irow.s

        HoverHandler {
            id: ih
            onHoveredChanged: root.reportRowHover(irow, hovered)
        }

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 3 * irow.s
            anchors.bottomMargin: 3 * irow.s
            radius: 9 * irow.s
            color: (ih.hovered || root.focusRowItem === irow) ? Theme.frameBg : "transparent"
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        Column {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 12 * irow.s
            anchors.rightMargin: 12 * irow.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3 * irow.s

            Text {
                text: irow.name
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 12.5 * irow.s
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                visible: irow.caption.length > 0
                text: irow.caption
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 10.5 * irow.s
            }
            Item { width: 1; height: 7 * irow.s }
            Item {
                id: segSlot
                width: childrenRect.width
                height: childrenRect.height
            }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Theme.hairSoft
            visible: !irow.last
        }
    }

    Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        SettingsHeader {
            s: root.s
            glyph: "灯"
            title: "NIGHT LIGHT"
            showBack: true
        }

        Item { width: 1; height: 12 * root.s }

        IdleRow {
            id: modeRow
            name: "Mode"
            caption: "Off, always warm, or auto by time"

            SettingsSeg {
                s: root.s
                flushLeft: true
                options: root.modeOptions
                value: Flags.nightLightMode
                onPicked: (v) => NightLight.setMode(v)
            }
        }

        IdleRow {
            id: tempRow
            name: "Warmth"
            caption: "Lower is warmer"

            ScrubValue {
                id: tempScrub
                s: root.s
                value: Flags.nightLightTemp
                from: 2200; to: 6500; step: 100; unit: "K"
                onEdited: (v) => NightLight.setTemp(v)
            }
        }

        IdleRow {
            id: onRow
            name: "On at"
            caption: "Warm tint starts"

            ScrubValue {
                id: onScrub
                s: root.s
                value: Flags.nightLightOnMin
                from: 0; to: 1439; step: 15
                fmt: root.fmtClock
                onEdited: (v) => NightLight.setOnMin(v)
            }
        }

        IdleRow {
            id: offRow
            name: "Off at"
            caption: "Back to neutral"
            last: true

            ScrubValue {
                id: offScrub
                s: root.s
                value: Flags.nightLightOffMin
                from: 0; to: 1439; step: 15
                fmt: root.fmtClock
                onEdited: (v) => NightLight.setOffMin(v)
            }
        }

        Item { width: 1; height: 10 * root.s }
    }
}