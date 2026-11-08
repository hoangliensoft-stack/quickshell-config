// App launcher for Hyprland (Quickshell).
// Run: qs -c launcher            Toggle: qs -c launcher ipc call launcher toggle
//
// - Categories (sidebar): Favorites, Recent, All + freedesktop main categories
// - Fuzzy search over name / generic name / keywords / comment (frequently used apps rank higher)
// - Calculator: type an expression (12*7+3, =sqrt(2)*pi) -> Enter copies the result
// - Command: type ">cmd" -> Enter runs it, Ctrl+Enter runs it in a terminal
// - Ctrl+F or right-click: add/remove favorite
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets

ShellRoot {
    id: root

    property bool opened: false
    property string query: ""
    property string category: "all"
    property int selected: 0
    property var apps: []      // all apps (plain objects)
    property var items: []     // apps currently shown in the grid
    property var favorites: [] // [desktop id]
    property var usage: ({})   // { id: { count, last } }

    readonly property string terminal: "kitty"
    readonly property color accent: "#66ccff"
    readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/quickshell-launcher"

    readonly property var categoryDefs: [
        { key: "fav", label: "Yêu thích", icon: "starred" },
        { key: "recent", label: "Gần đây", icon: "document-open-recent" },
        { key: "all", label: "Tất cả", icon: "view-app-grid" },
        { key: "Development", label: "Lập trình", icon: "applications-development" },
        { key: "Network", label: "Internet", icon: "applications-internet" },
        { key: "Office", label: "Văn phòng", icon: "applications-office" },
        { key: "Graphics", label: "Đồ họa", icon: "applications-graphics" },
        { key: "AudioVideo", label: "Đa phương tiện", icon: "applications-multimedia" },
        { key: "Game", label: "Trò chơi", icon: "applications-games" },
        { key: "Education", label: "Giáo dục", icon: "applications-education" },
        { key: "Utility", label: "Tiện ích", icon: "applications-utilities" },
        { key: "Settings", label: "Cài đặt", icon: "preferences-system" },
        { key: "System", label: "Hệ thống", icon: "applications-system" },
        { key: "other", label: "Khác", icon: "applications-other" }
    ]
    // Only show categories that contain apps (fav/recent/all always shown)
    readonly property var categories: categoryDefs.filter(c =>
        c.key === "fav" || c.key === "recent" || c.key === "all" || apps.some(a => a.primary === c.key))

    // ---------- modes ----------
    readonly property bool commandMode: query.startsWith(">")
    readonly property string commandText: commandMode ? query.slice(1).trim() : ""
    readonly property var calcResult: commandMode ? null : calc(query)
    readonly property bool calcMode: calcResult !== null
    readonly property var current: items[selected] || null

    // ---------- helpers ----------
    function iconSource(icon) {
        if (!icon)
            return Quickshell.iconPath("application-x-executable");
        if (icon.startsWith("/"))
            return "file://" + icon;
        return Quickshell.iconPath(icon, "application-x-executable");
    }

    function primaryCategory(cats) {
        const has = k => cats.indexOf(k) >= 0;
        if (has("Development")) return "Development";
        if (has("Network") || has("WebBrowser")) return "Network";
        if (has("Office")) return "Office";
        if (has("Graphics")) return "Graphics";
        if (has("AudioVideo") || has("Audio") || has("Video")) return "AudioVideo";
        if (has("Game")) return "Game";
        if (has("Education") || has("Science")) return "Education";
        if (has("Settings") || has("DesktopSettings") || has("HardwareSettings")) return "Settings";
        if (has("System") || has("TerminalEmulator")) return "System";
        if (has("Utility")) return "Utility";
        return "other";
    }

    function loadApps() {
        const seen = {};
        const list = [];
        const src = DesktopEntries.applications.values;
        for (let i = 0; i < src.length; i++) {
            const e = src[i];
            if (!e || e.noDisplay || seen[e.id])
                continue;
            seen[e.id] = true;
            const cats = Array.from(e.categories || []);
            list.push({
                id: e.id,
                name: e.name || e.id,
                generic: e.genericName || "",
                comment: e.comment || "",
                icon: e.icon || "",
                keywords: Array.from(e.keywords || []).join(" "),
                cats: cats,
                primary: primaryCategory(cats),
                terminal: e.runInTerminal,
                command: Array.from(e.command || []),
                workdir: e.workingDirectory || "",
                entry: e
            });
        }
        list.sort((a, b) => a.name.localeCompare(b.name));
        apps = list;
    }

    // Safe calculator: digits, operators, parentheses and whitelisted Math functions
    function calc(q) {
        let s = q.trim();
        const forced = s.startsWith("=");
        if (forced)
            s = s.slice(1).trim();
        if (!s)
            return null;
        if (!/^[0-9a-z\s+\-*/().,%^]+$/i.test(s))
            return null;
        if (!forced && !(/\d/.test(s) && /[+\-*/%^]/.test(s.replace(/^-/, ""))))
            return null;
        const fns = ["sqrt", "cbrt", "abs", "sin", "cos", "tan", "asin", "acos", "atan", "log",
                     "log2", "log10", "exp", "floor", "ceil", "round", "min", "max", "pow"];
        let bad = false;
        let expr = s.replace(/,/g, ".").replace(/\^/g, "**").replace(/[a-z]+[0-9]*/gi, w => {
            const l = w.toLowerCase();
            if (l === "pi") return "Math.PI";
            if (l === "e") return "Math.E";
            if (l === "ln") return "Math.log";
            if (fns.indexOf(l) >= 0) return "Math." + l;
            bad = true;
            return w;
        });
        if (bad)
            return null;
        try {
            const v = Function('"use strict"; return (' + expr + ");")();
            if (typeof v !== "number" || !isFinite(v))
                return null;
            return Math.round(v * 1e10) / 1e10;
        } catch (e) {
            return null;
        }
    }

    function score(app, q) {
        const name = app.name.toLowerCase();
        let s = 0;
        if (name === q) s = 120;
        else if (name.startsWith(q)) s = 100;
        else if (name.split(/[\s\-_.]+/).some(w => w.startsWith(q))) s = 85;
        else if (name.indexOf(q) >= 0) s = 70;
        else if (app.generic.toLowerCase().indexOf(q) >= 0) s = 50;
        else if (app.keywords.toLowerCase().indexOf(q) >= 0) s = 45;
        else if (app.id.toLowerCase().indexOf(q) >= 0) s = 40;
        else if (app.comment.toLowerCase().indexOf(q) >= 0) s = 30;
        else {
            // fuzzy subsequence on the name
            let i = 0, gaps = 0, last = -1;
            for (let k = 0; k < name.length && i < q.length; k++) {
                if (name[k] === q[i]) {
                    if (last >= 0) gaps += k - last - 1;
                    last = k;
                    i++;
                }
            }
            if (i === q.length)
                s = Math.max(5, 25 - gaps);
        }
        if (s > 0) {
            const u = usage[app.id];
            if (u) s += Math.min(u.count, 20);
        }
        return s;
    }

    function refresh() {
        let list;
        const q = query.trim().toLowerCase();
        // Compute modes from the query directly: the commandMode/calcMode bindings
        // may not have re-evaluated yet when onQueryChanged runs.
        if (query.startsWith(">") || calc(query) !== null) {
            list = [];
        } else if (q) {
            list = apps.map(a => ({ a: a, s: score(a, q) }))
                       .filter(x => x.s > 0)
                       .sort((x, y) => y.s - x.s || x.a.name.localeCompare(y.a.name))
                       .map(x => x.a);
        } else if (category === "fav") {
            list = favorites.map(id => apps.find(a => a.id === id)).filter(a => !!a);
        } else if (category === "recent") {
            list = apps.filter(a => usage[a.id])
                       .sort((x, y) => usage[y.id].last - usage[x.id].last)
                       .slice(0, 30);
        } else if (category === "all") {
            list = apps;
        } else {
            list = apps.filter(a => a.primary === category);
        }
        items = list;
        selected = 0;
    }

    function countFor(key) {
        if (key === "fav") return favorites.length;
        if (key === "recent") return Math.min(30, Object.keys(usage).length);
        if (key === "all") return apps.length;
        return apps.filter(a => a.primary === key).length;
    }

    function isFavorite(id) {
        return favorites.indexOf(id) >= 0;
    }

    function toggleFavorite(app) {
        if (!app)
            return;
        const f = favorites.slice();
        const i = f.indexOf(app.id);
        if (i >= 0) f.splice(i, 1);
        else f.push(app.id);
        favorites = f;
        save();
        if (category === "fav" && !query) {
            const keep = selected;
            refresh();
            selected = Math.min(keep, Math.max(0, items.length - 1));
        }
    }

    function launch(app, inTerminal) {
        if (!app)
            return;
        const u = Object.assign({}, usage);
        const old = u[app.id] || { count: 0, last: 0 };
        u[app.id] = { count: old.count + 1, last: Date.now() };
        usage = u;
        save();
        close();
        if (app.terminal || inTerminal) {
            Quickshell.execDetached([terminal, "-e"].concat(app.command));
        } else {
            app.entry.execute();
        }
    }

    function runCommand(inTerminal) {
        const cmd = commandText;
        if (!cmd)
            return;
        close();
        if (inTerminal)
            Quickshell.execDetached([terminal, "--hold", "sh", "-c", cmd]);
        else
            Quickshell.execDetached(["sh", "-c", cmd]);
    }

    function copyCalc() {
        if (calcResult === null)
            return;
        Quickshell.execDetached(["wl-copy", String(calcResult)]);
        close();
    }

    function activate(inTerminal) {
        if (commandMode) runCommand(inTerminal);
        else if (calcMode) copyCalc();
        else launch(current, inTerminal);
    }

    function move(d) {
        if (items.length === 0)
            return;
        selected = Math.max(0, Math.min(items.length - 1, selected + d));
    }

    function cycleCategory(d) {
        const keys = categories.map(c => c.key);
        let i = keys.indexOf(category);
        i = ((i + d) % keys.length + keys.length) % keys.length;
        setCategory(keys[i]);
    }

    function setCategory(key) {
        category = key;
        if (query)
            query = "";
        refresh();
    }

    function open() {
        loadApps();
        query = "";
        category = favorites.length ? "fav" : (Object.keys(usage).length ? "recent" : "all");
        introTimer.restart(); // before refresh(): new tiles must see intro = true
        refresh();
        shown = true;
        opened = true;
        progressAnim.to = 1;
        progressAnim.duration = 260 * slow;
        progressAnim.easing.type = Easing.OutCubic;
        progressAnim.restart();
    }

    function close() {
        if (!opened)
            return;
        opened = false;
        progressAnim.to = 0;
        progressAnim.duration = 170 * slow;
        progressAnim.easing.type = Easing.InCubic;
        progressAnim.restart();
    }

    // ---------- animation state ----------
    property bool shown: false     // window mapped (stays true during the close animation)
    property real progress: 0      // 0 = hidden, 1 = fully open
    property bool intro: false     // true right after opening: tiles fade in one by one
    property real slow: 1          // debug: slow-motion factor (ipc call launcher slowmo 5)

    NumberAnimation {
        id: progressAnim
        target: root
        property: "progress"
        onFinished: if (!root.opened) root.shown = false
    }
    Timer {
        id: introTimer
        interval: 600 * root.slow
        onRunningChanged: if (running) root.intro = true
        onTriggered: root.intro = false
    }

    function save() {
        stateFile.setText(JSON.stringify({ favorites: favorites, usage: usage }, null, 1));
    }

    onQueryChanged: refresh()

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", stateDir])

    FileView {
        id: stateFile
        path: root.stateDir + "/state.json"
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.favorites = d.favorites || [];
                root.usage = d.usage || {};
            } catch (e) {
                console.warn("launcher: bad state file", e);
            }
        }
    }

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            if (root.opened) {
                root.loadApps();
                root.refresh();
            }
        }
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void { root.opened ? root.close() : root.open(); }
        function open(): void { if (!root.opened) root.open(); }
        function hide(): void { root.close(); }
        function slowmo(f: real): void { root.slow = f; }
        function search(text: string): void {
            if (!root.opened) root.open();
            root.query = text;
        }
        function state(): string {
            return JSON.stringify({ opened: root.opened, category: root.category, query: root.query,
                                    count: root.items.length, selected: root.current ? root.current.name : null,
                                    calc: root.calcResult, apps: root.apps.length,
                                    favorites: root.favorites.length });
        }
    }

    PanelWindow {
        id: win

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
        // Give the keyboard back as soon as closing starts
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "launcher"

        onVisibleChanged: if (visible) Qt.callLater(() => search.forceActiveFocus())

        // Dim backdrop (fades with the panel), click outside to close
        Rectangle {
            anchors.fill: parent
            color: "#b30b0d14"
            opacity: root.progress
            MouseArea {
                anchors.fill: parent
                enabled: root.opened
                onClicked: root.close()
            }
        }

        Rectangle {
            id: panel
            width: Math.min(1060, win.width * 0.78)
            height: Math.min(700, win.height * 0.82)
            anchors.centerIn: parent
            radius: 22
            color: "#f2141821"
            border.width: 1
            border.color: "#26ffffff"

            // open / close animation: fade + zoom + slide up
            opacity: root.progress
            scale: 0.9 + 0.1 * root.progress
            transform: Translate { y: 36 * (1 - root.progress) }
            enabled: root.opened

            MouseArea { anchors.fill: parent } // swallow clicks so the backdrop doesn't close

            // ---------- search bar ----------
            Rectangle {
                id: searchBox
                x: 20; y: 20
                width: parent.width - 40
                height: 56
                radius: 14
                color: "#1d222e"
                border.width: search.activeFocus ? 2 : 1
                border.color: search.activeFocus ? root.accent : "#22ffffff"

                IconImage {
                    id: searchIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    implicitSize: 22
                    source: Quickshell.iconPath(root.commandMode ? "utilities-terminal"
                                                : root.calcMode ? "accessories-calculator"
                                                : "system-search", "system-search")
                }

                TextInput {
                    id: search
                    anchors.left: searchIcon.right
                    anchors.leftMargin: 14
                    anchors.right: modeChip.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    color: "white"
                    font.pixelSize: 20
                    selectionColor: root.accent
                    selectedTextColor: "#0b0d14"
                    clip: true
                    text: root.query
                    onTextEdited: root.query = text

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: !search.text
                        text: "Tìm ứng dụng…   (=  phép tính · >  chạy lệnh)"
                        color: "#667085"
                        font.pixelSize: 20
                    }

                    Keys.onPressed: e => {
                        const ctrl = e.modifiers & Qt.ControlModifier;
                        switch (e.key) {
                        case Qt.Key_Escape:
                            if (root.query) root.query = ""; else root.close();
                            break;
                        case Qt.Key_Return:
                        case Qt.Key_Enter:
                            root.activate(ctrl);
                            break;
                        case Qt.Key_Right: root.move(1); break;
                        case Qt.Key_Left: root.move(-1); break;
                        case Qt.Key_Down: root.move(grid.cols); break;
                        case Qt.Key_Up: root.move(-grid.cols); break;
                        case Qt.Key_PageDown: root.move(grid.cols * 3); break;
                        case Qt.Key_PageUp: root.move(-grid.cols * 3); break;
                        case Qt.Key_Tab: root.cycleCategory(1); break;
                        case Qt.Key_Backtab: root.cycleCategory(-1); break;
                        case Qt.Key_F:
                            if (!ctrl) return;
                            root.toggleFavorite(root.current);
                            break;
                        default:
                            return;
                        }
                        e.accepted = true;
                    }
                }

                Rectangle {
                    id: modeChip
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.commandMode || root.calcMode || root.query.length > 0
                    width: visible ? chipText.implicitWidth + 20 : 0
                    height: 30
                    radius: 15
                    color: "#2266ccff"
                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        text: root.commandMode ? "Lệnh" : root.calcMode ? "Máy tính" : root.items.length + " kết quả"
                        color: root.accent
                        font.pixelSize: 13
                        font.bold: true
                    }
                }
            }

            // ---------- sidebar ----------
            Column {
                id: sidebar
                x: 20
                y: searchBox.y + searchBox.height + 16
                width: 210
                spacing: 4

                Repeater {
                    model: root.categories
                    delegate: Rectangle {
                        id: cat
                        required property var modelData
                        readonly property bool active: !root.query && root.category === modelData.key

                        width: sidebar.width
                        height: 40
                        radius: 10
                        color: active ? "#2a66ccff" : catMouse.containsMouse ? "#14ffffff" : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Rectangle {
                            visible: cat.active
                            width: 3; radius: 2
                            height: 20
                            anchors.left: parent.left
                            anchors.leftMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            color: root.accent
                        }
                        IconImage {
                            id: catIcon
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            implicitSize: 20
                            source: Quickshell.iconPath(cat.modelData.icon, "applications-other")
                        }
                        Text {
                            anchors.left: catIcon.right
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: cat.modelData.label
                            color: cat.active ? "white" : "#c4cbd8"
                            font.pixelSize: 14
                            font.bold: cat.active
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.countFor(cat.modelData.key)
                            color: "#667085"
                            font.pixelSize: 12
                        }
                        MouseArea {
                            id: catMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.setCategory(cat.modelData.key);
                                search.forceActiveFocus();
                            }
                        }
                    }
                }
            }

            // ---------- main area ----------
            Item {
                id: main
                x: sidebar.x + sidebar.width + 16
                y: sidebar.y
                width: panel.width - x - 20
                height: panel.height - y - footer.height - 28

                // Calculator card
                Rectangle {
                    anchors.fill: parent
                    visible: root.calcMode
                    radius: 16
                    color: "#1a1f2b"
                    Column {
                        anchors.centerIn: parent
                        spacing: 10
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.query.replace(/^=/, "").trim()
                            color: "#8a93a6"
                            font.pixelSize: 22
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "= " + (root.calcResult !== null ? root.calcResult.toLocaleString(Qt.locale("en_US"), "f", -128).replace(/\.?0+$/, "") : "")
                            color: "white"
                            font.pixelSize: 52
                            font.bold: true
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Enter để copy kết quả"
                            color: root.accent
                            font.pixelSize: 14
                        }
                    }
                }

                // Command card
                Rectangle {
                    anchors.fill: parent
                    visible: root.commandMode
                    radius: 16
                    color: "#1a1f2b"
                    Column {
                        anchors.centerIn: parent
                        spacing: 12
                        IconImage {
                            anchors.horizontalCenter: parent.horizontalCenter
                            implicitSize: 64
                            source: Quickshell.iconPath("utilities-terminal", "application-x-executable")
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.min(implicitWidth, main.width - 60)
                            elide: Text.ElideRight
                            text: root.commandText ? "$ " + root.commandText : "Gõ lệnh sau dấu >"
                            color: "white"
                            font.family: "monospace"
                            font.pixelSize: 22
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Enter: chạy   ·   Ctrl+Enter: chạy trong terminal"
                            color: root.accent
                            font.pixelSize: 14
                        }
                    }
                }

                // Empty state
                Text {
                    anchors.centerIn: parent
                    visible: !root.commandMode && !root.calcMode && root.items.length === 0
                    horizontalAlignment: Text.AlignHCenter
                    text: root.query ? "Không tìm thấy ứng dụng nào"
                        : root.category === "fav" ? "Chưa có ứng dụng yêu thích\nChuột phải hoặc Ctrl+F trên một ứng dụng để ghim"
                        : root.category === "recent" ? "Chưa mở ứng dụng nào" : ""
                    color: "#667085"
                    font.pixelSize: 15
                    lineHeight: 1.4
                }

                // App grid
                GridView {
                    id: grid
                    anchors.fill: parent
                    visible: !root.commandMode && !root.calcMode
                    clip: true
                    model: root.items
                    readonly property int cols: Math.max(1, Math.floor(width / 132))
                    cellWidth: Math.floor(width / cols)
                    cellHeight: 128
                    currentIndex: root.selected
                    boundsBehavior: Flickable.StopAtBounds
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)

                    // Selection frame that glides between tiles
                    highlightFollowsCurrentItem: true
                    highlightMoveDuration: 140
                    highlight: Rectangle {
                        width: grid.cellWidth
                        height: grid.cellHeight
                        color: "transparent"
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 5
                            radius: 14
                            color: "#2a66ccff"
                            border.width: 2
                            border.color: root.accent
                        }
                    }

                    // Crossfade + small slide whenever the list changes (category / search)
                    property real swap: 1
                    NumberAnimation on swap { id: swapAnim; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic; running: false }
                    Connections {
                        target: root
                        function onItemsChanged() { if (root.opened && !root.intro) swapAnim.restart(); }
                    }
                    opacity: 0.35 + 0.65 * swap
                    transform: Translate { y: 10 * (1 - grid.swap) }

                    delegate: Item {
                        id: tile
                        required property var modelData
                        required property int index
                        readonly property bool isCurrent: index === root.selected

                        width: grid.cellWidth
                        height: grid.cellHeight

                        // Intro: tiles pop in one after another right after opening
                        property real appear: root.intro ? 0 : 1
                        opacity: appear
                        scale: 0.85 + 0.15 * appear
                        Component.onCompleted: if (root.intro) introAnim.start()
                        SequentialAnimation {
                            id: introAnim
                            PauseAnimation { duration: Math.min(tile.index, 30) * 14 * root.slow }
                            NumberAnimation { target: tile; property: "appear"; to: 1; duration: 220 * root.slow; easing.type: Easing.OutBack }
                        }

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 5
                            radius: 14
                            color: !tile.isCurrent && tileMouse.containsMouse ? "#12ffffff" : "transparent"
                            Behavior on color { ColorAnimation { duration: 100 } }

                            IconImage {
                                id: appIcon
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 14
                                implicitSize: 52
                                source: root.iconSource(tile.modelData.icon)
                                scale: tile.isCurrent ? 1.08 : 1
                                Behavior on scale { NumberAnimation { duration: 120 } }
                            }
                            Text {
                                anchors.top: appIcon.bottom
                                anchors.topMargin: 10
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width - 14
                                horizontalAlignment: Text.AlignHCenter
                                text: tile.modelData.name
                                color: tile.isCurrent ? "white" : "#d0d6e2"
                                font.pixelSize: 13
                                font.bold: tile.isCurrent
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                            Text {
                                visible: root.isFavorite(tile.modelData.id)
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 8
                                text: "★"
                                color: "#ffcc66"
                                font.pixelSize: 14
                            }
                        }

                        MouseArea {
                            id: tileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) {
                                    root.selected = tile.index;
                                    root.toggleFavorite(tile.modelData);
                                } else {
                                    root.launch(tile.modelData, false);
                                }
                            }
                        }
                    }
                }
            }

            // ---------- footer: details of the selected app + hints ----------
            Rectangle {
                id: footer
                x: 20
                width: parent.width - 40
                height: 58
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 18
                radius: 14
                color: "#1a1f2b"

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12
                    width: parent.width - hints.width - 48
                    visible: !!root.current && !root.commandMode && !root.calcMode

                    IconImage {
                        anchors.verticalCenter: parent.verticalCenter
                        implicitSize: 32
                        source: root.current ? root.iconSource(root.current.icon) : ""
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 44
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: root.current
                                  ? root.current.name + (root.isFavorite(root.current.id) ? "  ★" : "")
                                    + (root.current.terminal ? "  ·  terminal" : "")
                                  : ""
                            color: "white"
                            font.pixelSize: 15
                            font.bold: true
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: root.current ? (root.current.comment || root.current.generic || root.current.id) : ""
                            color: "#8a93a6"
                            font.pixelSize: 12
                        }
                    }
                }

                Text {
                    id: hints
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: "↵ mở   ⇥ danh mục   Ctrl+F ghim   Esc đóng"
                    color: "#667085"
                    font.pixelSize: 12
                }
            }
        }
    }
}
