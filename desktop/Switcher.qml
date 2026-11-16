// Workspace / window switcher for Hyprland.
// Left: column of workspaces, each with horizontal bars for its windows.
// Right: zoomed live preview of the selected window.
// Part of: qs -c desktop
// Control: qs -c desktop ipc call coverflow next|prev|confirm|cancel|state
import QtQuick
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
                g = { id: w.wsId, name: w.wsName, focused: w.wsId === focusedWs, items: [] };
                gs.push(g);
            }
            g.items.push(i);
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
            text: root.sticky
                  ? "🖱  Chế độ chuột — rê để xem · click để chuyển · × hoặc Delete để đóng ứng dụng · Esc để thoát"
                  : "Tab / Shift+Tab để chọn · thả Super để chuyển · Delete để đóng ứng dụng · di chuột để dùng chuột"
            color: root.sticky ? "#66ccff" : "#77ffffff"
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
                height: Math.min(stage.height, col.implicitHeight)
                anchors.verticalCenter: parent.verticalCenter
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

            // ---------- Right: zoomed preview of the selected window ----------
            Item {
                id: previewArea
                x: stage.colW + stage.gap
                width: stage.width - x
                height: stage.height
                opacity: root.progress
                scale: 0.92 + 0.08 * root.progress

                readonly property real infoH: 64

                Rectangle {
                    id: frame
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -previewArea.infoH / 2
                    width: shot.hasContent ? shot.width + 12 : previewArea.width * 0.6
                    height: shot.hasContent ? shot.height + 12 : previewArea.height * 0.5
                    radius: 16
                    color: "#1b1f2a"
                    border.width: 2
                    border.color: root.accent
                    clip: true

                    ScreencopyView {
                        id: shot
                        anchors.centerIn: parent
                        captureSource: root.shown && root.current ? root.current.toplevel : null
                        live: true
                        constraintSize: Qt.size(previewArea.width - 12, previewArea.height - previewArea.infoH - 12)
                    }

                    IconImage {
                        anchors.centerIn: parent
                        visible: !shot.hasContent
                        implicitSize: 128
                        source: root.current ? root.icon(root.current.cls) : ""
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.confirm()
                    }

                    CloseButton {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 14
                        size: 40
                        label: "Đóng ứng dụng"
                        shown: !!root.current
                        onClicked: root.closeWindow(root.currentIndex)
                    }
                }

                // Zoom-in when the selection changes
                SequentialAnimation {
                    id: zoomAnim
                    ParallelAnimation {
                        NumberAnimation { target: frame; property: "scale"; from: 0.94; to: 1; duration: 180; easing.type: Easing.OutCubic }
                        NumberAnimation { target: frame; property: "opacity"; from: 0.4; to: 1; duration: 180 }
                    }
                }
                Connections {
                    target: root
                    function onCurrentIndexChanged() { zoomAnim.restart(); }
                }

                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: frame.bottom
                    anchors.topMargin: 16
                    spacing: 4
                    visible: !!root.current

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 10
                        IconImage {
                            anchors.verticalCenter: parent.verticalCenter
                            implicitSize: 26
                            source: root.current ? root.icon(root.current.cls) : ""
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.current ? root.current.title : ""
                            color: "white"
                            font.pixelSize: 19
                            font.bold: true
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, previewArea.width * 0.8)
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.current
                              ? root.current.cls + "  ·  workspace " + root.current.wsName
                                + "  ·  " + (root.currentIndex + 1) + "/" + root.windows.length
                              : ""
                        color: "#99ffffff"
                        font.pixelSize: 13
                    }
                }
            }
        }
    }
}
