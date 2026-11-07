import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import ".."

// Wallpaper picker: horizontal carousel of thumbnails (no file names).
// Replaces ~/scripts/matugen_rofi_walls.sh.   quickshell ipc call wallpaper toggle
PanelWindow {
    id: root

    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    anchors { top: true; bottom: true; left: true; right: true }
    visible: false
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-wallpapers"
    WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    readonly property string home: Quickshell.env("HOME") || "/home/chizuko"
    readonly property string wallsDir: home + "/Pictures/wallpapers/W39"
    readonly property string currentLink: home + "/.config/hypr/current_wallpaper"

    property bool isOpen: false
    property real animProgress: 0.0
    property double lastCloseTime: 0

    property var files: []
    property var filesTmp: []
    property string currentPath: ""

    // ---- open / close ----------------------------------------------------
    function open() {
        if (isOpen && visible) return;
        isOpen = true;
        visible = true;
        reload();
        closeAnim.stop();
        openAnim.restart();
        keys.forceActiveFocus();
    }
    function close() {
        if (!isOpen && !visible) return;
        isOpen = false;
        lastCloseTime = Date.now();
        openAnim.stop();
        closeAnim.restart();
    }
    function toggle() {
        if (isOpen) close();
        else {
            if (Date.now() - lastCloseTime < 200) return;
            open();
        }
    }

    NumberAnimation { id: openAnim; target: root; property: "animProgress"; from: root.animProgress; to: 1.0; duration: 320; easing.type: Easing.OutCubic }
    NumberAnimation {
        id: closeAnim; target: root; property: "animProgress"; from: root.animProgress; to: 0.0; duration: 250; easing.type: Easing.InCubic
        onFinished: if (!root.isOpen) root.visible = false
    }

    HyprlandFocusGrab {
        windows: [root]
        active: root.isOpen
        onCleared: root.close()
    }

    IpcHandler {
        target: "wallpaper"
        function toggle(): void { root.toggle(); }
        function open(): void { root.open(); }
        function close(): void { root.close(); }
    }

    // ---- data ------------------------------------------------------------
    Process {
        id: curProc
        command: ["readlink", "-f", root.currentLink]
        stdout: SplitParser { onRead: data => { root.currentPath = data.trim(); } }
        onRunningChanged: if (!running) root.focusCurrent()
    }

    Process {
        id: listProc
        command: ["bash", "-c", "find \"" + root.wallsDir + "\" -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) | sort"]
        stdout: SplitParser {
            onRead: data => { if (data.trim() !== "") root.filesTmp.push(data.trim()); }
        }
        onRunningChanged: {
            if (!running) {
                root.files = root.filesTmp;
                curProc.running = false;
                curProc.running = true;
            }
        }
    }

    function reload() {
        filesTmp = [];
        listProc.running = false;
        listProc.running = true;
    }

    function focusCurrent() {
        // wait a tick so the ListView has built its model before we move to an index
        focusTimer.restart();
    }
    Timer {
        id: focusTimer
        interval: 60
        onTriggered: {
            const i = root.files.indexOf(root.currentPath);
            list.currentIndex = i >= 0 ? i : 0;
            list.positionViewAtIndex(list.currentIndex, ListView.Center);
        }
    }

    // Same steps as the old rofi script: set wallpaper, regenerate colours, update symlink, restart swaync
    function apply(path) {
        if (!path || popping) return;
        const script =
            'awww img "$1" --transition-type grow --transition-duration 0.85 --transition-fps 144 --transition-angle 45; ' +
            'matugen image "$1" --source-color-index 0; ' +
            'ln -sf "$1" "$HOME/.config/hypr/current_wallpaper"; ' +
            'killall -9 swaync; setsid swaync >/dev/null 2>&1 &';
        Quickshell.execDetached(["bash", "-c", script, "--", path]);
        currentPath = path;
        // chosen thumbnail grows, settles back to normal size, then the picker drops away
        popping = true;
        popAnim.restart();
    }

    property bool popping: false
    property real popScale: 1.0
    SequentialAnimation {
        id: popAnim
        NumberAnimation { target: root; property: "popScale"; to: 1.16; duration: 170; easing.type: Easing.OutQuart }
        NumberAnimation { target: root; property: "popScale"; to: 1.0; duration: 230; easing.type: Easing.OutCubic }
        ScriptAction { script: root.close() }
    }
    onVisibleChanged: if (!visible) { popping = false; popScale = 1.0; }

    // ---- backdrop + dialog ---------------------------------------------------
    MouseArea {
        anchors.fill: parent
        onPressed: mouse => { root.close(); mouse.accepted = true; }
    }

    Rectangle {
        id: dialog
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(root.width - 120, 1500)
        height: 390
        radius: 28
        color: Theme.surfaceContainer
        border.color: Theme.outlineVariant
        border.width: 1
        clip: true

        readonly property real targetY: Math.round((root.height - height) / 2)
        y: targetY + (1.0 - root.animProgress) * (root.height - targetY + 40)
        opacity: root.animProgress

        MouseArea { anchors.fill: parent; onPressed: mouse => { mouse.accepted = true; } }

        // keyboard
        Item {
            id: keys
            focus: true
            Keys.onLeftPressed: event => { event.accepted = true; list.decrementCurrentIndex(); }
            Keys.onRightPressed: event => { event.accepted = true; list.incrementCurrentIndex(); }
            Keys.onReturnPressed: event => { event.accepted = true; root.apply(root.files[list.currentIndex]); }
            Keys.onEnterPressed: event => { event.accepted = true; root.apply(root.files[list.currentIndex]); }
            Keys.onEscapePressed: event => { event.accepted = true; root.close(); }
        }

        ListView {
            id: list
            anchors.fill: parent
            anchors.topMargin: 36
            anchors.bottomMargin: 36
            orientation: ListView.Horizontal
            spacing: 18
            model: root.files
            boundsBehavior: Flickable.StopAtBounds
            clip: false      // dialog clips; lets the glow spill above/below the cards

            // selected thumbnail stays centred; the strip glides under it
            highlightRangeMode: ListView.StrictlyEnforceRange
            preferredHighlightBegin: width / 2 - 204
            preferredHighlightEnd: width / 2 + 204
            highlightMoveDuration: 224
            highlightMoveVelocity: -1
            snapMode: ListView.NoSnap
            leftMargin: width / 2 - 204
            rightMargin: width / 2 - 204

            // mouse wheel steps through wallpapers
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    const d = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                    if (d > 0) list.decrementCurrentIndex();
                    else if (d < 0) list.incrementCurrentIndex();
                }
            }

            delegate: Item {
                id: cell
                required property string modelData
                required property int index
                readonly property bool isSel: ListView.isCurrentItem
                readonly property bool isCurrent: modelData === root.currentPath

                width: 408
                height: list.height

                // selection size is smoothed; the pop is applied on top, unsmoothed, so it is actually visible
                property real selScale: isSel ? 1.0 : 0.86
                Behavior on selScale { NumberAnimation { duration: 196; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0.0, 0.0, 1.0, 1.0, 1.0] } }
                scale: selScale * (isSel ? root.popScale : 1.0)
                opacity: isSel ? 1.0 : 0.7
                Behavior on opacity { NumberAnimation { duration: 200 } }

                // soft glow around the wallpaper that is currently set
                Rectangle {
                    id: glowSrc
                    anchors.fill: parent
                    anchors.margins: 4
                    radius: 22
                    color: Theme.primary
                    visible: false
                    layer.enabled: true
                }
                MultiEffect {
                    anchors.fill: parent
                    source: glowSrc
                    visible: cell.isCurrent
                    autoPaddingEnabled: true
                    shadowEnabled: true
                    shadowColor: Theme.primary
                    shadowBlur: 0.45
                    shadowOpacity: 0.5
                    shadowScale: 1.02
                }

                // thumbnail, clipped to a rounded rectangle
                Item {
                    id: thumbHost
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    Image {
                        id: img
                        anchors.fill: parent
                        source: "file://" + cell.modelData
                        sourceSize.height: 480          // decode small: the originals are up to 5000 px
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        smooth: true
                    }
                }
                Rectangle { id: thumbMask; anchors.fill: parent; radius: 22; visible: false; layer.enabled: true }
                Rectangle {
                    anchors.fill: parent
                    radius: 22
                    color: Theme.surfaceContainerHigh      // placeholder while the image loads
                    visible: img.status !== Image.Ready
                }
                MultiEffect {
                    anchors.fill: parent
                    source: thumbHost
                    maskEnabled: true
                    maskSource: thumbMask
                    visible: img.status === Image.Ready
                }

                // selection ring
                Rectangle {
                    anchors.fill: parent
                    radius: 22
                    color: "transparent"
                    border.width: cell.isSel ? 4 + (root.popScale - 1.0) * 30 : 0
                    border.color: Theme.primary
                    Behavior on border.width { enabled: !root.popping; NumberAnimation { duration: 180 } }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (cell.isSel) root.apply(cell.modelData);
                        else list.currentIndex = cell.index;
                    }
                    onDoubleClicked: root.apply(cell.modelData)
                }
            }
        }
    }
}
