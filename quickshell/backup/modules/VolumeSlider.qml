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
    implicitHeight: 64

    function setVolume(val) {
        const clamped = Math.max(0.0, Math.min(root.maxVolume, val));
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
        spacing: 14

        // 1. Smart Mute / App Icon Button (matching the magenta rounded square in Figma)
        Rectangle {
            id: muteBtn
            width: 44
            height: 44
            anchors.verticalCenter: parent.verticalCenter
            radius: 12
            color: root.isMuted ? Theme.secondary : Theme.foreground
            opacity: root.isMuted ? 0.35 : 0.95

            scale: btnArea.pressed ? 0.92 : (btnArea.containsMouse ? 1.05 : 1.0)
            Behavior on scale {
                NumberAnimation { duration: 150; easing.type: Easing.OutBack }
            }
            Behavior on color {
                ColorAnimation { duration: 150 }
            }
            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }

            // System App Icon if available
            IconImage {
                id: sysIcon
                anchors.centerIn: parent
                implicitSize: 24
                visible: root.iconName !== "" && status === Image.Ready
                source: root.iconName !== "" ? (root.iconName.includes("/") ? root.iconName : Quickshell.iconPath(root.iconName, true)) : ""
            }

            // Font/Symbol icon fallback
            Text {
                anchors.centerIn: parent
                visible: !sysIcon.visible
                text: root.getFallbackIcon()
                color: Theme.background
                font.family: Theme.iconFamily
                font.pixelSize: 20
                renderType: Text.NativeRendering
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
            spacing: 5

            // Top Row: Title, Subtitle, and Percentage
            Row {
                width: parent.width

                Text {
                    id: titleText
                    width: parent.width - percentText.implicitWidth - 8
                    text: root.title !== "" ? root.title : (root.node ? (root.node.description || root.node.name) : "Audio Stream")
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    elide: Text.ElideRight
                    renderType: Text.NativeRendering
                }

                Text {
                    id: percentText
                    text: root.isMuted ? "Muted" : Math.round(root.currentVolume * 100) + "%"
                    color: root.isMuted ? Theme.secondary : Theme.foreground
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

            // Slider Track Area
            Item {
                id: sliderArea
                width: parent.width
                height: 22

                // Inactive Background Track (Theme.secondary with transparency)
                Rectangle {
                    id: baseTrack
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 5
                    radius: 2.5
                    color: Theme.secondary
                    opacity: 0.35
                }

                // Active Filled Track (Theme.foreground)
                Rectangle {
                    id: fillTrack
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: baseTrack.left
                    height: 5
                    radius: 2.5
                    color: Theme.foreground
                    width: Math.max(0, Math.min(baseTrack.width, (root.currentVolume / root.maxVolume) * baseTrack.width))

                    Behavior on width {
                        enabled: !sliderMouse.drag.active && !sliderMouse.pressed
                        NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
                    }
                }

                // Figma Stylized Thumb: A vertical rounded pill crossing the horizontal track
                Rectangle {
                    id: thumb
                    width: 4
                    height: 18
                    radius: 2
                    color: Theme.foreground
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.max(0, Math.min(sliderArea.width - width, (root.currentVolume / root.maxVolume) * sliderArea.width - (width / 2)))

                    scale: sliderMouse.containsMouse || sliderMouse.pressed ? 1.25 : 1.0
                    Behavior on scale {
                        NumberAnimation { duration: 120; easing.type: Easing.OutBack }
                    }
                    Behavior on x {
                        enabled: !sliderMouse.drag.active && !sliderMouse.pressed
                        NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
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

            // Figma Labels: 0, 100, 150 positioned under the track
            Item {
                width: parent.width
                height: 14

                // "0" at start
                Text {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    text: "0"
                    color: Theme.secondary
                    opacity: 0.65
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    renderType: Text.NativeRendering
                }

                // "100" at (1.0 / maxVolume) position (~66.7%)
                Text {
                    x: Math.round((1.0 / root.maxVolume) * parent.width - (implicitWidth / 2))
                    anchors.top: parent.top
                    text: "100"
                    color: Theme.secondary
                    opacity: 0.65
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    renderType: Text.NativeRendering
                }

                // "150" at end
                Text {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    text: "150"
                    color: Theme.secondary
                    opacity: 0.65
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    renderType: Text.NativeRendering
                }
            }
        }
    }
}
