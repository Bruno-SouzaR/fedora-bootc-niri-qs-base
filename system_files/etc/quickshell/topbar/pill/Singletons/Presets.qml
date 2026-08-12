// Presets.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/palette.js" as Palette

/**
 * Colour presets for the pill. The three factory presets (Warm/Cool/Mono) are
 * hardcoded in lib/palette.js and shipped read-only inside the bootc image, so
 * they can never be clobbered by an update and always come back after one.
 * User-saved presets live in ~/.config/pill/theme/custom.json, a plain editable
 * file the user can locate and tweak by hand. The exposed `list` is the merged
 * factory + custom view; selecting or saving writes only the custom file.
 * Registering in qmldir makes it a singleton so Theme.qml can read `active`.
 */
Singleton {
    id: root

    /** Id of the currently selected preset (factory or custom). */
    property string activeId: ""

    /**
     * Merged, ordered view: the immutable factory list first, then every user
     * preset from the custom file. Recomputes reactively when the custom file
     * reloads or is written.
     */
    readonly property var list: {
        var out = Palette.factoryPresets();
        for (var i = 0; i < adapter.custom.length; i++)
            out.push(adapter.custom[i]);
        return out;
    }

    readonly property var active: {
        for (var i = 0; i < root.list.length; i++)
            if (root.list[i].id === root.activeId)
                return root.list[i];
        return null;
    }

    FileView {
        id: file
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/pill/theme/custom.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: root.load()
        onLoaded: root.load()
        onLoadFailed: function(error) {
            if (error === FileViewError.FileNotFound) {
                root.load();
                file.writeAdapter();
            }
        }
        onAdapterUpdated: root.load()
        JsonAdapter {
            id: adapter
            property string activeId: ""
            property var custom: []
        }
    }

    /**
     * Re-read the active selection from the adapter. Reflects reads done on
     * initial load (onLoaded), on external edits (onFileChanged) and on our own
     * writes (onAdapterUpdated). Falls back to the first preset when the stored
     * activeId no longer exists; leaves the file untouched if it is missing.
     */
    function load() {
        root.activeId = adapter.activeId;
        var has = false;
        for (var i = 0; i < root.list.length; i++)
            if (root.list[i].id === root.activeId) has = true;
        if (!has)
            root.activeId = root.list.length > 0 ? root.list[0].id : "";
    }

    function select(id) {
        root.activeId = id;
        adapter.activeId = id;
        file.writeAdapter();
    }

    /**
     * Append (or replace an existing same-name user preset) a preset to the
     * custom file and select it. Factory presets are never replaced. Returns
     * the new id, or "" if the roles are invalid or the name is blank.
     */
    function save(name, roles) {
        var n = String(name || "").trim();
        if (!Palette.validate(roles) || n.length === 0)
            return "";
        var id = "user-" + n.toLowerCase().replace(/[^a-z0-9]+/g, "-");
        var customs = adapter.custom.slice();
        var replaced = false;
        for (var i = 0; i < customs.length; i++) {
            if (!customs[i].factory && customs[i].name === n) {
                customs[i] = { id: id, name: n, factory: false, roles: roles };
                replaced = true;
                break;
            }
        }
        if (!replaced)
            customs.push({ id: id, name: n, factory: false, roles: roles });
        adapter.custom = customs;
        adapter.activeId = id;
        root.activeId = id;
        file.writeAdapter();
        return id;
    }

    /**
     * Remove a custom preset by id; factory presets are ignored. Falls back to
     * the first remaining preset when the removed one was active.
     */
    function remove(id) {
        var customs = adapter.custom.filter(function (p) { return p.id !== id; });
        adapter.custom = customs;
        if (root.activeId === id)
            adapter.activeId = root.list.length > 0 ? root.list[0].id : "";
        root.load();
        file.writeAdapter();
    }
}
