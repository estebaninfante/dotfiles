pragma Singleton
import QtQuick

QtObject {
    property bool widgetMenuOpen: false
    property bool powerMenuOpen: false
    property bool volumeMenuOpen: false
    property bool brightnessMenuOpen: false
    property bool ramMenuOpen: false
    property bool dateMenuOpen: false
    property bool controlCenterOpen: false

    readonly property bool anyMenuOpen: widgetMenuOpen || powerMenuOpen || volumeMenuOpen || brightnessMenuOpen || ramMenuOpen || dateMenuOpen || controlCenterOpen

    property string activeSection: "conexiones"
    property string monitorDetail: ""

    signal hoversReset()
}
