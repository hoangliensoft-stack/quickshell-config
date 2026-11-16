import QtQuick

// Round "×" button used by the window switcher to close a window
Rectangle {
    id: btn
    property real size: 26
    property bool shown: true
    readonly property alias hovered: mouse.containsMouse
    signal clicked()

    width: size; height: size; radius: size / 2
    color: mouse.pressed ? "#c0392b" : mouse.containsMouse ? "#e74c3c" : "#59000000"
    border.width: 1
    border.color: mouse.containsMouse ? "#ff8a80" : "#40ffffff"
    opacity: shown ? 1 : 0
    visible: opacity > 0
    scale: mouse.pressed ? 0.9 : 1
    Behavior on opacity { NumberAnimation { duration: 120 } }
    Behavior on color { ColorAnimation { duration: 100 } }
    Behavior on scale { NumberAnimation { duration: 80 } }

    // two crossed bars (sharper than a font glyph at any size)
    Repeater {
        model: [45, -45]
        Rectangle {
            required property int modelData
            anchors.centerIn: parent
            width: btn.size * 0.46; height: Math.max(2, btn.size * 0.075); radius: height / 2
            rotation: modelData
            color: "white"
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
