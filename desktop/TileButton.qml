import QtQuick

// "Tiled" pill on a workspace header in the window switcher: opens the workspace with every
// window tiled. `attention` = the workspace has fullscreen / floating windows (accent tint).
Item {
    id: btn
    property bool attention: false
    signal clicked()

    readonly property bool hot: mouse.containsMouse
    readonly property color accent: "#66ccff"

    width: row.implicitWidth + 18
    height: 24
    scale: mouse.pressed ? 0.92 : hot ? 1.05 : 1
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        border.width: 1
        border.color: btn.hot ? btn.accent : btn.attention ? "#8066ccff" : "#26ffffff"
        gradient: Gradient {
            GradientStop { position: 0; color: btn.hot ? "#8a66ccff" : btn.attention ? "#3366ccff" : "#26ffffff" }
            GradientStop { position: 1; color: btn.hot ? "#4d2f8fd0" : btn.attention ? "#1a66ccff" : "#0dffffff" }
        }
        Behavior on border.color { ColorAnimation { duration: 140 } }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6

        // 2x2 tile grid icon; the tiles spread apart on hover
        Item {
            id: icon
            anchors.verticalCenter: parent.verticalCenter
            width: 12; height: 12
            property real gap: btn.hot ? 2.5 : 1.5
            Behavior on gap { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
            Repeater {
                model: 4
                Rectangle {
                    required property int index
                    readonly property real s: (icon.width - icon.gap) / 2
                    x: (index % 2) * (s + icon.gap)
                    y: Math.floor(index / 2) * (s + icon.gap)
                    width: s; height: s; radius: 1.5
                    color: btn.hot ? "white" : btn.attention ? btn.accent : "#c8d0de"
                }
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Tiled"
            color: btn.hot ? "white" : btn.attention ? btn.accent : "#c8d0de"
            font.pixelSize: 12
            font.bold: true
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
