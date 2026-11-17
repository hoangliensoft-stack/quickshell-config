import QtQuick
import Quickshell

// Left of the profile bar: apply a layout to every workspace at once.
//   ⊞ Tiled tất cả        -> DESKTOP_TILE_ALL()        (no fullscreen / maximize / floating)
//   ⛶ Full screen tất cả  -> DESKTOP_FULLSCREEN_ALL()  (most recent window of each workspace, like SUPER+F)
// The switcher stays open and re-reads the window list, so the change shows right away.
Item {
    id: tray
    required property var bar          // ProfileBar (k, colours, hint, toast)
    required property var sw           // Switcher

    readonly property real k: bar.k

    width: row.width + 16 * k
    height: 32 * k + 14 * k

    // tray: gradient hairline + dark glass body (same as the other trays)
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
        spacing: 6 * tray.k

        LayoutButton {
            kind: "tile"
            label: "Tiled tất cả"
            tip: "Mọi workspace: thoát full screen / maximize, cửa sổ nổi về tiled"
            onClicked: tray.sw.applyLayoutAll("tile")
        }
        LayoutButton {
            kind: "full"
            label: "Full screen tất cả"
            tip: "Mọi workspace: cửa sổ dùng gần nhất phủ kín màn hình (như Super + F)"
            onClicked: tray.sw.applyLayoutAll("full")
        }
    }

    component LayoutButton: Item {
        id: lb
        property string kind: ""
        property string label: ""
        property string tip: ""
        signal clicked()
        readonly property bool hot: lbMouse.containsMouse
        readonly property color ink: hot ? "white" : "#c8d0f0"
        readonly property real lw: Math.max(1.5, 1.6 * tray.k)

        anchors.verticalCenter: parent.verticalCenter
        width: lbRow.implicitWidth + 24 * tray.k
        height: 32 * tray.k
        scale: lbMouse.pressed ? 0.94 : 1
        Behavior on scale { NumberAnimation { duration: 100 } }
        onHotChanged: tray.bar.hint = hot ? tip : ""

        // edge + body, blue -> purple fill on hover
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: lb.hot ? tray.bar.blue : "#406f74ff" }
                GradientStop { position: 1; color: lb.hot ? tray.bar.purple : "#409b5cff" }
            }
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: height / 2
            color: "#171b2a"
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                opacity: lb.hot ? 0.85 : 0.10
                Behavior on opacity { NumberAnimation { duration: 140 } }
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: tray.bar.blue }
                    GradientStop { position: 1; color: tray.bar.purple }
                }
            }
        }

        Row {
            id: lbRow
            anchors.centerIn: parent
            spacing: 8 * tray.k

            Item {
                id: ico
                anchors.verticalCenter: parent.verticalCenter
                width: 15 * tray.k; height: 15 * tray.k

                // 2x2 tiles; they spread apart on hover
                Repeater {
                    model: lb.kind === "tile" ? 4 : 0
                    Rectangle {
                        required property int index
                        readonly property real gap: lb.hot ? 2.6 : 1.8
                        readonly property real s: (ico.width - gap) / 2
                        x: (index % 2) * (s + gap)
                        y: Math.floor(index / 2) * (s + gap)
                        width: s; height: s; radius: 1.5
                        color: lb.hot ? "white" : index === 0 ? tray.bar.blue : index === 3 ? tray.bar.purple : "#6f74ff"
                        Behavior on x { NumberAnimation { duration: 140 } }
                        Behavior on y { NumberAnimation { duration: 140 } }
                    }
                }

                // full screen: solid window + corners pushed outwards on hover
                Rectangle {
                    visible: lb.kind === "full"
                    anchors.centerIn: parent
                    width: ico.width * (lb.hot ? 0.5 : 0.42); height: width; radius: 1.5
                    color: lb.hot ? "white" : "#7b6cff"
                    Behavior on width { NumberAnimation { duration: 140 } }
                }
                Repeater {
                    model: lb.kind === "full" ? 4 : 0
                    Item {
                        required property int index
                        readonly property real c: ico.width * 0.32
                        readonly property bool r: index % 2 === 1
                        readonly property bool b: index >= 2
                        readonly property real out: lb.hot ? 1.5 : 0
                        x: (r ? ico.width - c : 0) + (r ? out : -out)
                        y: (b ? ico.height - c : 0) + (b ? out : -out)
                        width: c; height: c
                        Behavior on x { NumberAnimation { duration: 140 } }
                        Behavior on y { NumberAnimation { duration: 140 } }
                        Rectangle {
                            x: 0; y: parent.b ? parent.c - lb.lw : 0
                            width: parent.c; height: lb.lw; radius: lb.lw / 2
                            color: lb.ink
                        }
                        Rectangle {
                            x: parent.r ? parent.c - lb.lw : 0; y: 0
                            width: lb.lw; height: parent.c; radius: lb.lw / 2
                            color: lb.ink
                        }
                    }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: lb.label
                color: lb.hot ? "white" : "#c8d0f0"
                font.pixelSize: 13 * tray.k
            }
        }

        MouseArea {
            id: lbMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: lb.clicked()
        }
    }
}
