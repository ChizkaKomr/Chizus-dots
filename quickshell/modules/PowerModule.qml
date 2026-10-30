import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Rectangle {
    id: root

    color: Theme.background
    radius: Theme.pillRadius
    implicitHeight: Theme.pillHeight
    implicitWidth: 40

    scale: mouseArea.pressed ? 0.92 : (mouseArea.containsMouse ? 1.05 : 1.0)
    Behavior on scale {
        NumberAnimation { duration: 150; easing.type: Easing.OutBack }
    }

    Process {
        id: launcher
    }

    Text {
        id: powerLabel
        anchors.centerIn: parent
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
            launcher.exec(["wlogout", "-b", "5"]);
        }
    }
}
