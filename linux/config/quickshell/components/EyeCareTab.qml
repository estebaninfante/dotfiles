import QtQuick
import "../config"
import "../services"

Rectangle {
    id: eyeCareTab
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
        property string suffix: ""
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
                    if (v !== stepper.value) {
                        if (stepper.key === "interval_min") EyeCareService.setIntervalMin(v)
                        else if (stepper.key === "break_sec") EyeCareService.setBreakSec(v)
                    }
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
                    if (v !== stepper.value) {
                        if (stepper.key === "interval_min") EyeCareService.setIntervalMin(v)
                        else if (stepper.key === "break_sec") EyeCareService.setBreakSec(v)
                    }
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
            text: EyeCareService.onBreak
                  ? EyeCareService.remaining + "s"
                  : EyeCareService.fmt(EyeCareService.remaining)
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: 36
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            width: parent.width
            text: EyeCareService.onBreak
                  ? "Descansando la vista"
                  : "Próximo descanso"
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.pixelTitle
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            width: parent.width
            text: "Cada " + EyeCareService.intervalMin + " min — " + EyeCareService.breakSec + "s de descanso"
            color: Theme.fgDimmer
            font.family: Theme.fontFamily
            font.pixelSize: Theme.pixelNormal
            horizontalAlignment: Text.AlignHCenter
        }

        Rectangle { width: parent.width; height: 1; color: Theme.border }

        // Config
        Grid {
            columns: 2
            width: parent.width
            rowSpacing: 10
            columnSpacing: 10

            Row {
                width: (parent.width - 10) / 2
                spacing: 8
                Text {
                    width: 70
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Intervalo"
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.pixelNormal
                }
                StepperControl {
                    anchors.verticalCenter: parent.verticalCenter
                    value: EyeCareService.intervalMin
                    step: 5
                    min: 5
                    max: 60
                    key: "interval_min"
                    suffix: " min"
                }
            }

            Row {
                width: (parent.width - 10) / 2
                spacing: 8
                Text {
                    width: 70
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Duración"
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.pixelNormal
                }
                StepperControl {
                    anchors.verticalCenter: parent.verticalCenter
                    value: EyeCareService.breakSec
                    step: 5
                    min: 5
                    max: 60
                    key: "break_sec"
                    suffix: "s"
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.border }

        // Info
        Column {
            width: parent.width
            spacing: 4

            Text {
                width: parent.width
                text: "Regla 20-20-20: cada 20 minutos,"
                color: Theme.fgDimmer
                font.family: Theme.fontFamily
                font.pixelSize: Theme.pixelSmall
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                width: parent.width
                text: "mira algo a 20 pies (6m) por 20 segundos."
                color: Theme.fgDimmer
                font.family: Theme.fontFamily
                font.pixelSize: Theme.pixelSmall
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                width: parent.width
                visible: EyeCareService.onBreak
                text: "Clic en la pantalla para saltar"
                color: Theme.fgFaint
                font.family: Theme.fontFamily
                font.pixelSize: Theme.pixelSmall
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
