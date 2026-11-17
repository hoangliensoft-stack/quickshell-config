import QtQuick

// "Tiled" pill on a workspace header in the window switcher: opens the workspace with every
// window tiled. `attention` = the workspace has fullscreen / floating windows (blue -> purple tint).
Item {
    id: btn
    property bool attention: false
    signal clicked()

    readonly property bool hot: mouse.containsMouse
    readonly property color blue: "#2f8cff"
    readonly property color purple: "#9b5cff"
    readonly property color soft: "#a9b4ff"    // text tint between the two

    width: row.implicitWidth + 18
    height: 24
    scale: mouse.pressed ? 0.92 : hot ? 1.05 : 1
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    // edge: grey, or a blue -> purple gradient when it needs attention / is hovered
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: btn.hot || btn.attention ? btn.blue : "#26ffffff" }
            GradientStop { position: 1; color: btn.hot || btn.attention ? btn.purple : "#26ffffff" }
        }
        opacity: btn.hot ? 1 : btn.attention ? 0.75 : 1
        Behavior on opacity { NumberAnimation { duration: 140 } }
    }
    // body (inset 1px so the edge shows as a border)
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: height / 2
        color: "#171b28"
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            opacity: btn.hot ? 0.85 : btn.attention ? 0.22 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: btn.blue }
                GradientStop { position: 1; color: btn.purple }
            }
        }
        Rectangle {   // neutral fill when idle
            anchors.fill: parent
            radius: height / 2
            color: "#14ffffff"
            opacity: btn.hot || btn.attention ? 0 : 1
        }
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
                    // tiles run blue -> purple when the workspace needs attention
                    color: btn.hot ? "white" : btn.attention ? (index === 0 ? btn.blue : index === 3 ? btn.purple : "#6f74ff") : "#c8d0de"
                }
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Tiled"
            color: btn.hot ? "white" : btn.attention ? btn.soft : "#c8d0de"
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
