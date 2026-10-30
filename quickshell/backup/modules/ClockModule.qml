import QtQuick
import Quickshell
import ".."

Rectangle {
    id: root

    color: Theme.background
    radius: Theme.pillRadius
    implicitHeight: Theme.pillHeight
    implicitWidth: (root.showAlt ? dateText.implicitWidth : timeText.implicitWidth) + 24

    Behavior on implicitWidth {
        NumberAnimation {
            duration: 250
            easing.type: Easing.OutCubic
        }
    }

    property bool showAlt: false
    property var currentTime: new Date()

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.currentTime = new Date()
    }

    Item {
        anchors.centerIn: parent
        width: root.showAlt ? dateText.implicitWidth : timeText.implicitWidth
        height: root.height

        Text {
            id: timeText
            anchors.centerIn: parent
            text: Qt.formatDateTime(root.currentTime, "hh:mm")
            color: mouseArea.containsMouse ? Qt.lighter(Theme.foreground, 1.25) : Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
            renderType: Text.NativeRendering
            opacity: root.showAlt ? 0 : 1
            scale: root.showAlt ? 0.9 : 1.0

            Behavior on opacity {
                NumberAnimation { duration: 180 }
            }
            Behavior on scale {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
        }

        Text {
            id: dateText
            anchors.centerIn: parent
            text: Qt.formatDateTime(root.currentTime, "dddd, MMMM d, hh:mm")
            color: mouseArea.containsMouse ? Qt.lighter(Theme.foreground, 1.25) : Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
            renderType: Text.NativeRendering
            opacity: root.showAlt ? 1 : 0
            scale: root.showAlt ? 1.0 : 0.9

            Behavior on opacity {
                NumberAnimation { duration: 180 }
            }
            Behavior on scale {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
        }
    }

    MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: {
        root.showAlt = !root.showAlt;
	}
    }
}
