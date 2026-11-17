import QtQuick
import Quickshell
import Quickshell.Io

// Screenshot / screen-recording buttons, right of the profile bar in the window switcher.
//   📷 full screen   ⌗ area   ✎ area + edit (swappy)   |   ● record screen   ⌗● record area
// While recording, the two record buttons become a red "■ 00:12  Dừng" button.
// Scripts: ~/.config/hypr/scripts/ScreenShot.sh (JaKooLit), ~/.config/hypr/UserScripts/ScreenRecord.sh
Item {
    id: tools
    required property var bar          // ProfileBar (size factor k, hint line)
    required property var sw           // Switcher

    readonly property real k: bar.k
    readonly property string shot: Quickshell.env("HOME") + "/.config/hypr/scripts/ScreenShot.sh"
    readonly property string rec: Quickshell.env("HOME") + "/.config/hypr/UserScripts/ScreenRecord.sh"
    readonly property string stateFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/screenrecord.json"

    property bool recording: false
    property real recStart: 0
    property real now: Date.now() / 1000
    readonly property string elapsed: {
        const t = Math.max(0, Math.floor(now - recStart));
        const m = Math.floor(t / 60), s = t % 60;
        return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
    }

    width: row.width + 16 * k
    height: 32 * k + 14 * k
    Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    FileView {
        id: state
        path: tools.stateFile
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text());
                tools.recording = !!d.recording;
                tools.recStart = d.start || 0;
            } catch (e) {
                tools.recording = false;
            }
        }
        onLoadFailed: tools.recording = false
    }
    Connections {
        target: tools.sw
        function onOpenedChanged() { if (tools.sw.opened) state.reload(); }
    }
    Timer {
        interval: 1000
        repeat: true
        running: tools.recording && tools.sw.shown
        triggeredOnStart: true
        onTriggered: tools.now = Date.now() / 1000
    }

    // tray: gradient hairline + dark glass body (same as the profile tray)
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        opacity: 0.55
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "#552f8cff" }
            GradientStop { position: 1; color: "#559b5cff" }
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: height / 2
            color: "#e6121624"
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4 * tools.k

        ToolButton {
            kind: "shot"
            tip: "Chụp toàn màn hình  (Super + Print)"
            onClicked: tools.sw.runTool([tools.shot, "--now"])
        }
        ToolButton {
            kind: "area"
            tip: "Chụp một vùng  (Super + Shift + Print)"
            onClicked: tools.sw.runTool([tools.shot, "--area"])
        }
        ToolButton {
            kind: "edit"
            tip: "Chụp một vùng rồi vẽ / ghi chú bằng Swappy  (Super + Shift + S)"
            onClicked: tools.sw.runTool([tools.shot, "--swappy"])
        }

        Rectangle {   // separator
            anchors.verticalCenter: parent.verticalCenter
            width: 1; height: 18 * tools.k
            color: "#33a9b4ff"
        }

        ToolButton {
            kind: "rec"
            visible: !tools.recording
            tip: "Quay màn hình hiện tại, kèm âm thanh  (Super + Shift + R — bấm lại để dừng)"
            onClicked: tools.sw.runTool([tools.rec, "--full"])
        }
        ToolButton {
            kind: "recArea"
            visible: !tools.recording
            tip: "Quay một vùng, kèm âm thanh  (Super + Alt + Shift + R)"
            onClicked: tools.sw.runTool([tools.rec, "--area"])
        }

        // recording: red stop button with the running time
        Item {
            id: stopBtn
            visible: tools.recording
            readonly property bool hot: stopMouse.containsMouse
            anchors.verticalCenter: parent.verticalCenter
            width: stopRow.implicitWidth + 22 * tools.k
            height: 32 * tools.k
            scale: stopMouse.pressed ? 0.94 : 1
            Behavior on scale { NumberAnimation { duration: 100 } }
            onHotChanged: tools.bar.hint = hot ? "Dừng quay và lưu vào ~/Videos/Recordings  (Super + Shift + R)" : ""

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: stopBtn.hot ? "#ff4d6d" : "#d93a55" }
                    GradientStop { position: 1; color: stopBtn.hot ? "#c2410c" : "#9b2c45" }
                }
            }
            Row {
                id: stopRow
                anchors.centerIn: parent
                spacing: 7 * tools.k
                Rectangle {   // pulsing dot
                    anchors.verticalCenter: parent.verticalCenter
                    width: 9 * tools.k; height: width; radius: width / 2
                    color: "white"
                    SequentialAnimation on opacity {
                        running: stopBtn.visible
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 600; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: tools.elapsed
                    color: "white"
                    font.pixelSize: 13 * tools.k
                    font.bold: true
                    font.family: "monospace"
                }
                Rectangle {   // stop square
                    anchors.verticalCenter: parent.verticalCenter
                    width: 9 * tools.k; height: width; radius: 2
                    color: "white"
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Dừng"
                    color: "white"
                    font.pixelSize: 13 * tools.k
                    font.bold: true
                }
            }
            MouseArea {
                id: stopMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Quickshell.execDetached([tools.rec, "--stop"]);
                    tools.recording = false;
                }
            }
        }
    }

    // round icon button; icons are drawn with plain shapes so they always render
    component ToolButton: Item {
        id: tb
        property string kind: ""
        property string tip: ""
        signal clicked()
        readonly property bool hot: tbMouse.containsMouse
        readonly property real s: 32 * tools.k
        readonly property color ink: hot ? "white" : "#c8d0f0"
        readonly property real lw: Math.max(1.5, 1.6 * tools.k)

        anchors.verticalCenter: parent.verticalCenter
        width: s; height: s
        scale: tbMouse.pressed ? 0.9 : hot ? 1.06 : 1
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        onHotChanged: tools.bar.hint = hot ? tip : ""

        Rectangle {   // hover: blue -> purple disc
            anchors.fill: parent
            radius: width / 2
            opacity: tb.hot ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140 } }
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: tools.bar.blue }
                GradientStop { position: 1; color: tools.bar.purple }
            }
        }

        Item {
            id: ico
            anchors.centerIn: parent
            width: 18 * tools.k; height: 18 * tools.k

            // camera (shot)
            Item {
                anchors.fill: parent
                visible: tb.kind === "shot"
                Rectangle {
                    x: ico.width * 0.3; y: ico.height * 0.12
                    width: ico.width * 0.4; height: ico.height * 0.2; radius: 2
                    color: tb.ink
                }
                Rectangle {
                    x: 0; y: ico.height * 0.24
                    width: ico.width; height: ico.height * 0.64; radius: 3.5
                    color: "transparent"; border.width: tb.lw; border.color: tb.ink
                }
                Rectangle {
                    width: ico.width * 0.36; height: width; radius: width / 2
                    x: (ico.width - width) / 2; y: ico.height * 0.56 - height / 2
                    color: "transparent"; border.width: tb.lw; border.color: tb.ink
                }
            }

            // crop corners (area / edit / recArea)
            Repeater {
                model: tb.kind === "area" || tb.kind === "edit" || tb.kind === "recArea" ? 4 : 0
                Item {
                    required property int index
                    readonly property real c: ico.width * 0.34
                    readonly property bool r: index % 2 === 1
                    readonly property bool b: index >= 2
                    x: r ? ico.width - c : 0
                    y: b ? ico.height - c : 0
                    width: c; height: c
                    Rectangle {   // horizontal arm
                        x: 0; y: parent.b ? parent.c - tb.lw : 0
                        width: parent.c; height: tb.lw; radius: tb.lw / 2
                        color: tb.ink
                    }
                    Rectangle {   // vertical arm
                        x: parent.r ? parent.c - tb.lw : 0; y: 0
                        width: tb.lw; height: parent.c; radius: tb.lw / 2
                        color: tb.ink
                    }
                }
            }

            // pen (edit)
            Rectangle {
                visible: tb.kind === "edit"
                anchors.centerIn: parent
                width: ico.width * 0.62; height: tb.lw * 1.6; radius: height / 2
                rotation: -45
                color: tb.ink
            }

            // record ring + dot (rec)
            Rectangle {
                visible: tb.kind === "rec"
                anchors.fill: parent
                radius: width / 2
                color: "transparent"; border.width: tb.lw; border.color: tb.ink
            }
            Rectangle {
                visible: tb.kind === "rec" || tb.kind === "recArea"
                anchors.centerIn: parent
                width: ico.width * (tb.kind === "rec" ? 0.5 : 0.4); height: width; radius: width / 2
                color: tb.hot ? "white" : "#ff4d6d"
            }
        }

        MouseArea {
            id: tbMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tb.clicked()
        }
    }
}
