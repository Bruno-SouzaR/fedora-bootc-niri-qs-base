pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

/**
 * 設 SETTINGS index: a short list of categories. Each row carries its kanji,
 * name and caption, and morphs the pill into that category's sub-surface.
 * Arrow keys move the focused row with the glowing seam and Return opens it.
 */
SettingsSurface {
    id: root

    implicitHeight: content.implicitHeight

    rows: [
        { item: appearanceRow, kind: "nav", surface: "appearance" },
        // display/keybinds/workspaces ROWS REMOVIDAS: surfaces Hyprland-only, seguem inertes no repo
        { item: inputRow, kind: "nav", surface: "input" },
        { item: idleRow, kind: "nav", surface: "idlelock" },
        { item: nightRow, kind: "nav", surface: "nightlight" }
    ]

    Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        SettingsHeader {
            s: root.s
            glyph: "設"
            title: "SETTINGS"
        }

        SettingsRow {
            id: appearanceRow
            surface: root
            captionOnFocus: true
            icon: "sparkles"
            name: "Appearance"
            sub: "Clock, glyphs, accent palette"

            GlyphIcon {
                width: 16 * root.s
                height: 16 * root.s
                name: "chevron-right"
                color: root.focusRowItem === appearanceRow ? Theme.cream : Theme.iconDim
                stroke: 2.2
            }
        }

        // display/keybinds/workspaces ROWS REMOVIDAS: surfaces Hyprland-only, seguem inertes no repo
        SettingsRow {
            id: inputRow
            surface: root
            captionOnFocus: true
            icon: "mouse"
            name: "Input"
            sub: "Pointer, keyboard, cursor"

            GlyphIcon {
                width: 16 * root.s
                height: 16 * root.s
                name: "chevron-right"
                color: root.focusRowItem === inputRow ? Theme.cream : Theme.iconDim
                stroke: 2.2
            }
        }

        SettingsRow {
            id: idleRow
            surface: root
            captionOnFocus: true
            icon: "lock"
            name: "Idle / Lock"
            sub: "Auto-lock, screen off, suspend"

            GlyphIcon {
                width: 16 * root.s
                height: 16 * root.s
                name: "chevron-right"
                color: root.focusRowItem === idleRow ? Theme.cream : Theme.iconDim
                stroke: 2.2
            }
        }

        SettingsRow {
            id: nightRow
            surface: root
            captionOnFocus: true
            icon: "moon"
            name: "Night light"
            sub: "Warmth, schedule"
            last: true

            GlyphIcon {
                width: 16 * root.s
                height: 16 * root.s
                name: "chevron-right"
                color: root.focusRowItem === nightRow ? Theme.cream : Theme.iconDim
                stroke: 2.2
            }
        }
    }
}
