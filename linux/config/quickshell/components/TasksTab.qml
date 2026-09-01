import QtQuick
import "../config"
import "../services"

// Pestaña TAREAS del centro: añade, completa y borra tareas de la nota
// diaria de Obsidian (~/alicia/Dia/YYYY-MM-DD.md) vía TasksService.
Rectangle {
    id: tasksTab
    width: parent.width
    height: 340
    radius: 10
    color: Theme.bgItem

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
        anchors.margins: 10
        spacing: 8
        visible: TasksService.vaultOk

        Rectangle {
            width: parent.width
            height: 30
            radius: 8
            color: "#000000"
            border.color: taskInput.activeFocus ? Theme.fgFaint : Theme.border
            border.width: 1

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                visible: taskInput.text.length === 0 && !taskInput.activeFocus
                text: "Añadir tarea…"
                color: Theme.fgDimmer
                font.family: Theme.fontFamily
                font.pixelSize: Theme.pixelNormal
                font.italic: true
            }

            TextInput {
                id: taskInput
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 34
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.pixelNormal
                clip: true
                focus: true
                Keys.onReturnPressed: { TasksService.add(taskInput.text); taskInput.text = ""; }
                Keys.onEnterPressed: { TasksService.add(taskInput.text); taskInput.text = ""; }
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf067"
                color: addArea.containsMouse ? Theme.fg : Theme.fgFaint
                font.family: Theme.fontFamily
                font.pixelSize: Theme.pixelLarge
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
            height: parent.height - 38
            clip: true
            spacing: 4
            model: TasksService.tasks

            delegate: Rectangle {
                width: taskList.width
                height: 26
                radius: 6
                color: rowArea.containsMouse ? Theme.bgHover : "#000000"

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    Rectangle {
                        width: 14
                        height: 14
                        radius: 3
                        anchors.verticalCenter: parent.verticalCenter
                        color: modelData.done ? Theme.fg : "transparent"
                        border.color: modelData.done ? Theme.fg : Theme.border
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            visible: modelData.done
                            text: "\uf00c"
                            color: Theme.bg
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: TasksService.toggle(modelData.idx)
                        }
                    }

                    Text {
                        width: parent.width - 14 - 8 - 20 - 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.text
                        color: modelData.done ? Theme.fgFaint : (modelData.prio !== "" ? Theme.fg : Theme.fgDim)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.pixelNormal
                        font.strikeout: modelData.done
                        elide: Text.ElideRight
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: rowArea.containsMouse
                        text: "\uf00d"
                        color: delArea.containsMouse ? Theme.danger : Theme.fgDimmer
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.pixelNormal

                        MouseArea {
                            id: delArea
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: TasksService.del(modelData.idx)
                        }
                    }
                }

                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
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
