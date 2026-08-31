pragma Singleton
import QtQuick

QtObject {
    readonly property int durationFade: 240
    readonly property int durationHold: 250
    readonly property int durationCard: 200
    readonly property int durationCardScale: 250
    readonly property int durationKnob: 600
    readonly property int durationSpinner: 1000

    readonly property int easingInOutCubic: Easing.InOutCubic
    readonly property int easingOutCubic: Easing.OutCubic
    readonly property int easingOutQuad: Easing.OutQuad
    readonly property int easingOutBack: Easing.OutBack
    readonly property int easingInOutSine: Easing.InOutSine
}
