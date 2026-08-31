import QtQuick
import "../config"
import "../services"

Rectangle {
    id: gameModeFade
    anchors.fill: parent
    visible: GameModeService.gameModeActive
    color: "transparent"
    opacity: (GameModeService.gameShown && !GameModeService.gameClosing) ? 1 : 0
    // Bloquear el input de lo que haya detrás mientras el overlay está arriba.
    MouseArea {
        anchors.fill: parent
        enabled: GameModeService.gameModeActive
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
    }

    Text {
        anchors.top: parent.top
        anchors.topMargin: 56
        anchors.horizontalCenter: parent.horizontalCenter
        text: "\uf11b  MODO JUEGOS"
        color: "white"
        font.family: Theme.fontFamily
        font.pixelSize: 22
        font.bold: true
        font.letterSpacing: 8
    }

    Rectangle {
        id: gameCard
        width: 440
        height: gameConfirmCol.implicitHeight + 44
        visible: !GameModeService.gameLaunching
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 14
        radius: 16
        color: "#000000"
        border.color: "#333"
        border.width: 1

        Column {
            id: gameConfirmCol
            anchors.fill: parent
            anchors.margins: 22
            spacing: 8

            Text {
                text: "CERRAR APLICACIONES"
                color: "#aaa"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 3
            }

            Text {
                width: parent.width
                text: "Se cierran las demás apps para liberar recursos. Discord, WhatsApp y Spotify se quedan abiertas."
                color: "white"
                font.family: Theme.fontFamily
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            Rectangle {
                width: parent.width
                height: 42
                radius: 8
                color: gameSiArea.containsMouse ? "#eba0ac" : "#000000"
                Text {
                    anchors.centerIn: parent
                    text: "SÍ, CERRAR Y JUGAR"
                    color: gameSiArea.containsMouse ? "#000000" : "white"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.bold: true
                }
                MouseArea {
                    id: gameSiArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: GameModeService.gameConfirmClose()
                }
            }

            Rectangle {
                width: parent.width
                height: 42
                radius: 8
                color: gameNoArea.containsMouse ? "white" : "#141414"
                Text {
                    anchors.centerIn: parent
                    text: "NO, SOLO ABRIR"
                    color: gameNoArea.containsMouse ? "#000000" : "#aaa"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.bold: true
                }
                MouseArea {
                    id: gameNoArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: GameModeService.gameConfirmNoClose()
                }
            }

            Rectangle {
                width: parent.width
                height: 42
                radius: 8
                color: gameCancelArea.containsMouse ? "#222" : "#000000"
                Text {
                    anchors.centerIn: parent
                    text: "CANCELAR"
                    color: "#aaa"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.bold: true
                }
                MouseArea {
                    id: gameCancelArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: GameModeService.gameCancel()
                }
            }
        }
    }

    Item {
        anchors.fill: parent
        visible: GameModeService.gameLaunching

        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 20
            spacing: 18

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "\uf11b"
                color: "white"
                font.family: Theme.fontFamily
                font.pixelSize: 64
                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.2; duration: 420; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 420; easing.type: Easing.InOutSine }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "CARGANDO JUEGOS…"
                color: "#aaa"
                font.family: Theme.fontFamily
                font.pixelSize: 20
                font.bold: true
                font.letterSpacing: 6
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Steam y Cartridges están abriéndose"
                color: "#aaa"
                font.family: Theme.fontFamily
                font.pixelSize: 13
            }
        }
    }

    Text {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 44
        anchors.horizontalCenter: parent.horizontalCenter
        text: "El botón PS del volante también abre y cierra este modo"
        color: "#888"
        font.family: Theme.fontFamily
        font.pixelSize: 11
    }
}