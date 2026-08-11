pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * 灯 Night-light controller over gammastep. Every change rewrites
 * ~/.config/gammastep/config.ini from the Flags and restarts the user unit, so
 * the tint follows the clock on its own and survives a logout. Scheduled mode
 * maps dawn (day start) to the user's "off" clock and dusk (night start) to
 * their "on" clock — night is between on and off, day is the rest.
 */
Singleton {
    id: root

    readonly property string confPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/gammastep/config.ini"

    function clampTemp(t) {
        return Math.max(2200, Math.min(6500, Math.round(t)));
    }

    function hhmm(min) {
        var h = Math.floor(min / 60);
        var m = min % 60;
        return h + ":" + (m < 10 ? "0" + m : m);
    }

    /** gammastep config.ini for the current Flags. Off and On are one all-day
     * profile; Scheduled uses dawn-time/dusk-time so the daemon flips alone. */
    function buildConf() {
        var out = "[general]\n";
        if (Flags.nightLightMode === "scheduled") {
            out += "dawn-time=" + root.hhmm(Flags.nightLightOffMin) + "\n"
                + "dusk-time=" + root.hhmm(Flags.nightLightOnMin) + "\n"
                + "temp-day=6500\n"
                + "temp-night=" + root.clampTemp(Flags.nightLightTemp) + "\n";
        } else {
            var t = Flags.nightLightMode === "on" ? root.clampTemp(Flags.nightLightTemp) : 6500;
            out += "temp-day=" + t + "\n"
                + "temp-night=" + t + "\n";
        }
        return out;
    }

    function commit(restart) {
        writer.setText(root.buildConf());
        if (restart)
            restartProc.running = true;
    }

    function setMode(m) {
        Flags.nightLightMode = m;
        root.commit(true);
    }

    function setTemp(t) {
        Flags.nightLightTemp = root.clampTemp(t);
        root.commit(Flags.nightLightMode === "scheduled");
    }

    function setOnMin(v) {
        Flags.nightLightOnMin = v;
        root.commit(Flags.nightLightMode === "scheduled");
    }

    function setOffMin(v) {
        Flags.nightLightOffMin = v;
        root.commit(Flags.nightLightMode === "scheduled");
    }

    FileView {
        id: writer
        path: root.confPath
        atomicWrites: true
        printErrors: false
    }

    Process {
        id: restartProc
        command: ["systemctl", "--user", "restart", "gammastep"]
    }
}