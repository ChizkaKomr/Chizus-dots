import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Rectangle {
    id: root

    color: Theme.background
    radius: Theme.pillRadius
    implicitHeight: Theme.pillHeight
    implicitWidth: audioRow.implicitWidth + 24 // padding: 0 12px

    scale: mouseArea.pressed ? 0.92 : (mouseArea.containsMouse ? 1.05 : 1.0)
    Behavior on scale {
        NumberAnimation { duration: 150; easing.type: Easing.OutBack }
    }

    property var barWindow: null

    VolumeCenter {
        id: volumeCenter
        parentWindow: root.barWindow
        targetItem: root
    }

    property int volumePercent: 85
    property bool isMuted: false

    Process {
        id: volQuery
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                const match = data.match(/Volume:\s+([0-9.]+)/);
                if (match) {
                    root.volumePercent = Math.round(parseFloat(match[1]) * 100);
                }
                root.isMuted = data.includes("[MUTED]");
            }
        }
    }

    Timer {
        interval: 1500
        running: true
        repeat: true
        onTriggered: volQuery.running = true
    }

    Component.onCompleted: {
        volQuery.running = true;
    }

    function getIcon() {
        if (root.isMuted) return "";
        if (root.volumePercent < 50) return " ";
        return " ";
    }

    Row {
        id: audioRow
        anchors.centerIn: parent
        spacing: 4

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.isMuted ? "Muted" : root.volumePercent + "%"
            color: mouseArea.containsMouse ? Qt.lighter(Theme.foreground, 1.25) : Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
            renderType: Text.NativeRendering

            Behavior on color {
                ColorAnimation { duration: 150 }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.getIcon()
            color: mouseArea.containsMouse ? Qt.lighter(Theme.foreground, 1.25) : Theme.foreground
            font.family: Theme.iconFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
            renderType: Text.NativeRendering

            Behavior on color {
                ColorAnimation { duration: 150 }
            }
        }
    }

    Process {
        id: audioAction
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                audioAction.exec(["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"]);
                volQuery.running = true;
            } else {
                volumeCenter.toggle();
            }
        }

        onWheel: wheel => {
            if (wheel.angleDelta.y > 0) {
                audioAction.exec(["pactl", "set-sink-volume", "@DEFAULT_SINK@", "+1%"]);
            } else if (wheel.angleDelta.y < 0) {
                audioAction.exec(["pactl", "set-sink-volume", "@DEFAULT_SINK@", "-1%"]);
            }
            volQuery.running = true;
        }
    }
}
