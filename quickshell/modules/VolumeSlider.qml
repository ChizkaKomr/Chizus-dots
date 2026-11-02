import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import ".."

Item {
    id: root

    property var node: null
    property string title: ""
    property string subtitle: ""
    property string iconName: ""
    property bool isInput: false
    property bool isAppStream: false
    property real maxVolume: 1.5 // 150% maximum as depicted in Figma reference

    // Fallback/Direct values when not bound to a node
    property real manualVolume: 0.8
    property bool manualMuted: false

    readonly property real currentVolume: node && node.audio ? node.audio.volume : manualVolume
    readonly property bool isMuted: node && node.audio ? (node.audio.muted || node.audio.volume <= 0.001) : manualMuted

    // Smart mute memory: caches pre-muted volume
    property real savedVolume: 0.8

    implicitWidth: 380
    implicitHeight: 60

    function setVolume(val) {
        let clamped = Math.max(0.0, Math.min(root.maxVolume, val));
        // Subtle magnetic snap near exactly 1.0 (100% normal max)
        if (Math.abs(clamped - 1.0) < 0.015) {
            clamped = 1.0;
        }
        if (root.node && root.node.audio) {
            root.node.audio.volume = clamped;
            if (clamped > 0.005 && root.node.audio.muted) {
                root.node.audio.muted = false;
            }
        } else {
            root.manualVolume = clamped;
            if (clamped > 0.005 && root.manualMuted) {
                root.manualMuted = false;
            }
        }
    }

    function toggleMute() {
        if (root.isMuted) {
            // Restore saved volume
            const restore = root.savedVolume > 0.05 ? root.savedVolume : 0.8;
            if (root.node && root.node.audio) {
                root.node.audio.muted = false;
                root.node.audio.volume = Math.min(restore, root.maxVolume);
            } else {
                root.manualMuted = false;
                root.manualVolume = Math.min(restore, root.maxVolume);
            }
        } else {
            // Save current volume and mute
            if (root.currentVolume > 0.02) {
                root.savedVolume = root.currentVolume;
            }
            if (root.node && root.node.audio) {
                root.node.audio.muted = true;
                root.node.audio.volume = 0.0;
            } else {
                root.manualMuted = true;
                root.manualVolume = 0.0;
            }
        }
    }

    function getFallbackIcon() {
        if (root.isInput) {
            return root.isMuted ? "󰍭" : "󰍬";
        }
        if (root.isMuted) return "󰝟";
        if (root.currentVolume < 0.33) return "";
        if (root.currentVolume < 0.66) return "";
        return "";
    }

    Row {
        id: rowContainer
        anchors.fill: parent
        spacing: 12

        // 1. Material Design 3 Mute / App Icon Button
        Rectangle {
            id: muteBtn
            width: 36
            height: 36
            anchors.verticalCenter: parent.verticalCenter
            radius: 18
            color: root.isMuted ? Theme.errorContainer : (btnArea.pressed ? Theme.secondaryContainer : (btnArea.containsMouse ? Theme.surfaceContainerHighest : "transparent"))
            border.color: root.isMuted ? Theme.alertRed : (btnArea.containsMouse ? Theme.outlineVariant : "transparent")
            border.width: 1

            scale: btnArea.pressed ? 0.9 : 1.0
            Behavior on scale {
                NumberAnimation { duration: 150; easing.type: Easing.OutBack }
            }
            Behavior on color {
                ColorAnimation { duration: 150 }
            }

            // System App Icon if available
            IconImage {
                id: sysIcon
                anchors.centerIn: parent
                implicitSize: 24
                visible: root.iconName !== "" && status === Image.Ready
                source: root.iconName !== "" ? (root.iconName.includes("/") ? root.iconName : Quickshell.iconPath(root.iconName, true)) : ""
            }

            // Clean Material 3 style icon fallback
            Text {
                anchors.centerIn: parent
                visible: !sysIcon.visible
                text: root.getFallbackIcon()
                color: root.isMuted ? Theme.colorOnErrorContainer : (btnArea.containsMouse ? Theme.primary : Theme.colorOnSurfaceVariant)
                font.family: Theme.iconFamily
                font.pixelSize: 20
                renderType: Text.NativeRendering

                Behavior on color {
                    ColorAnimation { duration: 150 }
                }
            }

            MouseArea {
                id: btnArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleMute()
            }
        }

        // 2. Slider Details Column
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - muteBtn.width - rowContainer.spacing
            spacing: 6

            // Top Row: Title, Subtitle, and Percentage
            Row {
                width: parent.width

                Text {
                    id: titleText
                    width: parent.width - percentText.implicitWidth - 8
                    text: root.title !== "" ? root.title : (root.node ? (root.node.description || root.node.name) : "Audio Stream")
                    color: Theme.colorOnSurface
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    elide: Text.ElideRight
                    renderType: Text.NativeRendering
                }

                Text {
                    id: percentText
                    text: root.isMuted ? "Muted" : Math.round(root.currentVolume * 100) + "%"
                    color: root.isMuted ? Theme.alertRed : Theme.colorOnSurfaceVariant
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                    horizontalAlignment: Text.AlignRight
                    renderType: Text.NativeRendering

                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }
                }
            }

            // Material Design 3 Slider Track Area
            Item {
                id: sliderArea
                width: parent.width
                height: 32

                readonly property real trackHeight: 16
                readonly property real thumbWidth: 4
                readonly property real thumbHeight: 30
                readonly property real gapSize: 6

                readonly property real valRatio: Math.max(0.0, Math.min(1.0, root.currentVolume / root.maxVolume))
                readonly property real thumbCenterX: Math.max(thumbWidth / 2, Math.min(width - thumbWidth / 2, valRatio * width))

                readonly property real activeTrackWidth: Math.max(0, thumbCenterX - (thumbWidth / 2) - gapSize)
                readonly property real inactiveTrackStart: Math.min(width, thumbCenterX + (thumbWidth / 2) + gapSize)
                readonly property real inactiveTrackWidth: Math.max(0, width - inactiveTrackStart)

                function getDotColor(dotX) {
                    if (dotX <= sliderArea.activeTrackWidth) {
                        return root.isMuted ? Theme.colorOnSurfaceVariant : Theme.colorOnPrimary;
                    } else {
                        return root.isMuted ? Theme.colorOnSurfaceVariant : Theme.colorOnSecondaryContainer;
                    }
                }

                // Inactive Background Track (Material 3 Secondary Container)
                Rectangle {
                    id: inactiveTrack
                    x: sliderArea.inactiveTrackStart
                    anchors.verticalCenter: parent.verticalCenter
                    width: sliderArea.inactiveTrackWidth
                    height: sliderArea.trackHeight
                    radius: height / 2
                    color: Theme.secondaryContainer

                    Behavior on x {
                        enabled: !sliderMouse.drag.active && !sliderMouse.pressed
                        NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
                    }
                    Behavior on width {
                        enabled: !sliderMouse.drag.active && !sliderMouse.pressed
                        NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
                    }
                }

                // Active Filled Track (Material 3 Primary Pill)
                Rectangle {
                    id: activeTrack
                    x: 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: sliderArea.activeTrackWidth
                    height: sliderArea.trackHeight
                    radius: height / 2
                    color: root.isMuted ? Theme.outlineVariant : Theme.primary

                    Behavior on width {
                        enabled: !sliderMouse.drag.active && !sliderMouse.pressed
                        NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
                    }
                }

                // =====================================================
                // Material Design 3 Stop Indicator Dots:
                // 1. Beginning (0%)
                // 2. 100% point (normal full volume)
                // 3. 150% point (amplified boost maximum / end)
                // =====================================================

                // Dot 1: Beginning (0%)
                Rectangle {
                    id: dotStart
                    readonly property real centerX: sliderArea.trackHeight / 2
                    x: centerX - 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 4
                    height: 4
                    radius: 2
                    color: sliderArea.getDotColor(centerX)
                    z: 2
                    opacity: 0.9

                    Behavior on color {
                        ColorAnimation { duration: 120 }
                    }
                }

                // Dot 2: 100% volume point (normal maximum)
                Rectangle {
                    id: dot100
                    readonly property real centerX: Math.round((1.0 / root.maxVolume) * sliderArea.width)
                    x: centerX - 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 4
                    height: 4
                    radius: 2
                    color: sliderArea.getDotColor(centerX)
                    z: 2
                    visible: root.maxVolume > 1.05
                    opacity: 0.9

                    Behavior on color {
                        ColorAnimation { duration: 120 }
                    }
                }

                // Dot 3: End point (150% boost maximum)
                Rectangle {
                    id: dotEnd
                    readonly property real centerX: sliderArea.width - (sliderArea.trackHeight / 2)
                    x: centerX - 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 4
                    height: 4
                    radius: 2
                    color: sliderArea.getDotColor(centerX)
                    z: 2
                    opacity: 0.9

                    Behavior on color {
                        ColorAnimation { duration: 120 }
                    }
                }

                // Material 3 Vertical Bar Handle (Thumb)
                Rectangle {
                    id: thumb
                    anchors.verticalCenter: parent.verticalCenter
                    x: sliderArea.thumbCenterX - (width / 2)
                    width: sliderMouse.pressed ? 5 : sliderArea.thumbWidth
                    height: sliderMouse.pressed ? 34 : sliderArea.thumbHeight
                    radius: width / 2
                    color: root.isMuted ? Theme.outline : Theme.primary
                    z: 5

                    Behavior on x {
                        enabled: !sliderMouse.drag.active && !sliderMouse.pressed
                        NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
                    }
                    Behavior on width {
                        NumberAnimation { duration: 100 }
                    }
                    Behavior on height {
                        NumberAnimation { duration: 100 }
                    }
                }

                // MouseArea for Dragging & Clicking
                MouseArea {
                    id: sliderMouse
                    anchors.fill: parent
                    anchors.topMargin: -8
                    anchors.bottomMargin: -8
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    function updateFromPos(mouseX) {
                        const clampedX = Math.max(0, Math.min(sliderArea.width, mouseX));
                        const ratio = clampedX / sliderArea.width;
                        root.setVolume(ratio * root.maxVolume);
                    }

                    onPressed: mouse => updateFromPos(mouse.x)
                    onPositionChanged: mouse => {
                        if (pressed) updateFromPos(mouse.x);
                    }

                    onWheel: wheel => {
                        const step = 0.02 * root.maxVolume;
                        if (wheel.angleDelta.y > 0) {
                            root.setVolume(root.currentVolume + step);
                        } else if (wheel.angleDelta.y < 0) {
                            root.setVolume(root.currentVolume - step);
                        }
                    }
                }
            }
        }
    }
}
