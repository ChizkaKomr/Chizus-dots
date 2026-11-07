import QtQuick
import Quickshell
import ".."

Rectangle {
    id: root

    property var barWindow: null

    color: "transparent"
    radius: 0
    implicitHeight: Theme.pillHeight
    implicitWidth: 32


    NotificationCenter {
        id: notifCenter
        parentWindow: root.barWindow
        targetItem: root
    }

    Connections {
        target: NotificationService
        function onToggleCenterRequested() {
            notifCenter.toggle();
        }
        function onNotificationReceived() {
            if (!NotificationService.dnd) {
                bellRingAnim.restart();
            }
        }
    }

    // Bell ring/wobble animation on getting a notification
    SequentialAnimation {
        id: bellRingAnim
        NumberAnimation { target: bellIcon; property: "rotation"; to: -16; duration: 55; easing.type: Easing.OutQuad }
        NumberAnimation { target: bellIcon; property: "rotation"; to: 16; duration: 75; easing.type: Easing.InOutQuad }
        NumberAnimation { target: bellIcon; property: "rotation"; to: -10; duration: 65; easing.type: Easing.InOutQuad }
        NumberAnimation { target: bellIcon; property: "rotation"; to: 10; duration: 55; easing.type: Easing.InOutQuad }
        NumberAnimation { target: bellIcon; property: "rotation"; to: 0; duration: 45; easing.type: Easing.OutQuad }
    }

    Item {
        anchors.centerIn: parent
        width: bellIcon.implicitWidth
        height: bellIcon.implicitHeight

        Text {
            id: bellIcon
            anchors.centerIn: parent
            text: NotificationService.dnd ? "󰂛" : (NotificationService.count > 0 ? "" : "󰂚")
            color: mouseArea.containsMouse ? Qt.lighter(Theme.foreground, 1.25) : Theme.foreground
            font.family: Theme.iconFamily
            font.pixelSize: 15
            renderType: Text.NativeRendering
            transformOrigin: Item.Top

            Behavior on color {
                ColorAnimation { duration: 150 }
            }
        }

        // Red dot badge matching Waybar's <sup></sup> with pop-in animation
        Rectangle {
            id: dotBadge
            visible: NotificationService.count > 0 && !NotificationService.dnd
            width: 5
            height: 5
            radius: 2.5
            color: Theme.alertRed
            anchors.top: bellIcon.top
            anchors.topMargin: 0
            anchors.left: bellIcon.right
            anchors.leftMargin: -2

            scale: (NotificationService.count > 0 && !NotificationService.dnd) ? 1.0 : 0.0
            Behavior on scale {
                NumberAnimation { duration: 200; easing.type: Easing.OutBack }
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                NotificationService.toggleDnd();
            } else {
                notifCenter.toggle();
            }
        }
    }
}
