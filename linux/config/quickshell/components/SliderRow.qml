import QtQuick
import QtQuick.Layouts

Column {
    id: sliderRow
    width: parent.width
    spacing: 8

    property real value: 0
    property color accent: "white"
    property string label: ""
    signal commit(real pct)

    function setValue(pct) {
        sliderRow.value = Math.max(0, Math.min(100, pct));
        sliderRow.commit(sliderRow.value);
    }

    RowLayout {
        width: parent.width
        Text { text: sliderRow.label; color: "#aaa"; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1.5 }
        Item { Layout.fillWidth: true }
        Text { text: Math.round(sliderRow.value) + "%"; color: "white"; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10 }
    }

    Row {
        width: parent.width
        spacing: 6

        Rectangle {
            id: track
            width: parent.width - 54
            height: 26
            radius: 8
            color: "#000000"
            border.color: "#333"

            Rectangle {
                width: parent.width * Math.min(sliderRow.value, 100) / 100
                height: parent.height
                radius: 8
                color: sliderRow.accent
            }

            Rectangle {
                x: Math.max(0, Math.min(parent.width - this.width, parent.width * sliderRow.value / 100 - this.width / 2))
                y: (parent.height - height) / 2
                width: 12
                height: 12
                radius: 6
                color: sliderRow.accent
                Behavior on x { SmoothedAnimation { velocity: 600 } }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                property bool dragging: false
                onPressed: { dragging = true; sliderRow.setValue(mouse.x / width * 100) }
                onPositionChanged: { if (dragging) sliderRow.setValue(mouse.x / width * 100) }
                onReleased: dragging = false
                onWheel: wheel => { sliderRow.setValue(sliderRow.value + (wheel.angleDelta.y > 0 ? 5 : -5)) }
            }
        }

        TextInput {
            id: input
            width: 48
            height: 26
            text: Math.round(sliderRow.value).toString()
            color: "white"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            selectByMouse: true
            inputMethodHints: Qt.ImhDigitsOnly
            onAccepted: { sliderRow.setValue(parseFloat(text) || 0); focus = false; }
            Rectangle { anchors.fill: parent; z: -1; radius: 7; color: "#000000"; border.color: "#333" }
        }
    }
}