import QtQuick

// Background of a window bar in the switcher: sea-blue -> purple gradient.
//   normal  : faint static gradient
//   hot     : a bit stronger
//   active  : gradient border + brighter fill + soft glow + accent strip, all slowly flowing
//   closing : red tint
Item {
    id: g
    property bool active: false
    property bool hot: false
    property bool closing: false
    property real radius: 10

    readonly property color blue: "#2f8cff"
    readonly property color purple: "#9b5cff"

    // 0..1, loops; only animated on the selected bar
    property real phase: 0
    NumberAnimation on phase {
        from: 0; to: 1
        duration: 6000
        loops: Animation.Infinite
        running: g.active && g.visible
    }

    // colour at position t of the blue -> purple -> blue cycle
    function mix(t, a) {
        const f = 0.5 - 0.5 * Math.cos(2 * Math.PI * t);
        return Qt.rgba(blue.r + (purple.r - blue.r) * f,
                       blue.g + (purple.g - blue.g) * f,
                       blue.b + (purple.b - blue.b) * f,
                       a === undefined ? 1 : a);
    }

    property real fillA: closing ? 0 : active ? 0.34 : hot ? 0.15 : 0.065
    property real edgeA: active ? 1 : 0
    Behavior on fillA { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on edgeA { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    readonly property real inset: 1.5 * edgeA

    // soft glow around the selected bar
    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        radius: g.radius + 4
        opacity: 0.32 * g.edgeA
        visible: opacity > 0
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: g.mix(g.phase, 0.55) }
            GradientStop { position: 1; color: g.mix(g.phase + 0.5, 0.55) }
        }
    }

    // gradient border (shows around the inset base below)
    Rectangle {
        anchors.fill: parent
        radius: g.radius
        opacity: g.edgeA
        visible: opacity > 0
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0;   color: g.mix(g.phase) }
            GradientStop { position: 0.5; color: g.mix(g.phase + 0.33) }
            GradientStop { position: 1;   color: g.mix(g.phase + 0.66) }
        }
    }

    // opaque base, so the border colour does not bleed through the translucent fill
    Rectangle {
        anchors.fill: parent
        anchors.margins: g.inset
        radius: g.radius - g.inset
        color: "#161a28"
        opacity: g.edgeA
        visible: opacity > 0
    }

    // gradient fill
    Rectangle {
        anchors.fill: parent
        anchors.margins: g.inset
        radius: g.radius - g.inset
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0;   color: g.mix(g.phase, g.fillA) }
            GradientStop { position: 0.6; color: g.mix(g.phase + 0.3, g.fillA * 0.75) }
            GradientStop { position: 1;   color: g.mix(g.phase + 0.5, g.fillA * 0.45) }
        }
    }

    // top sheen on the selected bar
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: g.inset + 1
        height: parent.height * 0.55
        radius: g.radius - g.inset
        opacity: g.edgeA
        visible: opacity > 0
        gradient: Gradient {
            GradientStop { position: 0; color: "#16ffffff" }
            GradientStop { position: 1; color: "#00ffffff" }
        }
    }

    // accent strip
    Rectangle {
        width: 4; radius: 2
        height: parent.height - 16
        anchors.left: parent.left
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        opacity: g.edgeA
        visible: opacity > 0
        gradient: Gradient {
            GradientStop { position: 0; color: g.mix(g.phase) }
            GradientStop { position: 1; color: g.mix(g.phase + 0.5) }
        }
    }

    // closing: red tint
    Rectangle {
        anchors.fill: parent
        radius: g.radius
        color: "#55e0443e"
        opacity: g.closing ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }
}
