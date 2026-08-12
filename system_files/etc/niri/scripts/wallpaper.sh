#!/usr/bin/env bash
set -euo pipefail

flags_file="${XDG_STATE_HOME:-$HOME/.local/state}/ricelin/flags.json"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/ricelin-wallpaper"
MAP="${XDG_STATE_HOME:-$HOME/.local/state}/ricelin-wallpaper-map"
BAG="${XDG_STATE_HOME:-$HOME/.local/state}/ricelin-wallpaper-bag"
WLOG="${XDG_STATE_HOME:-$HOME/.local/state}/ricelin/wallcolors.log"

WPDIR=$(jq -r '.wallpaperDir // ""' "$flags_file" 2>/dev/null || echo "")
if [ -z "$WPDIR" ]; then
    for cand in "$HOME/Pictures/Wallpapers" "$HOME/Pictures/wallpapers" "$HOME/Wallpapers" "$HOME/wallpapers"; do
        [ -d "$cand" ] || continue
        n=$(find "$cand" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.webp' \) | head -2 | wc -l)
        if [ "$n" -ge 2 ]; then WPDIR="$cand"; break; fi
    done
    [ -n "$WPDIR" ] || WPDIR="$HOME/Ricelin/wallpapers"
fi
printf '%s\n' "$WPDIR" > "${XDG_STATE_HOME:-$HOME/.local/state}/ricelin-wallpaper-dir"
[ "${1:-}" = "resolve" ] && exit 0

list_pics() {
    find "$WPDIR" -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.webp' \)
}

refill_bag() {
    local current="" shuffled
    mkdir -p "$(dirname "$BAG")"
    [ -r "$STATE" ] && current=$(cat "$STATE")
    shuffled=$(list_pics | shuf)
    [ -n "$shuffled" ] || return 0
    if [ "$(printf '%s\n' "$shuffled" | head -n1)" = "$current" ] && [ "$(printf '%s\n' "$shuffled" | wc -l)" -gt 1 ]; then
        shuffled=$(printf '%s\n' "$shuffled" | tail -n +2; printf '%s\n' "$current")
    fi
    printf '%s\n' "$shuffled" > "$BAG"
}

pop_bag() {
    local line refilled=false
    mkdir -p "$(dirname "$BAG")"
    (
        flock 9
        while :; do
            if [ ! -s "$BAG" ]; then
                [ "$refilled" = true ] && exit 1
                refill_bag
                refilled=true
                [ -s "$BAG" ] || exit 1
            fi
            line=$(head -n1 "$BAG")
            tail -n +2 "$BAG" > "$BAG.tmp" && mv "$BAG.tmp" "$BAG"
            if [ -f "$line" ]; then
                printf '%s\n' "$line"
                exit 0
            fi
        done
    ) 9>"$BAG.lock"
}

outputs() {
    niri msg -j outputs 2>/dev/null | jq -r 'keys[]'
}

map_get() {
    awk -F'\t' -v o="$1" '$1 == o { print $2; exit }' "$MAP" 2>/dev/null || true
}

map_put() {
    mkdir -p "$(dirname "$MAP")"
    { awk -F'\t' -v o="$1" '$1 != o' "$MAP" 2>/dev/null || true; printf '%s\t%s\n' "$1" "$2"; } > "$MAP.tmp"
    mv "$MAP.tmp" "$MAP"
}

map_put_all() {
    local o
    mkdir -p "$(dirname "$MAP")"
    : > "$MAP.tmp"
    for o in $(outputs); do
        printf '%s\t%s\n' "$o" "$1" >> "$MAP.tmp"
    done
    mv "$MAP.tmp" "$MAP"
}

# swaybg is not an auto-singleton: a fresh apply must kill the previous one
# before spawning, otherwise two instances fight over the same buffers.
apply_visual() {
    pkill -x swaybg 2>/dev/null || true
    for _ in $(seq 1 20); do pgrep -x swaybg >/dev/null 2>&1 || break; sleep 0.1; done
    local o pic args=()
    for o in $(outputs); do
        pic=$(map_get "$o")
        [ -n "$pic" ] || pic="$1"
        args+=(-o "$o" -i "$pic")
    done
    [ "${#args[@]}" -gt 0 ] || return 0
    setsid -f swaybg "${args[@]}" >/dev/null 2>&1 || true
}

# The palette follows the focused monitor, matched by name.
focused_output() {
    niri msg -j focused-output 2>/dev/null | jq -r '.name // empty'
}

# The palette follows the focused monitor: whatever hangs there drives matugen,
# the global state file and the global still.
palette_update() {
    local focused pic
    focused=$(focused_output)
    pic=""
    [ -n "$focused" ] && pic=$(map_get "$focused")
    [ -n "$pic" ] || pic=$(cat "$STATE" 2>/dev/null || true)
    [ -n "$pic" ] && [ -f "$pic" ] || return 0
    mkdir -p "$(dirname "$STATE")"
    printf '%s\n' "$pic" > "$STATE"
    mkdir -p "$(dirname "$WLOG")"
    python3 "$(dirname "$0")/wallcolors.py" "$pic" >>"$WLOG" 2>&1 || true
    niri msg action load-config-file --path /etc/niri/config.kdl >/dev/null 2>&1 || true
    busctl --user call com.mitchellh.ghostty /com/mitchellh/ghostty org.gtk.Actions \
        Activate "sava{sv}" reload-config 0 0 >/dev/null 2>&1 || true
}

restore_all() {
    local o pic any=false
    for o in $(outputs); do
        pic=$(map_get "$o")
        [ -n "$pic" ] && [ -f "$pic" ] || pic=$(cat "$STATE" 2>/dev/null || true)
        [ -n "$pic" ] && [ -f "$pic" ] || pic=$(pop_bag) || continue
        map_put "$o" "$pic"
        any=true
    done
    [ "$any" = true ] || exit 0
    apply_visual ""
    palette_update
    exit 0
}

cmd="${1:-}"
target=""

if [ "$cmd" = "init" ]; then
    if [ ! -s "$MAP" ] && [ -s "$STATE" ]; then
        pic=$(cat "$STATE")
        [ -f "$pic" ] && map_put_all "$pic"
    fi
    restore_all
elif [ "$cmd" = "set" ]; then
    pic="${2:-}"
    [ -f "$pic" ] || exit 1
    target="${3:-}"
    [ "$target" = "all" ] && target=""
else
    scope=$(jq -r '.randomScope // "all"' "$flags_file" 2>/dev/null || echo all)
    if [ "$scope" = "cursor" ]; then
        target=$(focused_output)
    fi
    pic=$(pop_bag) || exit 0
fi

[ -n "$pic" ] || exit 0

if [ -n "$target" ]; then
    map_put "$target" "$pic"
else
    map_put_all "$pic"
fi

apply_visual "$pic"
palette_update
