// Workspace / window switcher for Hyprland.
// Left: column of workspaces, each with horizontal bars for its windows.
// Right: zoomed live preview of the selected window.
// Part of: qs -c desktop
// Control: qs -c desktop ipc call coverflow next|prev|confirm|cancel|state
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets

Scope {
    id: root

    property bool opened: false
    // ---------- open/close animation ----------
    property bool shown: false      // overlay mapped (stays true while the close animation runs)
    property real progress: 0       // 0 = hidden, 1 = fully open
    property bool fromBottom: false // opened by the 3-finger swipe up: everything rises from below
    property bool intro: false      // right after opening: workspace blocks appear one by one
    property bool loading: false
    property bool pendingConfirm: false
    property int pendingSteps: 0
    // Mouse mode: set once the pointer moves while open. Releasing the modifier then
    // keeps the switcher open so it can be used with the mouse (SUPER+click is taken
    // by Hyprland's movewindow bind while the modifier is held).
    property bool sticky: false
    property point pointerStart: Qt.point(-1, -1)
    property int currentIndex: 0
    // Windows in visual order (grouped by workspace):
    // [{ address, title, cls, wsId, wsName, mru, toplevel }]
    property var windows: []
    // [{ id, name, focused, items: [window indices] }]
    property var groups: []

    readonly property var current: windows[currentIndex]
    readonly property color accent: "#66ccff"

    function norm(a) {
        return (a || "").toLowerCase().replace(/^0x/, "");
    }

    function findToplevel(addr) {
        const n = norm(addr);
        const list = Hyprland.toplevels.values;
        for (let i = 0; i < list.length; i++)
            if (norm(list[i].address) === n)
                return list[i].wayland;
        return null;
    }

    function icon(cls) {
        return Quickshell.iconPath((cls || "").toLowerCase(), "application-x-executable");
    }

    function wrap(i) {
        const n = windows.length;
        return n === 0 ? 0 : ((i % n) + n) % n;
    }

    function step(d) {
        if (!opened) {
            open(d);
            return;
        }
        if (loading) {
            pendingSteps += d;
            return;
        }
        currentIndex = wrap(currentIndex + d);
    }

    function open(d) {
        windows = [];
        groups = [];
        currentIndex = 0;
        pendingSteps = d;
        pendingConfirm = false;
        sticky = false;
        pointerStart = Qt.point(-1, -1);
        loading = true;
        fromBottom = false;
        introTimer.restart();
        shown = true;
        opened = true;
        progressAnim.stop();
        progressAnim.to = 1;
        progressAnim.duration = 240;
        progressAnim.easing.type = Easing.OutCubic;
        progressAnim.start();
        clientsProc.running = true;
    }

    function loaded(clients) {
        if (!opened)
            return;
        loading = false;
        if (clients.length === 0) {
            close();
            return;
        }

        // Visual order: normal workspaces by id, special workspaces last; MRU inside a workspace
        const wsKey = c => c.wsId > 0 ? c.wsId : 100000 - c.wsId;
        const list = clients.slice().sort((a, b) => wsKey(a) - wsKey(b) || a.mru - b.mru);

        setList(list);

        if (keepAddress !== "") {   // refresh after closing a window
            const k = list.findIndex(w => w.address === keepAddress);
            keepAddress = "";
            currentIndex = k >= 0 ? k : wrap(currentIndex);
            return;
        }

        // First press selects the previously used window (MRU #1), further presses walk the list
        const byMru = r => Math.max(0, list.findIndex(w => w.mru === r));
        const s = pendingSteps;
        pendingSteps = 0;
        if (s > 0)
            currentIndex = wrap(byMru(list.length > 1 ? 1 : 0) + s - 1);
        else
            currentIndex = wrap(byMru(0) + s);

        if (pendingConfirm)
            confirm();
    }

    function confirm() {
        if (!opened)
            return;
        if (loading) {
            pendingConfirm = true;
            return;
        }
        const w = windows[currentIndex];
        close();
        if (w) {
            // Focus only after the overlay has unmapped, otherwise Hyprland
            // restores focus to the previous window when the layer goes away.
            focusTimer.address = w.address;
            focusTimer.restart();
        }
    }

    // Modifier released: pick the window, unless the user switched to mouse mode
    function release() {
        if (!sticky)
            confirm();
    }

    function pointerAt(p) {
        if (!opened || sticky)
            return;
        if (pointerStart.x < 0) {
            pointerStart = p;
            return;
        }
        const dx = p.x - pointerStart.x, dy = p.y - pointerStart.y;
        if (dx * dx + dy * dy > 100)
            sticky = true;
    }

    // ---------- scrolling through the list ----------
    // A touchpad sends dozens of small wheel events per swipe (plus kinetic ones after the
    // fingers lift). Accumulate them: one step per mouse-wheel notch (120 units) and at most
    // one step every wheelMinInterval ms, leftovers are dropped so it never runs away.
    readonly property int wheelNotch: 120
    readonly property int wheelMinInterval: 90
    property real wheelAcc: 0
    property double lastWheelStep: 0

    function wheelStep(wheel) {
        sticky = true;
        const d = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
        if (d === 0)
            return;
        if (wheelAcc !== 0 && Math.sign(d) !== Math.sign(wheelAcc))
            wheelAcc = 0; // direction changed
        wheelAcc += d;
        const now = Date.now();
        if (Math.abs(wheelAcc) >= wheelNotch && now - lastWheelStep >= wheelMinInterval) {
            step(wheelAcc > 0 ? -1 : 1);
            wheelAcc = 0;
            lastWheelStep = now;
        }
    }

    // Hyprland >= 0.57: dispatch takes a Lua dispatcher expression
    function focusWindow(address) {
        Hyprland.dispatch('hl.dsp.focus({ window = "address:' + address + '" })');
    }

    // ---------- profiles: saved sets of apps + their workspaces ----------
    // ~/.local/state/quickshell-switcher/profiles.json
    //   { profiles: [ { name, apps: [ { cls, ws, cmd } ] } ] }
    // Applying one opens only the apps that are missing (DESKTOP_PROFILE_LAUNCH in hypr/lua/desktop.lua).
    property var profiles: []
    readonly property string profDir: Quickshell.env("HOME") + "/.local/state/quickshell-switcher"

    FileView {
        id: profFile
        path: root.profDir + "/profiles.json"
        printErrors: false
        watchChanges: true            // hand edits of profiles.json are picked up
        onFileChanged: reload()
        onLoaded: {
            try {
                root.profiles = JSON.parse(text()).profiles || [];
            } catch (e) {
                console.warn("switcher: bad profiles file", e);
            }
        }
    }
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", profDir])

    function writeProfiles(list) {
        profiles = list;
        profFile.setText(JSON.stringify({ profiles: list }, null, 1));
    }

    function focusStage() {
        stage.forceActiveFocus();
    }

    // Pair the profile's apps with open windows: same class on the same workspace first,
    // then same class anywhere. Whatever is left over is missing.
    // key of a window/app: its class, or for class-less windows (e.g. Java apps such as
    // SQL Developer) the app name found in the title
    function appKey(a) {
        return a.cls ? a.cls.toLowerCase() : "title:" + (a.match || "").toLowerCase();
    }

    function profileMatch(p) {
        const pool = {};
        const titled = (p.apps || []).filter(a => !a.cls && a.match).map(a => a.match.toLowerCase());
        windows.forEach(w => {
            let k = (w.cls || "").toLowerCase();
            if (!k) {
                const t = (w.title || "").toLowerCase();
                const m = titled.find(x => t.includes(x));
                if (!m)
                    return;
                k = "title:" + m;
            }
            (pool[k] = pool[k] || []).push(w.wsId);
        });
        const left = [];
        (p.apps || []).forEach(a => {
            const ws = pool[root.appKey(a)] || [];
            const i = ws.indexOf(a.ws);
            if (i >= 0) ws.splice(i, 1);
            else left.push(a);
        });
        const missing = [];
        left.forEach(a => {
            const ws = pool[root.appKey(a)] || [];
            if (ws.length) ws.shift();
            else missing.push(a);
        });
        return missing;
    }

    function profileStatus(p) {
        return { total: (p.apps || []).length, missing: profileMatch(p).length };
    }

    function applyProfile(i) {
        const p = profiles[i];
        if (!p || loading)
            return;
        const missing = profileMatch(p);
        close();
        if (missing.length === 0) {
            Quickshell.execDetached(["notify-send", "-a", "Window switcher", "-i", "view-grid",
                                     p.name, "Tất cả " + p.apps.length + " ứng dụng đã mở"]);
            return;
        }
        const q = s => "[==[" + String(s).replace(/\]==\]/g, "") + "]==]";
        const lua = missing.map(a => "DESKTOP_PROFILE_LAUNCH(" + q(a.cls) + ", " + a.ws + ", " + q(a.cmd) + ")").join("; ");
        Quickshell.execDetached(["hyprctl", "eval", lua]);
        const names = missing.map(a => a.cls + " → " + a.ws).join("\n");
        Quickshell.execDetached(["notify-send", "-a", "Window switcher", "-i", "view-grid",
                                 p.name + ": mở " + missing.length + " ứng dụng", names]);
    }

    function renameProfile(i, name) {
        const list = profiles.slice();
        if (!list[i])
            return;
        list[i] = Object.assign({}, list[i], { name: name });
        writeProfiles(list);
    }

    function deleteProfile(i) {
        const list = profiles.slice();
        const p = list.splice(i, 1)[0];
        writeProfiles(list);
        if (p)
            profileBar.showToast("Đã xóa “" + p.name + "”");
    }

    // Save the current layout into profile i (-1 = new). The launch command of each app comes
    // from its .desktop entry; apps without one use their process command line.
    function saveProfile(i) {
        const wins = windows.filter(w => w.wsId > 0);
        if (!wins.length || cmdProc.running)
            return;
        cmdProc.target = i;
        cmdProc.wins = wins;
        const pids = [...new Set(wins.map(w => String(w.pid)))];
        cmdProc.command = ["sh", "-c",
            'for p; do printf "%s\\t" "$p"; tr "\\0" "\\037" < /proc/$p/cmdline 2>/dev/null; echo; done',
            "sh"].concat(pids);
        cmdProc.running = true;
    }

    function cleanExec(e) {
        return e && e.execString ? e.execString.replace(/\s+%[fFuUdDnNickvm]/g, "").replace(/%%/g, "%").trim() : "";
    }

    function desktopCommand(cls) {
        return cls ? cleanExec(DesktopEntries.heuristicLookup(cls)) : "";
    }

    // class-less window: the longest app name that appears in its title
    function entryFromTitle(title) {
        const t = (title || "").toLowerCase();
        let best = null;
        DesktopEntries.applications.values.forEach(e => {
            const n = (e.name || "").toLowerCase();
            if (n.length >= 4 && t.includes(n) && (!best || n.length > best.name.length))
                best = e;
        });
        return best;
    }

    function shellJoin(args) {
        return args.map(a => /^[\w@%+=:,.\/-]+$/.test(a) ? a : "'" + a.replace(/'/g, "'\\''") + "'").join(" ");
    }

    function finishSave(cmdlines) {
        const apps = [];
        cmdProc.wins.forEach(w => {
            if (!w.cls) {
                const e = entryFromTitle(w.title);
                if (e && cleanExec(e))
                    apps.push({ cls: "", match: e.name, ws: w.wsId, cmd: cleanExec(e) });
                return;
            }
            let cmd = desktopCommand(w.cls);
            if (!cmd && cmdlines[String(w.pid)])
                cmd = shellJoin(cmdlines[String(w.pid)]);
            if (cmd)
                apps.push({ cls: w.cls, ws: w.wsId, cmd: cmd });
        });
        apps.sort((a, b) => a.ws - b.ws);
        const list = profiles.slice();
        const i = cmdProc.target;
        let name;
        if (i >= 0 && list[i]) {
            name = list[i].name;
            list[i] = { name: name, apps: apps };
        } else {
            let n = 1;
            while (list.some(p => p.name === "Profile " + n))
                n++;
            name = "Profile " + n;
            list.push({ name: name, apps: apps });
        }
        writeProfiles(list);
        const skipped = cmdProc.wins.length - apps.length;
        profileBar.showToast("✓ Đã lưu “" + name + "” — " + apps.length + " ứng dụng"
                             + (skipped ? " (bỏ qua " + skipped + " không rõ lệnh mở)" : ""));
    }

    Process {
        id: cmdProc
        property int target: -1
        property var wins: []
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {};
                this.text.split("\n").forEach(line => {
                    const t = line.indexOf("\t");
                    if (t < 0)
                        return;
                    const args = line.slice(t + 1).split("\x1f").filter(x => x !== "");
                    if (args.length)
                        map[line.slice(0, t)] = args;
                });
                root.finishSave(map);
            }
        }
    }

    // ---------- "Tiled": open a workspace with all its windows tiled ----------
    // (no fullscreen / maximized / floating; done in Lua: DESKTOP_TILE_WS in hypr/lua/desktop.lua)
    function tileWorkspace(id) {
        if (!opened || !(id > 0))
            return;
        close();
        tileTimer.wsId = id;
        tileTimer.restart();   // after the overlay is gone, like focusTimer
    }

    Timer {
        id: tileTimer
        property int wsId: 0
        interval: 40
        onTriggered: tileProc.exec(["hyprctl", "eval", "DESKTOP_TILE_WS(" + wsId + ")"])
    }

    Process {
        id: tileProc
    }

    // ---------- closing a window from the switcher ----------
    // The switcher stays open (mouse mode) and the list updates; the list is re-read shortly
    // after, so an app that refuses to close (e.g. "save changes?") shows up again.
    property string keepAddress: ""   // selection to keep across a refresh

    property string closingAddress: "" // bar playing its "closing" animation

    function closeWindow(i) {
        const w = windows[i];
        if (!w || loading || closingAddress !== "")
            return;
        sticky = true;
        Hyprland.dispatch('hl.dsp.window.close({ window = "address:' + w.address + '" })');
        closingAddress = w.address;   // let the bar slide out first, then drop it from the list
        removeTimer.restart();
    }

    Timer {
        id: removeTimer
        interval: 220
        onTriggered: root.dropClosed()
    }

    function dropClosed() {
        const addr = closingAddress;
        closingAddress = "";
        const i = windows.findIndex(w => w.address === addr);
        if (!opened || i < 0)
            return;
        const list = windows.filter((_, j) => j !== i);
        if (list.length === 0) {
            close();
            return;
        }
        const next = list[Math.min(i, list.length - 1)];
        setList(list);
        currentIndex = Math.max(0, list.indexOf(next));
        keepAddress = next.address;
        refreshTimer.restart();
    }

    function setList(list) {
        const focusedWs = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : null;
        const gs = [];
        list.forEach((w, i) => {
            let g = gs.length ? gs[gs.length - 1] : null;
            if (!g || g.id !== w.wsId) {
                g = { id: w.wsId, name: w.wsName, focused: w.wsId === focusedWs, items: [], untiled: 0 };
                gs.push(g);
            }
            g.items.push(i);
            if (w.fs || w.floating)
                g.untiled++;
        });
        windows = list;
        groups = gs;
    }

    Timer {
        id: refreshTimer
        interval: 450
        onTriggered: if (root.opened && !root.loading) clientsProc.running = true
    }

    function close() {
        refreshTimer.stop();
        removeTimer.stop();
        closingAddress = "";
        keepAddress = "";
        sticky = false;
        loading = false;
        if (!opened)
            return;
        opened = false;   // keyboard is released immediately (see keyboardFocus)
        progressAnim.stop();
        progressAnim.to = 0;
        progressAnim.duration = 150;
        progressAnim.easing.type = Easing.InCubic;
        progressAnim.start();
    }

    NumberAnimation {
        id: progressAnim
        target: root
        property: "progress"
        onFinished: {
            if (!root.opened) {   // close animation done: unmap and drop the window list
                root.shown = false;
                root.windows = [];
                root.groups = [];
            }
        }
    }
    Timer {
        id: introTimer
        interval: 700
        onRunningChanged: if (running) root.intro = true
        onTriggered: root.intro = false
    }

    Timer {
        id: focusTimer
        property string address: ""
        interval: 40
        onTriggered: {
            root.focusWindow(address);
            Hyprland.dispatch('hl.dsp.window.alter_zorder({ window = "address:' + address + '", mode = "top" })');
            refocusTimer.restart();
        }
    }

    // With follow_mouse = 1, switching workspace makes Hyprland focus the window under
    // the cursor; focus the chosen window again once the workspace switch has settled.
    Timer {
        id: refocusTimer
        interval: 150
        onTriggered: root.focusWindow(focusTimer.address)
    }

    IpcHandler {
        target: "coverflow"
        function next(): void { root.step(1); }
        function prev(): void { root.step(-1); }
        function confirm(): void { root.confirm(); }
        function release(): void { root.release(); }
        // Touchpad gestures: open in mouse mode (stays open), swipe down closes
        function swipeUp(): void {
            if (root.opened) {
                root.close();
                return;
            }
            root.open(1);
            root.sticky = true;
            root.fromBottom = true;
        }
        function swipeDown(): void { root.close(); }
        function cancel(): void { root.close(); }
        function closeCurrent(): void { root.closeWindow(root.currentIndex); }
        function state(): string {
            return JSON.stringify({ opened: root.opened, loading: root.loading,
                                    index: root.currentIndex, count: root.windows.length,
                                    selected: root.current ? root.current.cls : null });
        }
    }

    Process {
        id: clientsProc
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let arr = [];
                try {
                    arr = JSON.parse(this.text);
                } catch (e) {
                    console.warn("coverflow: cannot parse hyprctl output", e);
                }
                root.loaded(arr.filter(c => c.mapped && !c.hidden).map(c => ({
                    address: c.address,
                    title: c.title || c.class,
                    cls: c.class,
                    wsId: c.workspace ? c.workspace.id : 0,
                    wsName: c.workspace ? c.workspace.name : "",
                    mru: c.focusHistoryID,
                    pid: c.pid,
                    fs: c.fullscreen > 0,
                    floating: !!c.floating,
                    toplevel: root.findToplevel(c.address)
                })));
            }
        }
    }

    PanelWindow {
        id: panel

        visible: root.shown
        screen: {
            const m = Hyprland.focusedMonitor;
            const s = Quickshell.screens;
            for (let i = 0; i < s.length; i++)
                if (m && s[i].name === m.name)
                    return s[i];
            return s[0];
        }

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "coverflow"

        Rectangle {
            anchors.fill: parent
            color: "#e00b0d14"
            opacity: root.progress

            MouseArea {
                anchors.fill: parent
                enabled: root.opened
                onClicked: root.close()
                onWheel: wheel => root.wheelStep(wheel)
            }
        }

        // Hint at the bottom
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 18
            visible: root.shown
            opacity: root.progress
            text: profileBar.hint !== "" ? profileBar.hint
                  : root.sticky
                  ? "🖱  Chế độ chuột — rê để xem · click để chuyển · × / Delete đóng ứng dụng · ⊞ / T mở workspace dạng tiled · Esc để thoát"
                  : "Tab / Shift+Tab để chọn · thả Super để chuyển · Delete đóng ứng dụng · T mở workspace dạng tiled · di chuột để dùng chuột"
            color: profileBar.hint !== "" || root.sticky ? "#66ccff" : "#77ffffff"
            font.pixelSize: 13
        }

        Item {
            id: stage
            anchors.fill: parent
            anchors.margins: Math.round(Math.min(panel.width, panel.height) * 0.06)
            focus: root.opened
            enabled: root.opened
            transform: Translate { y: root.fromBottom ? 120 * (1 - root.progress) : 0 }

            readonly property real colW: Math.min(460, width * 0.32)
            readonly property real gap: 36
            readonly property real topH: profileBar.height + 16   // profile bar + spacing

            ProfileBar {
                id: profileBar
                sw: root
                width: parent.width
                opacity: root.progress
                transform: Translate { y: -24 * (1 - root.progress) }
            }

            Keys.onPressed: e => {
                switch (e.key) {
                case Qt.Key_Down:
                case Qt.Key_Tab:
                case Qt.Key_J:
                    root.step(1); break;
                case Qt.Key_Up:
                case Qt.Key_Backtab:
                case Qt.Key_K:
                    root.step(-1); break;
                case Qt.Key_Home:
                    root.currentIndex = 0; break;
                case Qt.Key_End:
                    root.currentIndex = root.windows.length - 1; break;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                case Qt.Key_Space:
                    root.confirm(); break;
                case Qt.Key_Escape:
                    root.close(); break;
                case Qt.Key_Delete:
                    root.closeWindow(root.currentIndex); break;
                case Qt.Key_T:
                    if (root.current)
                        root.tileWorkspace(root.current.wsId);
                    break;
                default:
                    return;
                }
                e.accepted = true;
            }
            // Releasing the modifier (Super or Alt) picks the current window
            // (backup for the Hyprland release bind)
            Keys.onReleased: e => {
                if (e.isAutoRepeat)
                    return;
                switch (e.key) {
                case Qt.Key_Super_L:
                case Qt.Key_Super_R:
                case Qt.Key_Meta:
                case Qt.Key_Alt:
                    root.release();
                }
            }

            // Detect pointer movement (passive, does not block clicks/hover below)
            HoverHandler {
                id: hover
            }
            readonly property point hoverPos: hover.point.position
            onHoverPosChanged: if (hover.hovered) root.pointerAt(hoverPos)

            // ---------- Left: workspace column ----------
            Flickable {
                id: list
                width: stage.colW
                height: Math.min(stage.height - stage.topH, col.implicitHeight)
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: stage.topH / 2
                contentHeight: col.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                // no own scrolling: the wheel moves the selection (root.wheelStep) and the
                // column follows the selected bar (ensureVisible)
                interactive: false
                opacity: root.progress
                transform: Translate { x: root.fromBottom ? 0 : -48 * (1 - root.progress) }

                Behavior on contentY { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                function ensureVisible(item) {
                    const p = item.mapToItem(col, 0, 0);
                    const pad = 48;
                    let y = contentY;
                    if (p.y - pad < y)
                        y = p.y - pad;
                    else if (p.y + item.height + pad > y + height)
                        y = p.y + item.height + pad - height;
                    contentY = Math.max(0, Math.min(y, contentHeight - height));
                }

                Column {
                    id: col
                    width: list.width
                    spacing: 14

                    Repeater {
                        model: root.groups

                        delegate: Rectangle {
                            id: wsBox
                            required property var modelData
                            required property int index

                            // appear one after another right after opening
                            property real appear: root.intro ? 0 : 1
                            opacity: appear
                            transform: Translate { x: -24 * (1 - wsBox.appear) }
                            Component.onCompleted: if (root.intro) wsIntro.start()
                            SequentialAnimation {
                                id: wsIntro
                                PauseAnimation { duration: 40 + Math.min(wsBox.index, 8) * 55 }
                                NumberAnimation { target: wsBox; property: "appear"; to: 1; duration: 260; easing.type: Easing.OutCubic }
                            }

                            width: col.width
                            implicitHeight: wsCol.implicitHeight + 20
                            radius: 14
                            color: "#141821"
                            border.width: 1
                            border.color: modelData.focused ? "#5566ccff" : "#22ffffff"

                            Column {
                                id: wsCol
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 6

                                // Workspace header
                                Item {
                                    width: wsCol.width
                                    height: 28

                                TileButton {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: wsBox.modelData.id > 0
                                    attention: wsBox.modelData.untiled > 0
                                    onClicked: root.tileWorkspace(wsBox.modelData.id)
                                }

                                Row {
                                    spacing: 8
                                    leftPadding: 4
                                    height: 28
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 24; height: 24; radius: 6
                                        color: wsBox.modelData.focused ? root.accent : "#2a3040"
                                        Text {
                                            anchors.centerIn: parent
                                            text: wsBox.modelData.id > 0 ? wsBox.modelData.id : "S"
                                            color: wsBox.modelData.focused ? "#0b0d14" : "white"
                                            font.pixelSize: 13
                                            font.bold: true
                                        }
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: (wsBox.modelData.id > 0 ? "Workspace " : "") + wsBox.modelData.name
                                              + (wsBox.modelData.focused ? "  ·  hiện tại" : "")
                                        color: "#aab4c8"
                                        font.pixelSize: 14
                                        font.bold: true
                                    }
                                }
                                }

                                // Window bars
                                Repeater {
                                    model: wsBox.modelData.items

                                    delegate: Rectangle {
                                        id: bar
                                        required property int modelData
                                        readonly property var win: root.windows[modelData]
                                        readonly property bool isCurrent: modelData === root.currentIndex
                                        readonly property bool closing: !!win && win.address === root.closingAddress
                                        clip: closing

                                        width: wsCol.width
                                        height: closing ? 0 : 46
                                        opacity: closing ? 0 : 1
                                        transform: Translate {
                                            x: bar.closing ? 60 : 0
                                            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.InCubic } }
                                        }
                                        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.InOutCubic } }
                                        Behavior on opacity { NumberAnimation { duration: 180 } }
                                        radius: 10
                                        color: closing ? "#55e0443e" : isCurrent ? "#2a66ccff" : barMouse.containsMouse ? "#1affffff" : "#0dffffff"
                                        border.width: isCurrent ? 2 : 0
                                        border.color: root.accent
                                        Behavior on color { ColorAnimation { duration: 120 } }

                                        onIsCurrentChanged: if (isCurrent) Qt.callLater(list.ensureVisible, bar)
                                        Component.onCompleted: if (isCurrent) Qt.callLater(list.ensureVisible, bar)

                                        // Accent strip on the selected bar
                                        Rectangle {
                                            visible: bar.isCurrent
                                            width: 4; radius: 2
                                            height: parent.height - 16
                                            anchors.left: parent.left
                                            anchors.leftMargin: 6
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: root.accent
                                        }

                                        Row {
                                            anchors.fill: parent
                                            anchors.leftMargin: 18
                                            anchors.rightMargin: 44
                                            spacing: 10
                                            IconImage {
                                                anchors.verticalCenter: parent.verticalCenter
                                                implicitSize: 26
                                                source: bar.win ? root.icon(bar.win.cls) : ""
                                            }
                                            Column {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width - 36
                                                Text {
                                                    width: parent.width
                                                    text: bar.win ? bar.win.title : ""
                                                    color: bar.isCurrent ? "white" : "#d0d6e2"
                                                    font.pixelSize: 14
                                                    font.bold: bar.isCurrent
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    width: parent.width
                                                    text: bar.win ? bar.win.cls : ""
                                                    color: "#7f8a9e"
                                                    font.pixelSize: 11
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: barMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            // In mouse mode the preview follows the pointer
                                            onEntered: if (root.sticky) root.currentIndex = bar.modelData
                                            onPositionChanged: if (root.sticky && !bar.isCurrent) root.currentIndex = bar.modelData
                                            onClicked: {
                                                root.currentIndex = bar.modelData;
                                                root.confirm();
                                            }
                                        }

                                        CloseButton {
                                            anchors.right: parent.right
                                            anchors.rightMargin: 9
                                            anchors.verticalCenter: parent.verticalCenter
                                            size: 26
                                            shown: bar.isCurrent || barMouse.containsMouse || hovered
                                            onClicked: root.closeWindow(bar.modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---------- Right: preview of the selected window ----------
            // Rounded live capture with a soft shadow and a hairline border; the details sit
            // underneath as quiet chips; the close button only appears while hovering the capture.
            Item {
                id: previewArea
                x: stage.colW + stage.gap
                y: stage.topH
                width: stage.width - x
                height: stage.height - stage.topH
                opacity: root.progress
                scale: 0.94 + 0.06 * root.progress

                readonly property real infoH: 76
                readonly property real r: 14

                Item {
                    id: frame
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -previewArea.infoH / 2
                    width: shot.hasContent ? shot.width : previewArea.width * 0.6
                    height: shot.hasContent ? shot.height : previewArea.height * 0.5
                    Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                    // soft shadow: a few widening, fading rounded rects
                    Repeater {
                        model: 4
                        Rectangle {
                            required property int index
                            readonly property real d: 4 + index * 7
                            x: -d; y: -d + 10
                            width: frame.width + 2 * d; height: frame.height + 2 * d
                            radius: previewArea.r + d
                            color: "black"
                            opacity: 0.16 - index * 0.035
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: previewArea.r
                        color: "#141821"
                    }

                    ScreencopyView {
                        id: shot
                        anchors.centerIn: parent
                        captureSource: root.shown && root.current ? root.current.toplevel : null
                        live: true
                        constraintSize: Qt.size(previewArea.width - 8, previewArea.height - previewArea.infoH - 8)
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: shotMask
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 1.0
                        }
                    }
                    Item {
                        id: shotMask
                        width: shot.width; height: shot.height
                        layer.enabled: true
                        visible: false
                        Rectangle { anchors.fill: parent; radius: previewArea.r; color: "black" }
                    }

                    IconImage {
                        anchors.centerIn: parent
                        visible: !shot.hasContent
                        implicitSize: 96
                        opacity: 0.8
                        source: root.current ? root.icon(root.current.cls) : ""
                    }

                    // hairline border + a faint top highlight (glass edge)
                    Rectangle {
                        anchors.fill: parent
                        radius: previewArea.r
                        color: "transparent"
                        border.width: 1
                        border.color: frameHover.hovered ? "#8066ccff" : "#2effffff"
                        Behavior on border.color { ColorAnimation { duration: 160 } }
                    }
                    Rectangle {
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.topMargin: 1
                        width: parent.width - 2 * previewArea.r
                        height: 1
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: "transparent" }
                            GradientStop { position: 0.5; color: "#59ffffff" }
                            GradientStop { position: 1; color: "transparent" }
                        }
                    }

                    HoverHandler { id: frameHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.confirm()
                    }

                    CloseButton {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 12
                        size: 34
                        label: "Đóng ứng dụng"
                        shown: !!root.current && (frameHover.hovered || hovered)
                        onClicked: root.closeWindow(root.currentIndex)
                    }
                }

                // gentle cross-fade when the selection changes
                ParallelAnimation {
                    id: zoomAnim
                    NumberAnimation { target: frame; property: "scale"; from: 0.985; to: 1; duration: 220; easing.type: Easing.OutCubic }
                    NumberAnimation { target: frame; property: "opacity"; from: 0.55; to: 1; duration: 220; easing.type: Easing.OutCubic }
                    NumberAnimation { target: info; property: "opacity"; from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }
                }
                Connections {
                    target: root
                    function onCurrentIndexChanged() { zoomAnim.restart(); }
                }

                // details under the capture, aligned with its left edge
                Column {
                    id: info
                    x: frame.x
                    width: frame.width
                    anchors.top: frame.bottom
                    anchors.topMargin: 18
                    spacing: 8
                    visible: !!root.current

                    Row {
                        spacing: 10
                        width: parent.width
                        IconImage {
                            anchors.verticalCenter: parent.verticalCenter
                            implicitSize: 20
                            source: root.current ? root.icon(root.current.cls) : ""
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 30
                            text: root.current ? root.current.title : ""
                            color: "#eef2f8"
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                    }

                    Row {
                        spacing: 6
                        leftPadding: 30
                        Repeater {
                            model: {
                                const c = root.current;
                                if (!c)
                                    return [];
                                const chips = [c.cls, (c.wsId > 0 ? "Workspace " : "") + c.wsName];
                                if (c.fs)
                                    chips.push("Full screen");
                                if (c.floating)
                                    chips.push("Nổi");
                                chips.push((root.currentIndex + 1) + " / " + root.windows.length);
                                return chips;
                            }
                            Rectangle {
                                required property string modelData
                                required property int index
                                height: 22
                                width: chipText.implicitWidth + 16
                                radius: 6
                                color: "#12ffffff"
                                border.width: 1
                                border.color: "#1affffff"
                                Text {
                                    id: chipText
                                    anchors.centerIn: parent
                                    text: parent.modelData
                                    color: "#9aa6ba"
                                    font.pixelSize: 11
                                    font.letterSpacing: 0.3
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
