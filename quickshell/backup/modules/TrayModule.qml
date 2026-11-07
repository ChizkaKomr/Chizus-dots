import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import ".."

Rectangle {
    id: root

    property var barWindow: null

    color: "transparent"
    radius: 0
    implicitHeight: Theme.pillHeight
    implicitWidth: trayListView.count > 0 ? trayListView.count * (21 + 10) - 10 + 4 : 0
    visible: implicitWidth > 0

    Behavior on implicitWidth {
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
    }

    function getItems() {
        if (!SystemTray.items || !SystemTray.items.values) return [];
        return [...SystemTray.items.values].reverse();
    }

    ListView {
        id: trayListView
        anchors.centerIn: parent
        orientation: ListView.Horizontal
        spacing: 10
        width: count > 0 ? count * (21 + 10) - 10 : 0
        height: 21
        model: root.getItems()
        clip: false

        add: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.5; to: 1.0; duration: 200; easing.type: Easing.OutBack }
            }
        }

        remove: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 150; easing.type: Easing.InCubic }
                NumberAnimation { property: "scale"; from: 1.0; to: 0.5; duration: 150; easing.type: Easing.InCubic }
            }
        }

        displaced: Transition {
            NumberAnimation { property: "x"; duration: 200; easing.type: Easing.OutCubic }
        }

        delegate: Item {
            id: trayItem
            width: 21
            height: 21

            required property var modelData

            TrayMenu {
                id: trayMenu
                parentWindow: root.barWindow
                targetItem: trayItem
                menuHandle: trayItem.modelData.menu
            }

            IconImage {
                id: iconImg
                anchors.fill: parent
                source: trayItem.modelData.icon
                visible: false
            }

            MultiEffect {
                source: iconImg
                anchors.fill: iconImg
                colorization: 1.0
                colorizationColor: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 1.0)
            }

            MouseArea {
                id: mouseArea
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton) {
                        if (trayItem.modelData.hasMenu && trayMenu.menuHandle) {
                            trayMenu.toggle();
                        } else {
                            trayItem.modelData.secondaryActivate();
                        }
                    } else {
                        if (trayItem.modelData.onlyMenu) {
                            if (trayMenu.menuHandle) trayMenu.toggle();
                        } else {
                            trayItem.modelData.activate();
                        }
                    }
                }
            }
        }
    }
}
