import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import ".."

PopupWindow {
    id: root

    property var targetItem: null
    property var menuHandle: null
    property var parentWindow: null

    anchor.window: parentWindow
    anchor.item: targetItem
    anchor.edges: Edges.Bottom | Edges.Left
    anchor.gravity: Edges.Bottom | Edges.Right
    anchor.adjustment: PopupAdjustment.Slide | PopupAdjustment.Flip
    anchor.margins.top: 4

    visible: false
    grabFocus: false
    color: "transparent"

    implicitWidth: menuContainer.implicitWidth
    implicitHeight: menuContainer.implicitHeight

    HyprlandFocusGrab {
        windows: [ root ]
        active: root.visible
        onCleared: root.visible = false
    }

    QsMenuOpener {
        id: menuOpener
        menu: root.menuHandle
    }

    Rectangle {
        id: menuContainer
        color: Theme.background
        border.color: Theme.foreground
        border.width: 1
        radius: 16

        implicitWidth: menuCol.menuWidth + 10
        implicitHeight: menuCol.implicitHeight + 10

        Column {
            id: menuCol
            anchors.centerIn: parent
            spacing: 2
            property real menuWidth: Math.max(170, implicitWidth)

            Repeater {
                id: itemRepeater
                model: menuOpener.children

                delegate: Item {
                    id: entryItem
                    required property var modelData

                    property bool isSeparator: modelData ? modelData.isSeparator : false
                    property bool isItemEnabled: modelData ? modelData.enabled : true
                    property string itemText: modelData ? modelData.text : ""
                    property string itemIcon: modelData ? modelData.icon : ""
                    property int itemButtonType: modelData ? modelData.buttonType : 0
                    property int itemCheckState: modelData ? modelData.checkState : 0

                    width: menuCol.menuWidth
                    height: isSeparator ? 9 : 30
                    implicitWidth: isSeparator ? 120 : (itemRow.implicitWidth + 24)
                    implicitHeight: height

                    // Separator line
                    Rectangle {
                        visible: entryItem.isSeparator
                        anchors.centerIn: parent
                        width: parent.width - 12
                        height: 1
                        color: Theme.foreground
                        opacity: 0.25
                    }

                    // Clickable Menu Item
                    Rectangle {
                        id: bgRect
                        visible: !entryItem.isSeparator
                        anchors.fill: parent
                        radius: 4
                        color: itemMouse.containsMouse && entryItem.isItemEnabled ? Theme.foreground : "transparent"

                        Behavior on color {
                            ColorAnimation { duration: 120 }
                        }

                        Row {
                            id: itemRow
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            // Optional checkbox or radio bullet
                            Text {
                                visible: entryItem.itemButtonType !== 0
                                anchors.verticalCenter: parent.verticalCenter
                                text: {
                                    if (entryItem.itemButtonType === 1) { // CheckBox
                                        return entryItem.itemCheckState === Qt.Checked ? "✓" : " "
                                    } else if (entryItem.itemButtonType === 2) { // RadioButton
                                        return entryItem.itemCheckState === Qt.Checked ? "●" : "○"
                                    }
                                    return ""
                                }
                                color: itemMouse.containsMouse && entryItem.isItemEnabled ? Theme.background : Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.bold: true
                            }

                            // Optional icon
                            IconImage {
                                visible: entryItem.itemIcon !== ""
                                width: 16
                                height: 16
                                anchors.verticalCenter: parent.verticalCenter
                                source: entryItem.itemIcon
                            }

                            // Menu Item Text
                            Text {
                                id: labelText
                                anchors.verticalCenter: parent.verticalCenter
                                text: entryItem.itemText
                                color: itemMouse.containsMouse && entryItem.isItemEnabled ? Theme.background : Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.bold: true
                                opacity: entryItem.isItemEnabled ? 1.0 : 0.4
                            }
                        }

                        MouseArea {
                            id: itemMouse
                            anchors.fill: parent
                            hoverEnabled: entryItem.isItemEnabled
                            cursorShape: entryItem.isItemEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor

                            onClicked: {
                                if (entryItem.isItemEnabled && modelData) {
                                    modelData.triggered();
                                    root.visible = false;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
