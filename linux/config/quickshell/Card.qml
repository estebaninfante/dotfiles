import QtQuick
import QtQuick.Layouts

Rectangle {
    id: cCard
    width: parent.width
    height: 70
    radius: 12
    color: "#16161c"
    border.color: "#26262e"
    border.width: 1

    property string cIcon: ""
    property color cAccent: "#cba6f7"
    property string cTitle: ""
    property string cBig: "--"
    property string cSub: ""
    property double cVal: 0
    property bool cardOn: false
    property double dDel: 0

    opacity: 0
    scale: 0.96
    transform: Translate { id: cT }

    Item {
        id: cInner
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 12
        anchors.bottomMargin: 8

        RowLayout {
            id: cTop
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 10

            Text {
                text: cCard.cIcon
                color: cCard.cAccent
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 20
                Layout.preferredWidth: 28
            }

            Column {
                spacing: 2

                Text {
                    text: cCard.cTitle
                    color: "#9a9aa7"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    font.letterSpacing: 1.5
                }

                Text {
                    text: cCard.cBig
                    color: "white"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 18
                }
            }

            Item {
                Layout.fillWidth: true
            }

            Text {
                text: cCard.cSub
                color: "#8a8a99"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 10
                horizontalAlignment: Text.AlignRight
                Layout.fillWidth: true
                Layout.maximumWidth: 140
                elide: Text.ElideRight
            }
        }

        Meter {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: cTop.bottom
            anchors.topMargin: 10
            mv: cCard.cVal / 100
            mColor: cCard.cAccent
        }
    }

    states: [
        State {
            name: "on"
            when: cCard.cardOn
            PropertyChanges {
                target: cCard
                opacity: 1
                scale: 1
            }
            PropertyChanges {
                target: cT
                y: 0
            }
        },
        State {
            name: "off"
            PropertyChanges {
                target: cCard
                opacity: 0.15
                scale: 0.96
            }
            PropertyChanges {
                target: cT
                y: 14
            }
        }
    ]

    transitions: Transition {
        to: "*"
        reversible: true
        SequentialAnimation {
            PauseAnimation {
                duration: cCard.dDel
            }
            ParallelAnimation {
                NumberAnimation {
                    property: "opacity"
                    duration: 160
                    easing.type: Easing.OutQuad
                }
                NumberAnimation {
                    property: "scale"
                    duration: 300
                    easing.type: Easing.OutBack
                }
                NumberAnimation {
                    target: cT
                    property: "y"
                    duration: 300
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}
