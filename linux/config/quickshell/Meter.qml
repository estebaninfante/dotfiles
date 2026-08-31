import QtQuick

Rectangle {
    height: 6
    radius: 3
    color: "#333"

    property double mv: 0
    property color mColor: "white"

    Rectangle {
        height: parent.height
        width: parent.width * parent.mv
        radius: parent.radius
        color: parent.mColor
    }
}
