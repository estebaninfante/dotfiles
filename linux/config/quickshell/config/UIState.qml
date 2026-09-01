pragma Singleton
import QtQuick

Item {
    property bool widgetMenuOpen: false
    property bool powerMenuOpen: false
    property bool volumeMenuOpen: false
    property bool brightnessMenuOpen: false
    property bool ramMenuOpen: false
    property bool dateMenuOpen: false
    property bool controlCenterOpen: false
    property bool launcherOpen: false
    property string launcherMode: "apps"
    property string powerMenuPendingAction: ""
    property bool powerMenuProfilesOpen: false

    readonly property bool anyMenuOpen: widgetMenuOpen || powerMenuOpen || volumeMenuOpen || brightnessMenuOpen || ramMenuOpen || dateMenuOpen || controlCenterOpen || launcherOpen

    property string activeSection: "conexiones"
    property string monitorDetail: ""

    signal hoversReset()
}
