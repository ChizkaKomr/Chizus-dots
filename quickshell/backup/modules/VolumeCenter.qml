import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import ".."

PanelWindow {
    id: root

    property var parentWindow: null
    property var targetItem: null
    screen: parentWindow ? parentWindow.screen : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)

    // Fill screen so any click outside the panel is caught and consumed
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    visible: false
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-volume"
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

    // Exact opening and closing animations from NotificationCenter
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

    // Fullscreen backdrop: absorbs any click outside the volume card so nothing underneath is triggered
    MouseArea {
        id: backdropArea
        anchors.fill: parent
        hoverEnabled: false
        onPressed: mouse => {
            root.close();
            mouse.accepted = true;
        }
    }

    VolumePanel {
        id: panel
        width: 440
        height: 520
        y: 50

        // Smooth sliding animation from right:
        // Starts completely off-screen to the right and glides in to rest at 12px from right edge
        x: (root.width - width - 12) + (1.0 - root.animProgress) * (width + 30)
        opacity: root.animProgress
    }
}
