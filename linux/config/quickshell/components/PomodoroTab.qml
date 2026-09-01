import QtQuick
import "../config"
import "../services"

// Pestaña POMODORO del centro: timer + control de fases + configuración
// de duraciones y recordatorio de ojos (persistido en pomodoro.conf).
Rectangle {
    id: pomodoroTab
    width: parent.width
    height: 350
    radius: 12
    color: Theme.bgItem
    opacity: visible ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Motion.durationFade; easing.type: Motion.easingOutCubic } }

    component StepperRow: Row {
        id: stepRow
        property string label: ""
        property int value: 0
        property int step: 5
        property int min: 1
        property int max: 90
        property string key: ""
        spacing: 10

        Text {
            width: 80
            anchors.verticalCenter: parent.verticalCenter
            text: stepRow.label
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.pixelNormal
        }

        Rectangle {
            width: 26
            height: 26
            radius: 8
            anchors.verticalCenter: parent.verticalCenter
            color: minusArea.containsMouse ? Theme.bgHoverSoft : "#000000"
            border.color: Theme.border
            border.width: 1
            Behavior on color { ColorAnimation { duration: 120; easing.type: Motion.easingOutCubic } }
            Text { anchors.centerIn: parent; text: "\uf068"; color: Theme.fgDim; font.family: Theme.fontFamily; font.pixelSize: 10 }
            MouseArea {
                id: minusArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    const v = Math.max(stepRow.min, stepRow.value - stepRow.step);
                    if (v !== stepRow.value) PomodoroService.setConfig(stepRow.key, v);
                }
            }
        }

        Text {
            width: 60
            anchors.verticalCenter: parent.verticalCenter
            text: stepRow.value + " min"
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.pixelNormal
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
        }

        Rectangle {
            width: 26
            height: 26
            radius: 8
            anchors.verticalCenter: parent.verticalCenter
            color: plusArea.containsMouse ? Theme.bgHoverSoft : "#000000"
            border.color: Theme.border
            border.width: 1
            Behavior on color { ColorAnimation { duration: 120; easing.type: Motion.easingOutCubic } }
            Text { anchors.centerIn: parent; text: "\uf067"; color: Theme.fgDim; font.family: Theme.fontFamily; font.pixelSize: 10 }
            MouseArea {
                id: plusArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    const v = Math.min(stepRow.max, stepRow.value + stepRow.step);
                    if (v !== stepRow.value) PomodoroService.setConfig(stepRow.key, v);
                }
            }
        }
    }

    Column {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 9

        Text {
            width: parent.width
            text: PomodoroService.fmt(PomodoroService.remaining)
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: 46
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            width: parent.width
            text: {
                const s = PomodoroService.state;
                if (s === "work") return "Trabajo — ciclo " + (PomodoroService.cycle + 1);
                if (s === "break") return "Descanso";
                if (s === "paused_work" || s === "paused_break") return "Pausado";
                return "Inactivo";
            }
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.pixelLarge
            horizontalAlignment: Text.AlignHCenter
            Behavior on color { ColorAnimation { duration: 150; easing.type: Motion.easingOutCubic } }
        }

        Text {
            width: parent.width
            visible: PomodoroService.eyesOn && PomodoroService.active && PomodoroService.eyesIn >= 0
            text: "\uf06e  Ojos: mira lejos en " + PomodoroService.fmt(PomodoroService.eyesIn)
            color: Theme.fgFaint
            font.family: Theme.fontFamily
            font.pixelSize: Theme.pixelNormal
            horizontalAlignment: Text.AlignHCenter
        }

        Row {
            width: parent.width
            spacing: 10

            Rectangle {
                width: (parent.width - 20) / 3
                height: 34
                radius: 10
                color: mainArea.containsMouse ? Theme.fgFaint : Theme.fg
                Behavior on color { ColorAnimation { duration: 120; easing.type: Motion.easingOutCubic } }
                Text {
                    anchors.centerIn: parent
                    text: PomodoroService.paused ? "\uf04c  Pausar" : (PomodoroService.active ? "\uf04c  Pausar" : "\uf04b  Iniciar")
                    color: Theme.fgOnWhite
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.pixelNormal
                    font.bold: true
                }
                MouseArea {
                    id: mainArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (PomodoroService.paused) PomodoroService.resume();
                        else if (PomodoroService.active) PomodoroService.pause();
                        else PomodoroService.start();
                    }
                }
            }

            Rectangle {
                width: (parent.width - 20) / 3
                height: 34
                radius: 10
                color: skipArea.containsMouse ? Theme.bgHoverSoft : "#000000"
                border.color: Theme.border
                border.width: 1
                opacity: PomodoroService.active ? 1 : 0.4
                Behavior on color { ColorAnimation { duration: 120; easing.type: Motion.easingOutCubic } }
                Behavior on opacity { NumberAnimation { duration: 150; easing.type: Motion.easingOutCubic } }
                Text {
                    anchors.centerIn: parent
                    text: "\uf051  Saltar"
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.pixelNormal
                }
                MouseArea {
                    id: skipArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: PomodoroService.active
                    onClicked: PomodoroService.skip()
                }
            }

            Rectangle {
                width: (parent.width - 20) / 3
                height: 34
                radius: 10
                color: stopArea.containsMouse ? Theme.danger : "#000000"
                border.color: Theme.border
                border.width: 1
                opacity: PomodoroService.active ? 1 : 0.4
                Behavior on color { ColorAnimation { duration: 120; easing.type: Motion.easingOutCubic } }
                Behavior on opacity { NumberAnimation { duration: 150; easing.type: Motion.easingOutCubic } }
                Text {
                    anchors.centerIn: parent
                    text: "\uf04d  Detener"
                    color: stopArea.containsMouse ? Theme.bg : Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.pixelNormal
                    Behavior on color { ColorAnimation { duration: 120; easing.type: Motion.easingOutCubic } }
                }
                MouseArea {
                    id: stopArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: PomodoroService.active
                    onClicked: PomodoroService.stop()
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.border }

        StepperRow {
            width: parent.width
            label: "Trabajo"
            value: PomodoroService.workMin
            step: 5
            min: 5
            max: 90
            key: "work_min"
        }

        StepperRow {
            width: parent.width
            label: "Descanso"
            value: PomodoroService.breakMin
            step: 1
            min: 1
            max: 30
            key: "break_min"
        }

        Row {
            width: parent.width
            spacing: 10

            Text {
                width: 80
                anchors.verticalCenter: parent.verticalCenter
                text: "Ojos"
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.pixelNormal
            }

            Rectangle {
                width: 44
                height: 24
                radius: 8
                anchors.verticalCenter: parent.verticalCenter
                color: "#000000"
                border.color: PomodoroService.eyesOn ? Theme.fg : Theme.border
                border.width: 1
                Behavior on border.color { ColorAnimation { duration: 150; easing.type: Motion.easingOutCubic } }
                Text {
                    anchors.centerIn: parent
                    text: PomodoroService.eyesOn ? "ON" : "OFF"
                    color: PomodoroService.eyesOn ? Theme.fg : Theme.fgDimmer
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.pixelSmall
                    font.bold: true
                    Behavior on color { ColorAnimation { duration: 150; easing.type: Motion.easingOutCubic } }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: PomodoroService.setConfig("eyes_on", PomodoroService.eyesOn ? "0" : "1")
                }
            }

            StepperRow {
                anchors.verticalCenter: parent.verticalCenter
                value: PomodoroService.eyesMin
                step: 5
                min: 5
                max: 60
                key: "eyes_min"
                label: ""
            }
        }
    }
}
