import QtQuick

Rectangle {
    id: deviceRow
    width: parent.width
    height: rowHeight
    radius: 6
    color: area.containsMouse ? "#1d1d26" : selected ? "#1d1d26" : "#141414"

    property string name: ""
    property bool selected: false
    property real rowHeight: 22
    signal clicked()

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: (selected ? "●  " : "○  ") + name
        color: selected ? "white" : "white"
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 9
        elide: Text.ElideRight
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: deviceRow.clicked()
    }
}