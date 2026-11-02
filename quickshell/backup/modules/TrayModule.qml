import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import ".."

Rectangle {
    id: root

    property var barWindow: null

    color: Theme.background
    radius: Theme.pillRadius
    implicitHeight: Theme.pillHeight
    visible: trayRepeater.count > 0
    implicitWidth: visible ? row.implicitWidth + 20 : 0 // padding: 2px 10px

    function getItems() {
        if (!SystemTray.items || !SystemTray.items.values) return [];
        return [...SystemTray.items.values].reverse();
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 10

        Repeater {
            id: trayRepeater
            model: root.getItems()

            Item {
                id: trayItem
                width: 21
                height: 21
                anchors.verticalCenter: parent.verticalCenter

                TrayMenu {
                    id: trayMenu
                    parentWindow: root.barWindow
                    targetItem: trayItem
                    menuHandle: modelData.menu
                }

                IconImage {
                    id: iconImg
                    anchors.fill: parent
                    source: modelData.icon
                }

                MouseArea {
                    id: mouseArea
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            if (modelData.hasMenu && trayMenu.menuHandle) {
                                trayMenu.toggle();
                            } else {
                                modelData.secondaryActivate();
                            }
                        } else {
                            if (modelData.onlyMenu) {
                                if (trayMenu.menuHandle) trayMenu.toggle();
                            } else {
                                modelData.activate();
                            }
                        }
                    }
                }
            }
        }
    }
}
