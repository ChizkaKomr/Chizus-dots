import QtQuick
import Quickshell
import Quickshell.Hyprland
import ".."

Rectangle {
    id: root

    color: Theme.background
    radius: Theme.pillRadius
    implicitHeight: Theme.pillHeight
    implicitWidth: row.implicitWidth + 14 // 7px padding on each end so buttons never touch the edge curve

    property var persistentWorkspaces: [1, 2, 3, 4, 5, 6]
    property int activeWorkspaceId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1

    function getWorkspaces() {
        let set = new Set(persistentWorkspaces);
        if (activeWorkspaceId > 0) {
            set.add(activeWorkspaceId);
        }
        if (Hyprland.workspaces && Hyprland.workspaces.values) {
            for (let i = 0; i < Hyprland.workspaces.values.length; i++) {
                let ws = Hyprland.workspaces.values[i];
                if (ws && ws.id > 0) set.add(ws.id);
            }
        }
        return Array.from(set).sort((a, b) => a - b);
    }

    property var workspaceList: getWorkspaces()

    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            root.activeWorkspaceId = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1;
            root.workspaceList = root.getWorkspaces();
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 8

        Repeater {
            model: root.workspaceList

            Rectangle {
                id: wsBtn
                readonly property int wsId: modelData
                readonly property bool isActive: root.activeWorkspaceId === wsId

                // Active button is 20px high centered in 32px pill, leaving 6px margin top/bottom
                implicitHeight: 20
                implicitWidth: wsText.implicitWidth + (isActive ? 40 : 26)
               anchors.verticalCenter: parent.verticalCenter
                radius: 10
                color: isActive ? Theme.foreground : (wsMouse.containsMouse ? Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.15) : "transparent")

                Behavior on color {
                    ColorAnimation { duration: 150 }
                }

                Behavior on implicitWidth {
                    NumberAnimation { duration: 150 }
                }

                Text {
                    id: wsText
                    anchors.centerIn: parent
                    text: wsId.toString()
                    color: isActive ? Theme.background : Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    font.bold: true
                    renderType: Text.NativeRendering
                }

                MouseArea {
                    id: wsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Hyprland.dispatch("hl.dsp.focus({ workspace = " + wsId + " })");
                    }
                }
            }
        }
    }
}
