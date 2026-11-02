import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import ".."

PanelWindow {
    id: root

    property var parentWindow: null
    property var targetItem: null
    screen: parentWindow ? parentWindow.screen : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)

    // Fill screen so any click outside the card is caught and consumed
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    visible: false
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notifications"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

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
            if (Date.now() - lastCloseTime < 250) return;
            open();
        }
    }

    NumberAnimation {
        id: openAnim
        target: root
        property: "animProgress"
        from: root.animProgress
        to: 1.0
        duration: 320
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: closeAnim
        target: root
        property: "animProgress"
        from: root.animProgress
        to: 0.0
        duration: 250
        easing.type: Easing.InCubic
        onFinished: {
            if (!root.isOpen) {
                root.visible = false;
            }
        }
    }

    HyprlandFocusGrab {
        windows: (root.parentWindow) ? [ root, root.parentWindow ] : [ root ]
        active: root.isOpen
        onCleared: root.close()
    }

    // Fullscreen backdrop: absorbs any click outside the card so nothing underneath is triggered
    MouseArea {
        id: backdropArea
        anchors.fill: parent
        hoverEnabled: false
        onPressed: mouse => {
            root.close();
            mouse.accepted = true;
        }
    }

    Rectangle {
        id: mainCard
        width: 380
        implicitHeight: contentCol.implicitHeight + 28
        color: Theme.background
        border.color: Theme.outlineVariant
        border.width: 1
        radius: 18
        clip: true

        // Prevent clicks inside the card from propagating to the dismiss backdrop
        MouseArea {
            anchors.fill: parent
            onPressed: mouse => { mouse.accepted = true; }
        }

        // Smooth sliding animation from right:
        // Starts completely off-screen to the right and glides in to rest at 12px from right edge
        y: 50
        x: (root.width - width - 12) + (1.0 - root.animProgress) * (width + 30)
        opacity: root.animProgress

        Column {
            id: contentCol
            anchors.top: parent.top
            anchors.topMargin: 14
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 28
            spacing: 12

            // Top Header: Date & Time at the very top + Do Not Disturb button in the top right corner
            Item {
                width: parent.width
                height: Math.max(clockCol.implicitHeight, dndBtn.implicitHeight)

                // Date & Time
                Column {
                    id: clockCol
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    property var currentTime: new Date()
                    Timer {
                        interval: 1000
                        running: root.visible
                        repeat: true
                        onTriggered: clockCol.currentTime = new Date()
                    }

                    Text {
                        text: Qt.formatDateTime(clockCol.currentTime, "hh:mm")
                        color: Theme.colorOnSurface
                        font.family: Theme.fontFamily
                        font.pixelSize: 28
                        font.bold: true
                        renderType: Text.NativeRendering
                    }

                    Text {
                        text: Qt.formatDateTime(clockCol.currentTime, "dddd, MMMM d")
                        color: Theme.colorOnSurfaceVariant
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        renderType: Text.NativeRendering
                    }
                }

                // Do Not Disturb Button in top right corner with smooth press & toggle animations
                Rectangle {
                    id: dndBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    implicitHeight: 34
                    implicitWidth: dndRow.implicitWidth + 22
                    radius: 17

                    scale: dndMouse.pressed ? 0.92 : (dndMouse.containsMouse ? 1.04 : 1.0)
                    color: NotificationService.dnd ? Theme.primaryContainer : (dndMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)
                    border.color: NotificationService.dnd ? Theme.primary : (dndMouse.containsMouse ? Theme.outline : Theme.outlineVariant)
                    border.width: 1

                    Behavior on scale {
                        NumberAnimation { duration: 160; easing.type: Easing.OutBack }
                    }
                    Behavior on color {
                        ColorAnimation { duration: 200 }
                    }
                    Behavior on border.color {
                        ColorAnimation { duration: 200 }
                    }

                    Row {
                        id: dndRow
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            id: dndIcon
                            anchors.verticalCenter: parent.verticalCenter
                            text: NotificationService.dnd ? "󰂛" : "󰂚"
                            font.family: Theme.iconFamily
                            font.pixelSize: 14
                            color: NotificationService.dnd ? Theme.colorOnPrimaryContainer : Theme.colorOnSurfaceVariant
                            renderType: Text.NativeRendering
                            rotation: NotificationService.dnd ? -15 : 0
                            scale: NotificationService.dnd ? 1.15 : 1.0

                            Behavior on rotation {
                                NumberAnimation { duration: 220; easing.type: Easing.OutBack }
                            }
                            Behavior on scale {
                                NumberAnimation { duration: 200; easing.type: Easing.OutBack }
                            }
                            Behavior on color {
                                ColorAnimation { duration: 200 }
                            }
                        }

                        Text {
                            id: dndLabel
                            anchors.verticalCenter: parent.verticalCenter
                            text: NotificationService.dnd ? "DND On" : "DND"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: true
                            color: NotificationService.dnd ? Theme.colorOnPrimaryContainer : Theme.colorOnSurfaceVariant
                            renderType: Text.NativeRendering

                            Behavior on color {
                                ColorAnimation { duration: 200 }
                            }
                        }
                    }

                    MouseArea {
                        id: dndMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: NotificationService.toggleDnd()
                    }
                }
            }

            // Divider
            Rectangle {
                width: parent.width
                height: 1
                color: Theme.outlineVariant
            }

            // Notifications Header with count badge & Clear all
            Item {
                width: parent.width
                height: 22

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Text {
                        text: "Notifications"
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.bold: true
                        color: Theme.colorOnSurface
                        renderType: Text.NativeRendering
                    }

                    Rectangle {
                        visible: NotificationService.count > 0
                        width: countText.implicitWidth + 10
                        height: 18
                        radius: 9
                        color: Theme.primaryContainer
                        anchors.verticalCenter: parent.verticalCenter

                        scale: visible ? 1.0 : 0.0
                        Behavior on scale {
                            NumberAnimation { duration: 200; easing.type: Easing.OutBack }
                        }

                        Text {
                            id: countText
                            anchors.centerIn: parent
                            text: NotificationService.count
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: true
                            color: Theme.colorOnPrimaryContainer
                            renderType: Text.NativeRendering
                        }
                    }
                }

                // Clear all button
                Rectangle {
                    visible: NotificationService.count > 0
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: clearRow.implicitWidth + 12
                    implicitHeight: 22
                    radius: 11
                    scale: clearMouse.pressed ? 0.93 : (clearMouse.containsMouse ? 1.05 : 1.0)
                    color: clearMouse.containsMouse ? Theme.errorContainer : "transparent"

                    Behavior on scale {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }

                    Row {
                        id: clearRow
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰎟"
                            font.family: Theme.iconFamily
                            font.pixelSize: 12
                            color: clearMouse.containsMouse ? Theme.colorOnErrorContainer : Theme.colorOnSurfaceVariant
                            renderType: Text.NativeRendering
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Clear all"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: true
                            color: clearMouse.containsMouse ? Theme.colorOnErrorContainer : Theme.colorOnSurfaceVariant
                            renderType: Text.NativeRendering
                        }
                    }

                    MouseArea {
                        id: clearMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: NotificationService.clearAll()
                    }
                }
            }

            // Notification zone: displays only 3 at a time, scrollable for more
            Item {
                width: parent.width
                height: NotificationService.count === 0 ? 100 : (Math.min(NotificationService.count, 3) * 84 + Math.max(0, Math.min(NotificationService.count, 3) - 1) * 8)

                Behavior on height {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }

                // Empty state with smooth fade
                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    opacity: NotificationService.count === 0 ? 1.0 : 0.0
                    scale: NotificationService.count === 0 ? 1.0 : 0.9
                    visible: opacity > 0

                    Behavior on opacity {
                        NumberAnimation { duration: 200 }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: ""
                        font.family: Theme.iconFamily
                        font.pixelSize: 28
                        color: Theme.colorOnSurfaceVariant
                        renderType: Text.NativeRendering
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "No notifications"
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: Theme.colorOnSurfaceVariant
                        renderType: Text.NativeRendering
                    }
                }

                // List of notifications with entrance and displacement animations
                ListView {
                    id: notifList
                    anchors.fill: parent
                    clip: true
                    spacing: 8
                    boundsBehavior: Flickable.StopAtBounds
                    model: NotificationService.notificationList
                    opacity: NotificationService.count > 0 ? 1.0 : 0.0
                    visible: opacity > 0

                    Behavior on opacity {
                        NumberAnimation { duration: 200 }
                    }

                    // Smooth animations for getting notifications and list updates
                    add: Transition {
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 280; easing.type: Easing.OutCubic }
                            NumberAnimation { property: "scale"; from: 0.88; to: 1.0; duration: 280; easing.type: Easing.OutBack }
                            NumberAnimation { property: "y"; from: -24; duration: 280; easing.type: Easing.OutCubic }
                        }
                    }

                    displaced: Transition {
                        NumberAnimation { properties: "y"; duration: 250; easing.type: Easing.OutCubic }
                    }

                    remove: Transition {
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; to: 0.0; duration: 200; easing.type: Easing.OutQuad }
                            NumberAnimation { property: "scale"; to: 0.82; duration: 200; easing.type: Easing.InQuad }
                        }
                    }

                    // Scroll bar ONLY visible when count > 3, completely hidden otherwise
                    ScrollBar.vertical: ScrollBar {
                        id: scrollBar
                        visible: NotificationService.count > 3
                        enabled: NotificationService.count > 3
                        policy: NotificationService.count > 3 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                        width: 4
                        opacity: NotificationService.count > 3 ? 1.0 : 0.0

                        Behavior on opacity {
                            NumberAnimation { duration: 200 }
                        }

                        contentItem: Rectangle {
                            implicitWidth: 4
                            radius: 2
                            color: Theme.foreground
                            opacity: scrollBar.pressed ? 0.85 : (scrollBar.hovered ? 0.65 : 0.4)

                            Behavior on opacity {
                                NumberAnimation { duration: 150 }
                            }
                        }
                    }

                    delegate: Rectangle {
                        id: cardRoot
                        width: notifList.width - (NotificationService.count > 3 ? 8 : 0)
                        height: 84
                        radius: 12
                        scale: cardMouse.pressed ? 0.98 : (cardMouse.containsMouse ? 1.01 : 1.0)
                        color: cardMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                        border.color: cardMouse.containsMouse ? Theme.outline : Theme.outlineVariant
                        border.width: 1

                        Behavior on width {
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }
                        Behavior on scale {
                            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                        }
                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }
                        Behavior on border.color {
                            ColorAnimation { duration: 150 }
                        }

                        // App Icon
                        Rectangle {
                            id: iconBox
                            width: 38
                            height: 38
                            radius: 10
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.secondaryContainer

                            IconImage {
                                id: cardIcon
                                anchors.fill: parent
                                anchors.margins: 4
                                source: modelData ? (modelData.image || modelData.appIcon || "") : ""
                                visible: source !== ""
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: !cardIcon.visible || cardIcon.status !== Image.Ready
                                text: ""
                                font.family: Theme.iconFamily
                                font.pixelSize: 18
                                color: Theme.colorOnSecondaryContainer
                                renderType: Text.NativeRendering
                            }
                        }

                        // Content (App name, time, summary, body, actions)
                        Column {
                            anchors.left: iconBox.right
                            anchors.leftMargin: 10
                            anchors.right: closeCardBtn.left
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Row {
                                spacing: 4
                                Text {
                                    text: modelData ? (modelData.appName || "Notification") : ""
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: Theme.colorOnSurfaceVariant
                                    renderType: Text.NativeRendering
                                }
                                Text {
                                    text: "•"
                                    font.pixelSize: 10
                                    color: Theme.colorOnSurfaceVariant
                                    renderType: Text.NativeRendering
                                }
                                Text {
                                    text: modelData ? NotificationService.formatTimestamp(modelData.id) : ""
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Theme.colorOnSurfaceVariant
                                    renderType: Text.NativeRendering
                                }
                            }

                            Text {
                                width: parent.width
                                text: modelData ? (modelData.summary || "") : ""
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: true
                                color: Theme.colorOnSurface
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                renderType: Text.NativeRendering
                            }

                            Text {
                                width: parent.width
                                text: modelData ? (modelData.body || "") : ""
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.colorOnSurfaceVariant
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                renderType: Text.NativeRendering
                            }

                            // Notification Action buttons (if available)
                            Row {
                                visible: modelData && modelData.actions && modelData.actions.length > 0
                                spacing: 6

                                Repeater {
                                    model: (modelData && modelData.actions) ? modelData.actions : []
                                    delegate: Rectangle {
                                        height: 20
                                        implicitWidth: actionLabel.implicitWidth + 10
                                        radius: 5
                                        color: actionMouse.containsMouse ? Theme.primaryContainer : Theme.secondaryContainer
                                        border.color: actionMouse.containsMouse ? Theme.primary : Theme.outlineVariant
                                        border.width: 1

                                        Text {
                                            id: actionLabel
                                            anchors.centerIn: parent
                                            text: modelData.text || ""
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            color: actionMouse.containsMouse ? Theme.colorOnPrimaryContainer : Theme.colorOnSecondaryContainer
                                            renderType: Text.NativeRendering
                                        }

                                        MouseArea {
                                            id: actionMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (modelData) modelData.invoke();
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Close / Dismiss button for individual notification
                        Rectangle {
                            id: closeCardBtn
                            width: 22
                            height: 22
                            radius: 11
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.top: parent.top
                            anchors.topMargin: 8
                            scale: closeCardMouse.pressed ? 0.88 : (closeCardMouse.containsMouse ? 1.15 : 1.0)
                            color: closeCardMouse.containsMouse ? Theme.errorContainer : "transparent"

                            Behavior on scale {
                                NumberAnimation { duration: 150; easing.type: Easing.OutBack }
                            }
                            Behavior on color {
                                ColorAnimation { duration: 150 }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                font.pixelSize: 10
                                color: closeCardMouse.containsMouse ? Theme.colorOnErrorContainer : Theme.colorOnSurfaceVariant
                                renderType: Text.NativeRendering

                                Behavior on color {
                                    ColorAnimation { duration: 150 }
                                }
                            }

                            MouseArea {
                                id: closeCardMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData) NotificationService.dismiss(modelData);
                                }
                            }
                        }

                        // Clicking anywhere on card invokes default action or dismisses
                        MouseArea {
                            id: cardMouse
                            anchors.fill: parent
                            anchors.rightMargin: 32
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData) {
                                    if (modelData.actions && modelData.actions.length > 0) {
                                        modelData.actions[0].invoke();
                                    } else {
                                        NotificationService.dismiss(modelData);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
