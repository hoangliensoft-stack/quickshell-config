import QtQuick

// "×" close button for the window switcher.
//  idle : small frosted-glass disc, soft grey cross
//  hover: turns into a red gradient pill (expands with `label` if set), glow ring pulses,
//         the cross spins a quarter turn
//  press: squeezes in
Item {
    id: btn
    property real size: 26
    property bool shown: true
    property string label: ""           // e.g. "Đóng" -> the button grows into a pill on hover
    readonly property alias hovered: mouse.containsMouse
    signal clicked()

    readonly property bool hot: mouse.containsMouse
    readonly property real labelW: label !== "" && hot ? labelText.implicitWidth + size * 0.45 : 0

    width: size + labelW
    height: size
    opacity: shown ? 1 : 0
    visible: opacity > 0
    scale: !shown ? 0.6 : mouse.pressed ? 0.88 : hot ? 1.08 : 1

    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 140 } }
    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    // glow ring (only when hovered), breathing slowly
    Rectangle {
        anchors.centerIn: body
        width: body.width + 10; height: body.height + 10
        radius: height / 2
        color: "transparent"
        border.width: 2
        border.color: "#ff6b6b"
        opacity: btn.hot ? 0.55 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        SequentialAnimation on scale {
            running: btn.hot
            loops: Animation.Infinite
            NumberAnimation { from: 0.92; to: 1.06; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1.06; to: 0.92; duration: 700; easing.type: Easing.InOutSine }
        }
    }

    // soft drop shadow
    Rectangle {
        anchors.fill: body
        anchors.topMargin: 2; anchors.bottomMargin: -2
        radius: body.radius
        color: "#000000"
        opacity: 0.35
    }

    Rectangle {
        id: body
        anchors.fill: parent
        radius: height / 2
        border.width: 1
        border.color: btn.hot ? "#ffa8a3" : "#33ffffff"
        gradient: Gradient {
            GradientStop { position: 0; color: btn.hot ? "#ff7a72" : "#4d3a4252" }
            GradientStop { position: 1; color: btn.hot ? (mouse.pressed ? "#b8322b" : "#e0443e") : "#661a1e28" }
        }
        clip: true

        // glassy highlight on the upper half
        Rectangle {
            x: 1; y: 1
            width: parent.width - 2; height: parent.height / 2
            radius: height
            color: "white"
            opacity: btn.hot ? 0.22 : 0.10
        }

        // the cross
        Item {
            id: cross
            width: btn.size; height: btn.size
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            rotation: btn.hot ? 90 : 0
            Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
            Repeater {
                model: [45, -45]
                Rectangle {
                    required property int modelData
                    anchors.centerIn: parent
                    width: btn.size * 0.42
                    height: Math.max(2, Math.round(btn.size * 0.08))
                    radius: height / 2
                    rotation: modelData
                    color: btn.hot ? "white" : "#d8dde8"
                    Behavior on color { ColorAnimation { duration: 140 } }
                }
            }
        }

        Text {
            id: labelText
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: cross.left
            anchors.rightMargin: -btn.size * 0.12
            text: btn.label
            color: "white"
            font.pixelSize: Math.round(btn.size * 0.38)
            font.bold: true
            opacity: btn.labelW > 0 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
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
