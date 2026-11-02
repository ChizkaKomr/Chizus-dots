import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import ".."

Rectangle {
    id: root

    color: "transparent"
    radius: 0
    implicitHeight: Theme.pillHeight
    implicitWidth: 40


    property string layoutCode: "US"

    function parseLayout(layoutName) {
        if (!layoutName) return "US";
        const lower = layoutName.toLowerCase();
        if (lower.includes("ukrain") || lower.includes("ua")) return "UA";
        if (lower.includes("russ") || lower.includes("ru")) return "RU";
        if (lower.includes("english") || lower.includes("us")) return "US";
        return layoutName.substring(0, 2).toUpperCase();
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout") {
                const parts = event.data.split(",");
                if (parts.length >= 2) {
                    root.layoutCode = root.parseLayout(parts[1]);
                }
            }
        }
    }

    Process {
        id: langQuery
        command: ["bash", "-c", "hyprctl devices -j | jq -r '.keyboards[] | select(.main == true) | .active_keymap' 2>/dev/null || echo 'English'"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (data.trim().length > 0) {
                    root.layoutCode = root.parseLayout(data.trim());
                }
            }
        }
    }

    Text {
        id: langText
        anchors.centerIn: parent
        text: root.layoutCode
        color: mouseArea.containsMouse ? Qt.lighter(Theme.foreground, 1.25) : Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: 15
        font.bold: true
        renderType: Text.NativeRendering

        Behavior on color {
            ColorAnimation { duration: 150 }
        }
    }

    Process {
        id: langSwitchProc
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            langSwitchProc.exec(["hyprctl", "switchxkblayout", "all", "next"]);
            langQuery.running = true;
        }
    }
}
