import QtQuick

Rectangle {
    height: 6
    radius: 3
    color: "#252530"

    property double mv: 0
    property color mColor: "#cba6f7"

    Rectangle {
        height: parent.height
        width: parent.width * parent.mv
        radius: parent.radius
        color: parent.mColor

        Behavior on width {
            NumberAnimation {
                duration: 700
                easing.type: Easing.OutQuint
            }
        }
    }
}