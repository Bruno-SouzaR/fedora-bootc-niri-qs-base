// Presets.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/palette.js" as Palette

/**
 * Persisted colour presets. Seeds the three factory presets the first time the
 * file is missing, then lives in ~/.local/state/ricelin/presets.json. `save`
 * appends a user preset (replacing any user preset with the same name) and makes
 * it active; `select` switches the active preset. Factory presets are immutable.
 * Registering in qmldir makes it a singleton so Theme.qml can read `active`.
 */
Singleton {
    id: root

    property string activeId: ""
    property var list: []

    readonly property var active: {
        if (root.activeId) {
            for (var i = 0; i < root.list.length; i++)
                if (root.list[i].id === root.activeId)
                    return root.list[i];
        }
        return null;
    }

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ricelin/presets.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: root.load()
        onLoadFailed: function(error) {
            if (error === FileViewError.FileNotFound)
                root.seed();
        }
        onAdapterUpdated: root.load()
        JsonAdapter {
            id: adapter
            property string activeId: ""
            property var presets: []
        }
    }

    function seed() {
        adapter.presets = Palette.factoryPresets();
        adapter.activeId = adapter.presets[0].id;
        file.writeAdapter();
    }

    function load() {
        root.list = adapter.presets;
        root.activeId = adapter.activeId;
        if (!root.list || root.list.length === 0) { root.seed(); return; }
        var has = false;
        for (var i = 0; i < root.list.length; i++)
            if (root.list[i].id === root.activeId) has = true;
        if (!has) root.activeId = root.list[0].id;
    }

    function select(id) {
        root.activeId = id;
        adapter.activeId = id;
        file.writeAdapter();
    }

    function save(name, roles) {
        if (!Palette.validate(roles)) return "";
        var id = "user-" + name.toLowerCase().replace(/[^a-z0-9]+/g, "-");
        var presets = root.list.slice();
        var replaced = false;
        for (var i = 0; i < presets.length; i++) {
            if (!presets[i].factory && presets[i].name === name) {
                presets[i] = { id: id, name: name, factory: false, roles: roles };
                replaced = true;
                break;
            }
        }
        if (!replaced)
            presets.push({ id: id, name: name, factory: false, roles: roles });
        adapter.presets = presets;
        adapter.activeId = id;
        root.list = presets;
        root.activeId = id;
        file.writeAdapter();
        return id;
    }
}
