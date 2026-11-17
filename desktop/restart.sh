#!/usr/bin/env bash
# Restart the desktop Quickshell (window switcher + launcher) to apply QML edits.
# (hot reload is off, see shell.qml)
QS="$HOME/.local/bin/qs"
[[ -x "$QS" ]] || QS=qs
pkill -x -f "$QS -c desktop" 2>/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x -f "$QS -c desktop" >/dev/null || break; sleep 0.2; done
if command -v hyprctl >/dev/null && [[ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]]; then
    hyprctl dispatch "hl.dsp.exec_cmd(\"$QS -c desktop\")" >/dev/null   # child of Hyprland, like at login
else
    setsid -f "$QS" -c desktop >/dev/null 2>&1
fi
for _ in $(seq 1 25); do
    "$QS" -c desktop ipc call coverflow state 2>/dev/null | grep -q opened && { echo "quickshell desktop: ok"; exit 0; }
    sleep 0.2
done
echo "quickshell desktop: not answering yet — check: $QS log -c desktop" >&2; exit 1
