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

    // State matching ClipboardManager
    property bool isOpen: false
    property real animProgress: 0.0
    property double lastCloseTime: 0

    onVisibleChanged: {
        if (visible && !isOpen) {
            open();
        } else if (!visible && isOpen) {
            close();
        }
    }

    function open() {
        if (isOpen && visible) return;
        isOpen = true;
        visible = true;
        closeAnim.stop();
        openAnim.restart();
        menuCol.updateWidth();
        menuContainer.forceActiveFocus();
    }

    function close() {
        if (!isOpen && !visible) return;
        isOpen = false;
        lastCloseTime = Date.now();
        openAnim.stop();
        closeAnim.restart();
    }

    function toggle() {
        if (isOpen) {
            close();
        } else {
            if (Date.now() - lastCloseTime < 200) return;
            open();
        }
    }

    NumberAnimation {
        id: openAnim
        target: root
        property: "animProgress"
        from: root.animProgress
        to: 1.0
        duration: 220
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: closeAnim
        target: root
        property: "animProgress"
        from: root.animProgress
        to: 0.0
        duration: 180
        easing.type: Easing.InCubic
        onFinished: {
            if (!root.isOpen) {
                root.visible = false;
            }
        }
    }

    implicitWidth: menuContainer.implicitWidth
    implicitHeight: menuContainer.implicitHeight

    HyprlandFocusGrab {
        windows: [ root ]
        active: root.isOpen
        onCleared: root.close()
    }

    QsMenuOpener {
        id: menuOpener
        menu: root.menuHandle
        onChildrenChanged: menuCol.updateWidth()
    }

    Rectangle {
        id: menuContainer
        color: Theme.background
        border.color: Theme.foreground
        border.width: 1
        radius: 16

        scale: 0.95 + 0.05 * root.animProgress
        opacity: root.animProgress
        transformOrigin: Item.Top

        focus: true
        Keys.onEscapePressed: event => {
            root.close();
            event.accepted = true;
        }

        implicitWidth: menuCol.menuWidth + 10
        implicitHeight: menuCol.implicitHeight + 10

        Column {
            id: menuCol
            anchors.centerIn: parent
            spacing: 2
            property real menuWidth: 170

            function updateWidth() {
                let maxW = 170;
                for (let i = 0; i < itemRepeater.count; i++) {
                    const item = itemRepeater.itemAt(i);
                    if (item && item.implicitWidth > maxW) {
                        maxW = item.implicitWidth;
                    }
                }
                menuWidth = maxW;
            }

            Repeater {
                id: itemRepeater
                model: menuOpener.children
                onItemAdded: menuCol.updateWidth()
                onItemRemoved: menuCol.updateWidth()
                onCountChanged: menuCol.updateWidth()

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

                    onImplicitWidthChanged: menuCol.updateWidth()
                    Component.onCompleted: menuCol.updateWidth()

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
                                    root.close();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
