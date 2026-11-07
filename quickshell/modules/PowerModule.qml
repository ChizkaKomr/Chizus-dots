import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Item {
    id: root

    // Hit area reaches all the way into the screen's top-left corner (so it is easy to hit);
    // the visible pill is the original shape: 40x32, 12px in from the left, centred in the 44px bar.
    readonly property int pillX: 12
    readonly property int pillY: 6
    implicitWidth: pillX + 40
    implicitHeight: pillY + Theme.pillHeight

    Rectangle {
        id: pill
        x: root.pillX
        y: root.pillY
        width: 40
        height: Theme.pillHeight
        radius: Theme.pillRadius
        color: Theme.background
    }

    property var barWindow: null

    PowerMenu {
        id: powerMenu
        parentWindow: root.barWindow
    }

    Text {
        id: powerLabel
        anchors.centerIn: pill
        text: "󰤄"
        color: mouseArea.containsMouse ? Qt.lighter(Theme.foreground, 1.25) : Theme.foreground
        font.family: Theme.iconFamily
        font.pixelSize: 20
        renderType: Text.NativeRendering
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter

        Behavior on color {
            ColorAnimation { duration: 150 }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            powerMenu.toggle();
        }
    }
}
