import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Notifications
import ".."

PanelWindow {
    id: root

    property var parentScreen: null
    screen: parentScreen || (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)

    anchors {
        top: true
        right: true
    }
    margins.top: 54
    margins.right: 12

    visible: activeToasts.length > 0
    color: "transparent"

    implicitWidth: 440
    implicitHeight: Math.max(1, toastCol.implicitHeight + 40)

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-toasts"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    property var activeToasts: []

    Connections {
        target: NotificationService
        function onNotificationReceived(notif) {
            if (!notif) return;

            const isCrit = Boolean(
                notif.urgency === NotificationUrgency.Critical ||
                (notif.hints && (notif.hints["urgency"] === 2 || notif.hints["urgency"] === "2" || notif.hints["urgency"] === "critical"))
            );

            if (NotificationService.dnd && !isCrit) return;

            const existing = activeToasts.find(t => t && t.id === notif.id);
            if (existing) return;

            let current = [...activeToasts];
            if (current.length >= 4) {
                current = current.slice(0, 3);
            }
            activeToasts = [notif, ...current];
        }
    }

    function removeToast(notifId) {
        activeToasts = activeToasts.filter(t => t && t.id !== notifId);
    }

    Column {
        id: toastCol
        anchors.top: parent.top
        anchors.topMargin: 4
        anchors.right: parent.right
        anchors.rightMargin: 10
        spacing: 6

        Repeater {
            model: root.activeToasts

            delegate: Item {
                id: delegateRoot
                width: 410
                implicitHeight: card.implicitHeight

                required property var modelData

                property bool isDismissing: false
                property bool isCritical: Boolean(modelData && (
                    modelData.urgency === NotificationUrgency.Critical ||
                    (modelData.hints && (modelData.hints["urgency"] === 2 || modelData.hints["urgency"] === "2" || modelData.hints["urgency"] === "critical"))
                ))

                // Normal stays 2.5s (2500ms), Critical stays 5.0s (5000ms)
                property real totalDuration: isCritical ? 5000 : 2500
                property real remainingTime: totalDuration

                property bool isHovered: cardMouse.containsMouse || closeMouse.containsMouse

                onIsHoveredChanged: {
                    if (!isHovered && !isDismissing && modelData) {
                        totalDuration = 1800;
                        remainingTime = 1800;
                        countdownTimer.restart();
                    }
                }

                Timer {
                    id: countdownTimer
                    interval: 16
                    repeat: true
                    running: !delegateRoot.isHovered && !delegateRoot.isDismissing
                    onTriggered: {
                        delegateRoot.remainingTime = Math.max(0, delegateRoot.remainingTime - 16);
                        if (delegateRoot.remainingTime <= 0) {
                            countdownTimer.stop();
                            delegateRoot.dismiss();
                        }
                    }
                }

                Connections {
                    target: modelData
                    ignoreUnknownSignals: true
                    function onClosed() {
                        delegateRoot.dismiss();
                    }
                }

                function dismiss() {
                    if (isDismissing) return;
                    isDismissing = true;
                    slideOutAnim.restart();
                }

                Item {
                    id: cardContainer
                    width: parent.width
                    height: parent.height
                    x: 420
                    opacity: 0.0

                    Component.onCompleted: {
                        slideInAnim.restart();
                    }

                    ParallelAnimation {
                        id: slideInAnim
                        NumberAnimation {
                            target: cardContainer
                            property: "x"
                            from: 420
                            to: 0
                            duration: 320
                            easing.type: Easing.OutCubic
                        }
                        NumberAnimation {
                            target: cardContainer
                            property: "opacity"
                            from: 0.0
                            to: 1.0
                            duration: 220
                            easing.type: Easing.OutQuad
                        }
                    }

                    ParallelAnimation {
                        id: slideOutAnim
                        NumberAnimation {
                            target: cardContainer
                            property: "x"
                            from: cardContainer.x
                            to: 420
                            duration: 260
                            easing.type: Easing.InCubic
                        }
                        NumberAnimation {
                            target: cardContainer
                            property: "opacity"
                            to: 0.0
                            duration: 200
                            easing.type: Easing.InQuad
                        }
                        onFinished: {
                            if (modelData) {
                                root.removeToast(modelData.id);
                            }
                        }
                    }

                    Item {
                        id: shadowSource
                        anchors.fill: card
                        visible: false
                        Rectangle {
                            anchors.fill: parent
                            radius: card.radius
                            color: Theme.foreground
                        }
                    }

                    MultiEffect {
                        source: shadowSource
                        anchors.fill: card
                        shadowEnabled: true
                        shadowColor: Theme.foreground
                        shadowBlur: 1.0
                        shadowScale: 1.05
                        shadowOpacity: delegateRoot.isHovered ? 0.60 : 0.0
                        opacity: shadowOpacity

                        Behavior on shadowOpacity {
                            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                        }
                    }

                    Rectangle {
                        id: card
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 380
                        implicitHeight: Math.max(92, Math.max(iconBox.height + 28, textCol.implicitHeight + (actionsRow.visible ? actionsRow.implicitHeight + 8 : 0) + 24))
                        radius: 22
                        color: Theme.background
                        border.color: delegateRoot.isCritical ? Theme.alertRed : Theme.foreground
                        border.width: 2
                        clip: true

                        Item {
                            id: iconBox
                            width: 60
                            height: 60
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter

                            Item {
                                id: iconContent
                                anchors.fill: parent
                                layer.enabled: true

                                Rectangle {
                                    id: maskRect
                                    width: iconContent.width
                                    height: iconContent.height
                                    radius: 18
                                    visible: false
                                }

                                layer.effect: MultiEffect {
                                    maskEnabled: true
                                    maskSource: maskRect
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 18
                                    color: delegateRoot.isCritical ? Qt.rgba(Theme.alertRed.r, Theme.alertRed.g, Theme.alertRed.b, 0.22) : Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.2)
                                }

                                // Full-bleed image loader for file paths & URLs (e.g. album art cover)
                                Image {
                                    id: fileImg
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectCrop
                                    source: {
                                        if (!modelData) return "";
                                        const s = String(modelData.image || modelData.appIcon || "");
                                        if (s.startsWith("/")) return "file://" + s;
                                        if (s.startsWith("file://") || s.startsWith("http://") || s.startsWith("https://")) return s;
                                        return "";
                                    }
                                    visible: status === Image.Ready
                                }

                                // Fallback IconImage for desktop theme icons (e.g. "firefox", "spotify")
                                IconImage {
                                    id: themeIcon
                                    anchors.fill: parent
                                    backer.fillMode: Image.PreserveAspectCrop
                                    source: {
                                        if (!modelData || fileImg.status === Image.Ready) return "";
                                        const s = String(modelData.appIcon || modelData.image || "");
                                        if (s.startsWith("/") || s.startsWith("file://")) return "";
                                        return s;
                                    }
                                    visible: !fileImg.visible && source !== ""
                                }

                                // Fallback glyph icon when no image
                                Text {
                                    anchors.centerIn: parent
                                    visible: !fileImg.visible && !themeIcon.visible
                                    text: delegateRoot.isCritical ? "󰀦" : (modelData && modelData.appName ? "" : "󰂚")
                                    font.family: Theme.iconFamily
                                    font.pixelSize: 26
                                    color: delegateRoot.isCritical ? Theme.alertRed : Theme.foreground
                                    renderType: Text.NativeRendering
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: 18
                                color: "transparent"
                                border.color: delegateRoot.isCritical ? Qt.rgba(Theme.alertRed.r, Theme.alertRed.g, Theme.alertRed.b, 0.5) : Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.35)
                                border.width: 1
                            }
                        }

                        Column {
                            id: textCol
                            anchors.left: iconBox.right
                            anchors.leftMargin: 14
                            anchors.right: closeBtn.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Text {
                                width: parent.width
                                text: {
                                    if (!modelData) return "Notification";
                                    if (modelData.appName && modelData.appName.length > 0) return modelData.appName;
                                    if (modelData.summary && modelData.summary.length > 0) return modelData.summary;
                                    return "Notification";
                                }
                                font.family: Theme.fontFamily
                                font.pixelSize: 15
                                font.bold: true
                                color: "#ffffff"
                                elide: Text.ElideRight
                                renderType: Text.NativeRendering
                            }

                            Text {
                                width: parent.width
                                text: {
                                    if (!modelData) return "";
                                    if (modelData.appName && modelData.summary && modelData.summary !== modelData.appName) {
                                        return modelData.body ? (modelData.summary + "\n" + modelData.body) : modelData.summary;
                                    }
                                    return modelData.body || modelData.summary || "";
                                }
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                color: Qt.rgba(1, 1, 1, 0.85)
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                                renderType: Text.NativeRendering
                            }

                            Row {
                                id: actionsRow
                                visible: modelData && modelData.actions && modelData.actions.length > 0
                                spacing: 6

                                Repeater {
                                    model: (modelData && modelData.actions) ? modelData.actions : []
                                    delegate: Rectangle {
                                        height: 20
                                        implicitWidth: actLabel.implicitWidth + 10
                                        radius: 5
                                        color: actMouse.containsMouse ? Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.28) : Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.14)
                                        border.color: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.3)
                                        border.width: 1

                                        Text {
                                            id: actLabel
                                            anchors.centerIn: parent
                                            text: modelData.text || ""
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            color: Theme.foreground
                                            renderType: Text.NativeRendering
                                        }

                                        MouseArea {
                                            id: actMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (modelData) modelData.invoke();
                                                delegateRoot.dismiss();
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Item {
                            id: closeBtn
                            width: 32
                            height: 32
                            anchors.top: parent.top
                            anchors.topMargin: 12
                            anchors.right: parent.right
                            anchors.rightMargin: 12

                            Shape {
                                anchors.fill: parent
                                layer.enabled: true
                                layer.samples: 4
                                ShapePath {
                                    strokeColor: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.22)
                                    strokeWidth: 2
                                    fillColor: "transparent"
                                    PathAngleArc {
                                        centerX: 16
                                        centerY: 16
                                        radiusX: 13
                                        radiusY: 13
                                        startAngle: -90
                                        sweepAngle: 360
                                    }
                                }
                            }

                            Shape {
                                anchors.fill: parent
                                layer.enabled: true
                                layer.samples: 4
                                ShapePath {
                                    strokeColor: delegateRoot.isCritical ? Theme.alertRed : Theme.foreground
                                    strokeWidth: 2.2
                                    fillColor: "transparent"
                                    capStyle: ShapePath.RoundCap
                                    PathAngleArc {
                                        centerX: 16
                                        centerY: 16
                                        radiusX: 13
                                        radiusY: 13
                                        startAngle: -90
                                        sweepAngle: Math.max(0, Math.min(360, (delegateRoot.remainingTime / delegateRoot.totalDuration) * 360))
                                    }
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                font.pixelSize: 12
                                font.bold: true
                                color: closeMouse.containsMouse ? (delegateRoot.isCritical ? Theme.alertRed : Qt.lighter(Theme.foreground, 1.25)) : (delegateRoot.isCritical ? Theme.alertRed : Theme.foreground)
                                renderType: Text.NativeRendering
                                scale: closeMouse.pressed ? 0.85 : (closeMouse.containsMouse ? 1.15 : 1.0)
                                Behavior on scale { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                id: closeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    delegateRoot.dismiss();
                                    if (modelData) NotificationService.dismiss(modelData);
                                }
                            }
                        }

                        MouseArea {
                            id: cardMouse
                            anchors.fill: parent
                            anchors.rightMargin: 44
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData) {
                                    if (modelData.actions && modelData.actions.length > 0) {
                                        modelData.actions[0].invoke();
                                    }
                                }
                                delegateRoot.dismiss();
                            }
                        }
                    }
                }
            }
        }
    }
}