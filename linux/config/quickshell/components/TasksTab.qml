import QtQuick
import "../config"
import "../services"

// Pestaña TAREAS del centro: añade, completa y borra tareas de la nota
// diaria de Obsidian (~/alicia/Dia/YYYY-MM-DD.md) vía TasksService.
Rectangle {
    id: tasksTab
    width: parent.width
    height: 350
    radius: 12
    color: Theme.bgItem
    opacity: visible ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Motion.durationFade; easing.type: Motion.easingOutCubic } }

    Text {
        anchors.centerIn: parent
        visible: !TasksService.vaultOk
        text: "Vault ~/alicia no encontrado"
        color: Theme.fgDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.pixelMedium
        wrapMode: Text.WordWrap
    }

    Column {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10
        visible: TasksService.vaultOk

        Rectangle {
            width: parent.width
            height: 34
            radius: 10
            color: "#000000"
            border.color: taskInput.activeFocus ? Theme.fgFaint : Theme.border
            border.width: 1
            Behavior on border.color { ColorAnimation { duration: 120; easing.type: Motion.easingOutCubic } }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                visible: taskInput.text.length === 0 && !taskInput.activeFocus
                text: "Añadir tarea…"
                color: Theme.fgDimmer
                font.family: Theme.fontFamily
                font.pixelSize: Theme.pixelLarge
                font.italic: true
            }

            TextInput {
                id: taskInput
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 40
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.pixelLarge
                clip: true
                focus: true
                Keys.onReturnPressed: { TasksService.add(taskInput.text); taskInput.text = ""; }
                Keys.onEnterPressed: { TasksService.add(taskInput.text); taskInput.text = ""; }
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf067"
                color: addArea.containsMouse ? Theme.fg : Theme.fgFaint
                font.family: Theme.fontFamily
                font.pixelSize: 15
                Behavior on color { ColorAnimation { duration: 120; easing.type: Motion.easingOutCubic } }
            }

            MouseArea {
                id: addArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    TasksService.add(taskInput.text);
                    taskInput.text = "";
                    taskInput.focus = true;
                }
            }
        }

        ListView {
            id: taskList
            width: parent.width
            height: parent.height - 44
            clip: true
            spacing: 5
            model: TasksService.tasks

            delegate: Rectangle {
                width: taskList.width
                height: 30
                radius: 8
                color: rowArea.containsMouse ? Theme.bgHover : "#000000"
                Behavior on color { ColorAnimation { duration: 120; easing.type: Motion.easingOutCubic } }

                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    Rectangle {
                        width: 16
                        height: 16
                        radius: 4
                        anchors.verticalCenter: parent.verticalCenter
                        color: modelData.done ? Theme.fg : "transparent"
                        border.color: modelData.done ? Theme.fg : (rowArea.containsMouse ? Theme.fgFaint : Theme.border)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120; easing.type: Motion.easingOutCubic } }
                        Behavior on border.color { ColorAnimation { duration: 120; easing.type: Motion.easingOutCubic } }

                        Text {
                            anchors.centerIn: parent
                            visible: modelData.done
                            text: "\uf00c"
                            color: Theme.bg
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -7
                            cursorShape: Qt.PointingHandCursor
                            onClicked: TasksService.toggle(modelData.idx)
                        }
                    }

                    Text {
                        width: parent.width - 16 - 10 - 22 - 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.text
                        color: modelData.done ? Theme.fgFaint : (modelData.prio !== "" ? Theme.fg : Theme.fgDim)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.pixelLarge
                        font.strikeout: modelData.done
                        elide: Text.ElideRight
                        Behavior on color { ColorAnimation { duration: 150; easing.type: Motion.easingOutCubic } }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: rowArea.containsMouse ? 1 : 0
                        text: "\uf00d"
                        color: delArea.containsMouse ? Theme.danger : Theme.fgDimmer
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.pixelLarge
                        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Motion.easingOutCubic } }
                        Behavior on color { ColorAnimation { duration: 120; easing.type: Motion.easingOutCubic } }

                        MouseArea {
                            id: delArea
                            anchors.fill: parent
                            anchors.margins: -7
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: TasksService.del(modelData.idx)
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: TasksService.tasks.length === 0 && !TasksService.loading
                text: "Sin tareas hoy — añade la primera arriba"
                color: Theme.fgDimmer
                font.family: Theme.fontFamily
                font.pixelSize: Theme.pixelMedium
            }
        }
    }
}
