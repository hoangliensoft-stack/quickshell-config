// Workspace / window switcher for Hyprland.
// Left: column of workspaces, each with horizontal bars for its windows.
// Right: zoomed live preview of the selected window.
// Run: qs -c coverflow
// Control: qs -c coverflow ipc call coverflow next|prev|confirm|cancel|state
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets

ShellRoot {
    id: root

    property bool opened: false
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
        opened = true;
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

    function close() {
        sticky = false;
        opened = false;
        loading = false;
        windows = [];
        groups = [];
    }

    Timer {
        id: focusTimer
        property string address: ""
        interval: 40
        onTriggered: {
            Hyprland.dispatch("focuswindow address:" + address);
            Hyprland.dispatch("alterzorder top,address:" + address);
            refocusTimer.restart();
        }
    }

    // With follow_mouse = 1, switching workspace makes Hyprland focus the window under
    // the cursor; focus the chosen window again once the workspace switch has settled.
    Timer {
        id: refocusTimer
        interval: 150
        onTriggered: Hyprland.dispatch("focuswindow address:" + focusTimer.address)
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
        }
        function swipeDown(): void { root.close(); }
        function cancel(): void { root.close(); }
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

        visible: root.opened
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
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "coverflow"

        Rectangle {
            anchors.fill: parent
            color: "#e00b0d14"

            MouseArea {
                anchors.fill: parent
                onClicked: root.close()
                onWheel: wheel => {
                    root.sticky = true;
                    root.step(wheel.angleDelta.y > 0 ? -1 : 1);
                }
            }
        }

        // Hint at the bottom
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 18
            visible: root.opened
            text: root.sticky
                  ? "🖱  Chế độ chuột — rê để xem · click để chuyển · Esc hoặc click ra ngoài để đóng"
                  : "Tab / Shift+Tab để chọn · thả Super để chuyển · di chuột để dùng chuột"
            color: root.sticky ? "#66ccff" : "#77ffffff"
            font.pixelSize: 13
        }

        Item {
            id: stage
            anchors.fill: parent
            anchors.margins: Math.round(Math.min(panel.width, panel.height) * 0.06)
            focus: root.opened

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

                                        width: wsCol.width
                                        height: 46
                                        radius: 10
                                        color: isCurrent ? "#2a66ccff" : barMouse.containsMouse ? "#1affffff" : "#0dffffff"
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
                                            anchors.rightMargin: 12
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
                        captureSource: root.opened && root.current ? root.current.toplevel : null
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
