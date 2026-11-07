import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import ".."

PanelWindow {
    id: root

    property var parentWindow: null
    screen: parentWindow ? parentWindow.screen : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)

    // Full-screen transparent backdrop to catch outside clicks
    anchors { top: true; bottom: true; left: true; right: true }
    visible: false
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-powermenu"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    property real progress: 0.0

    function open() {
        visible = true;
        closeAnim.stop();
        openAnim.restart();
        keyCatcher.forceActiveFocus();
    }
    function close() {
        openAnim.stop();
        closeAnim.restart();
    }
    function toggle() { visible && progress > 0 ? close() : open(); }

    // Same open/close animation as VolumeCenter
    NumberAnimation {
        id: openAnim; target: root; property: "progress"
        from: root.progress; to: 1.0; duration: 320
        easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id: closeAnim; target: root; property: "progress"
        from: root.progress; to: 0.0; duration: 250
        easing.type: Easing.InCubic
        onFinished: root.visible = false
    }

    readonly property var actions: [
        { label: "Power off", icon: "shutdown", file: "\uf8c7", cmd: ["systemctl", "poweroff"], final: true },
        { label: "Restart",   icon: "reboot", file: "\uf053", cmd: ["systemctl", "reboot"], final: true },
        { label: "Suspend",   icon: "suspend", file: "\uf159", cmd: ["systemctl", "suspend"] },
        { label: "Lock",      icon: "lock", file: "\ue899", cmd: ["quickshell", "ipc", "call", "lock", "lock"], instant: true }
    ]

    // --- Fullscreen expand animation -------------------------------
    property bool expanding: false
    property real expand: 0.0          // 0 = button rect, 1 = whole screen
    property real expanderOpacity: 1.0
    property rect fromRect: Qt.rect(0, 0, 0, 0)
    property int activeIndex: -1
    property real fromRadius: 26

    // Lock: hide the menu at once (so it isn't captured in the desktop snapshot the
    // lockscreen fades back into), then fire the lock.
    Timer {
        id: instantTimer
        interval: 150
        onTriggered: Quickshell.execDetached(root.actions[root.activeIndex].cmd)
    }

    function run(i, item) {
        if (expanding) return;
        if (actions[i].instant) {
            openAnim.stop(); closeAnim.stop();
            activeIndex = i;
            progress = 0;
            visible = false;
            instantTimer.start();
            return;
        }
        const p = item.mapToItem(root.contentItem, 0, 0);
        fromRect = Qt.rect(p.x, p.y, item.width, item.height);
        fromRadius = item.radius;
        activeIndex = i;
        expanderOpacity = 1.0;
        expand = 0.0;
        expanding = true;
        runAnim.restart();
    }

    function reset() {
        expanding = false;
        expand = 0.0;
        expanderOpacity = 1.0;
        activeIndex = -1;
        visible = false;
        progress = 0.0;
    }

    SequentialAnimation {
        id: runAnim
        // MD3 "emphasized" easing
        NumberAnimation {
            target: root; property: "expand"; to: 1.0; duration: 500
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.2, 0.0, 0.0, 1.0, 1.0, 1.0]
        }
        ScriptAction {
            script: {
                const a = root.actions[root.activeIndex];
                Quickshell.execDetached(a.cmd);
                // poweroff/reboot: stay covered until the session dies
                if (!a.final) fadeAnim.restart();
            }
        }
    }

    // Lock/suspend: the cover only needs to hide the desktop until the lock
    // screen is drawn. It goes away *while locked* (the lock surface sits above
    // it), so nothing is left over after unlocking.
    SequentialAnimation {
        id: fadeAnim
        PauseAnimation { duration: 600 }
        NumberAnimation { target: root; property: "expanderOpacity"; to: 0.0; duration: 250; easing.type: Easing.OutCubic }
        ScriptAction { script: root.reset() }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: { if (!root.expanding) root.close() }
    }

    Item {
        id: keyCatcher
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape && !root.expanding) { root.close(); event.accepted = true; }
        }
    }

    Rectangle {
        id: panel
        // slides in from the left edge (mirrors VolumeCenter's slide from the right)
        x: 33 - (1.0 - root.progress) * (width + 30)
        y: 43
        width: 280
        height: 280
        radius: 28
        color: Theme.surfaceContainer
        border.color: Theme.outlineVariant
        border.width: 1

        opacity: root.progress * (1.0 - Math.min(1.0, root.expand * 3))

        // swallow clicks inside the panel
        MouseArea { anchors.fill: parent; onPressed: mouse => mouse.accepted = true }

        Grid {
            anchors.fill: parent
            anchors.margins: 14
            columns: 2
            spacing: 12

            Repeater {
                model: root.actions

                delegate: Rectangle {
                    id: btn
                    required property int index
                    required property var modelData
                    readonly property bool danger: modelData.icon === "shutdown"

                    width: (panel.width - 28 - 12) / 2
                    height: (panel.height - 28 - 12) / 2
                    radius: btnMouse.containsMouse ? 20 : 26
                    color: btnMouse.pressed
                        ? (danger ? Theme.error : Theme.primary)
                        : btnMouse.containsMouse
                            ? (danger ? Theme.errorContainer : Theme.primaryContainer)
                            : Theme.surfaceContainerHigh

                    readonly property color fg: btnMouse.pressed
                        ? (danger ? Theme.colorOnError : Theme.colorOnPrimary)
                        : btnMouse.containsMouse
                            ? (danger ? Theme.colorOnErrorContainer : Theme.colorOnPrimaryContainer)
                            : Theme.colorOnSurface

                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on radius { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                    Column {
                        anchors.centerIn: parent

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: btn.modelData.file
                            color: btn.fg
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 57
                            font.variableAxes: { "FILL": 0 }
                            renderType: Text.NativeRendering
                        }
                    }

                    MouseArea {
                        id: btnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.run(btn.index, btn)
                    }
                }
            }
        }
    }

    // Expanding surface: grows from the pressed button to cover the screen
    Rectangle {
        id: expander
        visible: root.expanding
        opacity: root.expanderOpacity
        readonly property real e: root.expand
        x: root.fromRect.x * (1 - e)
        y: root.fromRect.y * (1 - e)
        width: root.fromRect.width + (root.width - root.fromRect.width) * e
        height: root.fromRect.height + (root.height - root.fromRect.height) * e
        radius: root.fromRadius * (1 - e)
        color: Qt.tint(Theme.primaryContainer, Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, e))

        Column {
            anchors.centerIn: parent
            spacing: 12
            opacity: Math.min(1.0, expander.e * 2)

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.activeIndex >= 0 ? root.actions[root.activeIndex].file : ""
                color: Theme.colorOnSurface
                font.family: "Material Symbols Rounded"
                font.pixelSize: 57 + 57 * expander.e
                font.variableAxes: { "FILL": 0 }
                renderType: Text.NativeRendering
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.activeIndex >= 0 ? root.actions[root.activeIndex].label : ""
                color: Theme.colorOnSurface
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 4 * expander.e
                font.bold: true
                renderType: Text.NativeRendering
            }
        }
    }
}
