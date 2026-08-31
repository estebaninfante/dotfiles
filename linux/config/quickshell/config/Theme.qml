pragma Singleton
import QtQuick

Item {
    readonly property string fontFamily: "JetBrainsMono Nerd Font"

    readonly property color bg: "#000000"
    readonly property color bgItem: "#141414"
    readonly property color bgHover: "#1d1d26"
    readonly property color bgHoverSoft: "#222222"
    readonly property color border: "#333333"

    readonly property color fg: "#ffffff"
    readonly property color fgOnWhite: "#000000"
    readonly property color fgDim: "#aaaaaa"
    readonly property color fgDimmer: "#555555"
    readonly property color fgFaint: "#888888"
    readonly property color danger: "#eba0ac"

    readonly property int pixelSmall: 9
    readonly property int pixelMedium: 10
    readonly property int pixelNormal: 11
    readonly property int pixelLarge: 12
    readonly property int pixelTitle: 13
    readonly property int pixelBig: 14
    readonly property int pixelDisplay: 20
    readonly property int pixelDisplayLarge: 22
}
