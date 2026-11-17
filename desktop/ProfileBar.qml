import QtQuick

// Profile bar at the top of the window switcher.
//   click a profile      -> open the apps it is missing, each on its saved workspace
//   ⟳ (on hover)         -> overwrite it with the current layout
//   × (on hover)         -> delete (click twice)
//   right click          -> rename
//   "+ Lưu bố cục"       -> save the current layout as a new profile
Item {
    id: bar
    required property var sw          // the Switcher (root)
    property int renaming: -1
    property int confirmDelete: -1
    property string hint: ""          // shown by the switcher's hint line while hovering
    readonly property real k: 1.35    // size of the whole bar (1 = compact)

    height: tray.height + 30          // tray + room for the toast underneath

    Timer {
        id: deleteTimer
        interval: 2500
        onTriggered: bar.confirmDelete = -1
    }

    // glass tray behind the row
    Rectangle {
        id: tray
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: row.width + 16 * bar.k
        height: row.height + 14 * bar.k
        radius: height / 2
        color: "#0fffffff"
        border.width: 1
        border.color: "#1fffffff"
        Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }

    Row {
        id: row
        anchors.centerIn: tray
        spacing: 8 * bar.k

        // label
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7 * bar.k
            leftPadding: 8 * bar.k
            rightPadding: 4 * bar.k
            // stacked-layers icon
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: 16 * bar.k; height: 14 * bar.k
                Repeater {
                    model: 3
                    Rectangle {
                        required property int index
                        x: 0; y: index * 5 * bar.k
                        width: 16 * bar.k; height: 4 * bar.k; radius: height / 2
                        color: "#8fa0bd"
                        opacity: 1 - index * 0.25
                    }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Profile"
                color: "#8fa0bd"
                font.pixelSize: 13 * bar.k
                font.bold: true
                font.letterSpacing: 0.5
            }
        }

        Repeater {
            model: bar.sw.profiles

            delegate: Item {
                id: pill
                required property var modelData
                required property int index
                readonly property var st: bar.sw.profileStatus(modelData)
                readonly property bool complete: st.total > 0 && st.missing === 0
                readonly property bool hot: pillMouse.containsMouse || saveBtn.hot || delBtn.hot
                readonly property bool deleting: bar.confirmDelete === index
                readonly property bool editing: bar.renaming === index

                width: content.implicitWidth + 26 * bar.k
                height: 32 * bar.k
                anchors.verticalCenter: parent.verticalCenter
                scale: pillMouse.pressed ? 0.95 : 1
                Behavior on scale { NumberAnimation { duration: 100 } }
                Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                onHotChanged: if (hot) bar.hint = "Click: mở các app còn thiếu và xếp vào đúng workspace  ·  ⟳ lưu đè bố cục hiện tại  ·  × xóa  ·  chuột phải: đổi tên"
                              else if (bar.hint !== "") bar.hint = ""

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: pill.deleting ? "#4de0443e" : pill.hot ? "#2effffff" : "#14ffffff"
                    border.width: 1
                    border.color: pill.deleting ? "#ff8a80" : pill.hot ? "#66ccff" : "#24ffffff"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on border.color { ColorAnimation { duration: 120 } }
                }

                MouseArea {
                    id: pillMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    enabled: !pill.editing
                    onClicked: m => {
                        if (m.button === Qt.RightButton) {
                            bar.renaming = pill.index;
                            nameEdit.text = pill.modelData.name;
                            nameEdit.selectAll();
                            nameEdit.forceActiveFocus();
                        } else if (pill.deleting) {
                            bar.confirmDelete = -1;
                        } else {
                            bar.sw.applyProfile(pill.index);
                        }
                    }
                }

                Row {
                    id: content
                    anchors.left: parent.left
                    anchors.leftMargin: 13 * bar.k
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 7 * bar.k

                    // status dot: green = every app is open, amber = some are missing
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 7 * bar.k; height: width; radius: width / 2
                        color: pill.complete ? "#5fd38d" : "#e6b450"
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !pill.editing
                        text: pill.modelData.name
                        color: pill.deleting ? "#ffd0cc" : "white"
                        font.pixelSize: 13 * bar.k
                        font.bold: true
                    }
                    TextInput {
                        id: nameEdit
                        anchors.verticalCenter: parent.verticalCenter
                        visible: pill.editing
                        width: Math.max(80 * bar.k, contentWidth + 4)
                        color: "white"
                        selectionColor: "#66ccff"
                        selectedTextColor: "#0b0d14"
                        font.pixelSize: 13 * bar.k
                        font.bold: true
                        maximumLength: 24
                        Keys.onReturnPressed: finish(true)
                        Keys.onEnterPressed: finish(true)
                        Keys.onEscapePressed: finish(false)
                        onActiveFocusChanged: if (!activeFocus && pill.editing) finish(true)
                        function finish(ok) {
                            if (bar.renaming !== pill.index)
                                return;
                            bar.renaming = -1;
                            if (ok && text.trim() !== "")
                                bar.sw.renameProfile(pill.index, text.trim());
                            bar.sw.focusStage();
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !pill.editing
                        text: pill.st.total - pill.st.missing + "/" + pill.st.total
                        color: "#8fa0bd"
                        font.pixelSize: 11 * bar.k
                    }

                    // hover actions: always take their space (only fade), so nothing in the bar
                    // shifts under the pointer when the hover starts or ends
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2 * bar.k
                        visible: !pill.editing
                        enabled: pill.hot || pill.deleting
                        opacity: enabled ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                        PillAction {
                            id: saveBtn
                            glyph: "⟳"
                            enabled: !pill.deleting
                            opacity: pill.deleting ? 0.25 : 1
                            onClicked: bar.sw.saveProfile(pill.index)
                        }
                        // second click confirms: the × grows to the right into "Xóa?", so a
                        // click on the same spot still hits it
                        PillAction {
                            id: delBtn
                            glyph: pill.deleting ? "Xóa?" : "×"
                            armed: pill.deleting
                            danger: true
                            onClicked: {
                                if (pill.deleting) {
                                    bar.confirmDelete = -1;
                                    bar.sw.deleteProfile(pill.index);
                                } else {
                                    bar.confirmDelete = pill.index;
                                    deleteTimer.restart();
                                }
                            }
                        }
                    }
                }
            }
        }

        // + save current layout
        Item {
            id: addPill
            readonly property bool hot: addMouse.containsMouse
            anchors.verticalCenter: parent.verticalCenter
            width: addRow.implicitWidth + 26 * bar.k
            height: 32 * bar.k
            scale: addMouse.pressed ? 0.95 : 1
            Behavior on scale { NumberAnimation { duration: 100 } }
            onHotChanged: if (hot) bar.hint = "Lưu các app đang mở và workspace của chúng thành một profile mới"
                          else if (bar.hint !== "") bar.hint = ""

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: addPill.hot ? "#2266ccff" : "transparent"
                border.width: 1
                border.color: addPill.hot ? "#66ccff" : "#33ffffff"
                Behavior on color { ColorAnimation { duration: 120 } }
            }
            Row {
                id: addRow
                anchors.centerIn: parent
                spacing: 6 * bar.k
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "+"
                    color: addPill.hot ? "#66ccff" : "#aab4c8"
                    font.pixelSize: 17 * bar.k
                    font.bold: true
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: bar.sw.profiles.length ? "Lưu bố cục hiện tại" : "Lưu bố cục hiện tại thành Profile 1"
                    color: addPill.hot ? "white" : "#aab4c8"
                    font.pixelSize: 13 * bar.k
                }
            }
            MouseArea {
                id: addMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: bar.sw.saveProfile(-1)
            }
        }
    }

    // toast ("Đã lưu ...")
    Text {
        id: toast
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: tray.bottom
        anchors.topMargin: 8
        color: "#5fd38d"
        font.pixelSize: 13
        opacity: 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Timer {
            id: toastTimer
            interval: 2600
            onTriggered: toast.opacity = 0
        }
    }

    function showToast(msg) {
        toast.text = msg;
        toast.opacity = 1;
        toastTimer.restart();
    }

    component PillAction: Rectangle {
        id: act
        property string glyph: ""
        property bool danger: false
        property bool armed: false
        readonly property bool hot: am.containsMouse
        signal clicked()
        width: armed ? actText.implicitWidth + 14 * bar.k : 20 * bar.k
        height: 20 * bar.k; radius: height / 2
        color: armed || hot ? (danger ? "#e0443e" : "#4066ccff") : "transparent"
        Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 100 } }
        Text {
            id: actText
            anchors.centerIn: parent
            anchors.verticalCenterOffset: act.glyph.length > 1 ? 0 : -1
            text: act.glyph
            color: act.hot || act.armed ? "white" : "#aab4c8"
            font.pixelSize: (act.glyph === "×" ? 16 : act.glyph.length > 1 ? 11 : 13) * bar.k
            font.bold: true
        }
        MouseArea {
            id: am
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: act.clicked()
        }
    }
}
