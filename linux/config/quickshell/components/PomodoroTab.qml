import QtQuick
import "../config"
import "../services"

Rectangle {
    id: pomodoroTab
    width: parent.width
    height: 364
    radius: 12
    color: Theme.bgItem
    opacity: visible ? 1 : 0
    Behavior on opacity {
        NumberAnimation {
            duration: Motion.durationFade
            easing.type: Motion.easingOutCubic
        }
    }

    component StepperControl: Row {
        id: stepper
        property int value: 0
        property int step: 5
        property int min: 1
        property int max: 90
        property string key: ""
        property string suffix: " min"
        spacing: 6

        Rectangle {
            width: 26
            height: 26
            radius: 8
            anchors.verticalCenter: parent.verticalCenter
            color: minusArea.containsMouse ? Theme.bgHoverSoft : "#000000"
            border.color: Theme.border
            border.width: 1
            Text {
                anchors.centerIn: parent
                text: "\uf068"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }
            MouseArea {
                id: minusArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    const v = Math.max(stepper.min, stepper.value - stepper.step);
                    if (v !== stepper.value)
                        PomodoroService.setConfig(stepper.key, v);
                }
            }
        }

        Text {
            width: 54
            anchors.verticalCenter: parent.verticalCenter
            text: stepper.value + stepper.suffix
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.pixelLarge
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
            Text {
                anchors.centerIn: parent
                text: "\uf067"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }
            MouseArea {
                id: plusArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    const v = Math.min(stepper.max, stepper.value + stepper.step);
                    if (v !== stepper.value)
                        PomodoroService.setConfig(stepper.key, v);
                }
            }
        }
    }

    Column {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        Text {
            width: parent.width
            text: PomodoroService.fmt(PomodoroService.remaining)
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: 36
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            width: parent.width
            text: {
                const s = PomodoroService.state;
                if (s === "work")
                    return "Trabajo — ciclo " + (PomodoroService.cycle + 1);
                if (s === "break")
                    return "Descanso";
                if (s === "paused_work" || s === "paused_break")
                    return "Pausado";
                return "Inactivo";
            }
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.pixelTitle
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            width: parent.width
            visible: PomodoroService.active || PomodoroService.cycle > 0
            text: "Bloques completados: " + PomodoroService.cycle
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.pixelNormal
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            width: parent.width
            visible: PomodoroService.eyesOn && PomodoroService.active && PomodoroService.eyesIn >= 0
            text: "\uf06e  Ojos: mira lejos en " + PomodoroService.fmt(PomodoroService.eyesIn)
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.pixelNormal
            horizontalAlignment: Text.AlignHCenter
        }

        Row {
            width: parent.width
            spacing: 8

            Rectangle {
                width: (parent.width - 16) / 3
                height: 32
                radius: 8
                color: mainArea.containsMouse ? Theme.fgFaint : Theme.fg
                Text {
                    anchors.centerIn: parent
                    text: PomodoroService.paused ? "\uf04c Pausar" : (PomodoroService.active ? "\uf04c Pausar" : "\uf04b Iniciar")
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
                        if (PomodoroService.paused)
                            PomodoroService.resume();
                        else if (PomodoroService.active)
                            PomodoroService.pause();
                        else
                            PomodoroService.start();
                    }
                }
            }

            Rectangle {
                width: (parent.width - 16) / 3
                height: 32
                radius: 8
                color: skipArea.containsMouse ? Theme.bgHoverSoft : "#000000"
                border.color: Theme.border
                border.width: 1
                opacity: PomodoroService.active ? 1 : 0.6
                Text {
                    anchors.centerIn: parent
                    text: "\uf051 Saltar"
                    color: Theme.fg
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
                width: (parent.width - 16) / 3
                height: 32
                radius: 8
                color: stopArea.containsMouse ? Theme.danger : "#000000"
                border.color: Theme.border
                border.width: 1
                opacity: PomodoroService.active ? 1 : 0.6
                Text {
                    anchors.centerIn: parent
                    text: "\uf04d Detener"
                    color: stopArea.containsMouse ? Theme.bg : Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.pixelNormal
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

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.border
        }

        Grid {
            columns: 2
            width: parent.width
            rowSpacing: 10
            columnSpacing: 10

            // Columna 1
            Row {
                width: (parent.width - 10) / 2
                spacing: 8
                Text {
                    width: 70
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Trabajo"
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.pixelNormal
                }
                StepperControl {
                    anchors.verticalCenter: parent.verticalCenter
                    value: PomodoroService.workMin
                    step: 5
                    min: 5
                    max: 90
                    key: "work_min"
                }
            }

            // Columna 2
            Row {
                width: (parent.width - 10) / 2
                spacing: 8
                Text {
                    width: 70
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Descanso"
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.pixelNormal
                }
                StepperControl {
                    anchors.verticalCenter: parent.verticalCenter
                    value: PomodoroService.breakMin
                    step: 1
                    min: 1
                    max: 30
                    key: "break_min"
                }
            }

            // Columna 1
            Row {
                width: (parent.width - 10) / 2
                spacing: 8
                Text {
                    width: 70
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Sesiones"
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.pixelNormal
                }
                StepperControl {
                    anchors.verticalCenter: parent.verticalCenter
                    value: PomodoroService.targetSessions || 4
                    step: 1
                    min: 1
                    max: 12
                    key: "target_sessions"
                    suffix: ""
                }
            }

            // Columna 2
            Row {
                width: (parent.width - 10) / 2
                spacing: 8
                Text {
                    width: 70
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Ojos"
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.pixelNormal
                }
                Row {
                    spacing: 6
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        width: 40
                        height: 26
                        radius: 8
                        color: PomodoroService.eyesOn ? Theme.fg : "#000000"
                        border.color: Theme.border
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: PomodoroService.eyesOn ? "ON" : "OFF"
                            color: PomodoroService.eyesOn ? Theme.fgOnWhite : Theme.fgDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.pixelNormal
                            font.bold: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: PomodoroService.setConfig("eyes_on", PomodoroService.eyesOn ? "0" : "1")
                        }
                    }
                    StepperControl {
                        visible: PomodoroService.eyesOn
                        value: PomodoroService.eyesMin
                        step: 5
                        min: 5
                        max: 60
                        key: "eyes_min"
                    }
                }
            }
        }
    }
}
