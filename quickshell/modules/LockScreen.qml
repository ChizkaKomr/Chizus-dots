import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import ".."

// Native Quickshell lockscreen (ext-session-lock). Replaces hyprlock.
//   quickshell ipc call lock lock
Scope {
    id: root

    readonly property string home: Quickshell.env("HOME") || "/home/chizuko"
    readonly property string userName: Quickshell.env("USER") || "user"
    readonly property string wallpaper: "file://" + home + "/.config/hypr/current_wallpaper"

    // ---- shared auth state (all monitors show the same input) ----------
    property string password: ""
    property bool busy: false
    property bool failed: false

    // ---- unlock exit animation ---------------------------------------------
    property bool unlocking: false
    property real exitProg: 1      // 0..1  elements flying off to the sides (1 = off-screen)
    property real unblur: 1        // 0..1  1 = clear desktop, 0 = fully blurred lockscreen

    function finishUnlock() {
        root.stopCava();
        lock.locked = false;
        Quickshell.execDetached(["sh", "-c", "rm -f /tmp/qs-lock-" + root.shotId + "-*.png"]);
        root.unlocking = false;
        root.exitProg = 1;
        root.unblur = 1;
    }

    ParallelAnimation {
        id: exitAnim
        NumberAnimation {
            target: root; property: "unblur"; from: 0; to: 1; duration: 500
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root; property: "exitProg"; from: 0; to: 1; duration: 320
            easing.type: Easing.InOutQuart      // slow start, fast middle, slow end (the S-curve)
        }
        onFinished: root.finishUnlock()
    }

    // ---- lock animation: the unlock animation played in reverse ------------
    function playEnter() {
        exitAnim.stop();
        unlocking = false;
        exitProg = 1;
        unblur = 1;
        enterAnim.restart();
    }

    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: root; property: "unblur"; from: 1; to: 0; duration: 500; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "exitProg"; from: 1; to: 0; duration: 320; easing.type: Easing.InOutQuart }
    }

    function submit() {
        if (busy || unlocking || password === "") return;
        failed = false;
        busy = true;
        pam.start();
    }

    PamContext {
        id: pam
        config: "hyprlock"          // /etc/pam.d/hyprlock -> includes login
        user: root.userName

        onPamMessage: {
            if (responseRequired) respond(root.password);
        }
        onCompleted: result => {
            root.busy = false;
            root.password = "";
            if (result === PamResult.Success) {
                root.failed = false;
                root.unlocking = true;       // play the exit animation, then really unlock
                exitAnim.restart();
            } else {
                root.failed = true;
            }
        }
    }

    // ---- cava audio data (only runs while locked) ------------------------
    property var bars: []
    Process {
        id: cava
        running: false
        command: ["cava", "-p", root.home + "/.config/quickshell/cava_lock.conf"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                const parts = data.split(";");
                const out = [];
                for (let i = 0; i < parts.length; i++) {
                    if (parts[i] === "") continue;
                    out.push(Math.min(100, parseInt(parts[i])) / 100);
                }
                if (out.length > 0) root.bars = out;
            }
        }
    }

    // onLockedChanged never fires for the unlock direction, so stop cava explicitly.
    function stopCava() {
        cava.running = false;
        Quickshell.execDetached(["pkill", "-KILL", "-f", "cava_lock.conf"]);
    }

    // ---- desktop snapshot, so the unlock animation can fade into the real screen ----
    property string shotId: ""

    Process {
        id: snap
        onExited: lock.locked = true     // lock whether or not grim succeeded
    }

    function startLock() {
        if (lock.locked || snap.running) return;
        shotId = String(Date.now());
        const grabs = Quickshell.screens.map(sc =>
            "grim -o '" + sc.name + "' /tmp/qs-lock-" + shotId + "-" + sc.name + ".png");
        snap.command = ["sh", "-c", grabs.join(" & ") + " & wait"];
        snap.running = true;
    }

    IpcHandler {
        target: "lock"
        function lock(): void { root.startLock(); }
        function isLocked(): bool { return lock.locked; }
    }

    WlSessionLock {
        id: lock
        locked: false
        onLockedChanged: {
            cava.running = locked;
            if (locked) { root.password = ""; root.failed = false; root.busy = false; root.bars = []; }
        }

        WlSessionLockSurface {
            id: surface
            color: Theme.surface
            Component.onCompleted: root.playEnter()

            // ---------- Wallpaper, blurred + dimmed -----------------------
            Image {
                id: wall
                anchors.fill: parent
                source: root.wallpaper
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: false
            }
            MultiEffect {
                anchors.fill: parent
                source: wall
                blurEnabled: true
                blur: 1.0 - root.unblur
                blurMax: 64
                brightness: -0.12
                saturation: -0.1
            }
            Rectangle {
                anchors.fill: parent
                color: Theme.surface
                opacity: 0.55 * (1.0 - root.unblur)
            }

            // ---------- Real desktop (snapshot taken at lock time), fades in on unlock
            Image {
                anchors.fill: parent
                source: (root.shotId !== "" && surface.screen) ? "file:///tmp/qs-lock-" + root.shotId + "-" + surface.screen.name + ".png" : ""
                fillMode: Image.PreserveAspectCrop
                cache: false
                visible: status === Image.Ready
                opacity: root.unblur
            }

            // ---------- Blurred cava visualizer on both sides -------------
            Item {
                id: vizLayer
                anchors.fill: parent
                opacity: 1.0 - root.unblur
                layer.enabled: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: 0.6
                    blurMax: 48
                }

                // bars start this far behind the screen edge, so at silence they (and their
                // blur halo) are fully hidden and only peek out when there is sound
                readonly property real tuck: 30

                Repeater {
                    model: root.bars.length
                    delegate: Item {
                        required property int index
                        readonly property real v: root.bars[index] || 0
                        readonly property real slot: vizLayer.height / root.bars.length

                        // left edge
                        Rectangle {
                            x: -vizLayer.tuck
                            y: index * slot + slot * 0.12
                            height: slot * 0.76
                            width: 24 + v * vizLayer.width * 0.22
                            radius: height / 2
                            color: Theme.primary
                            opacity: 0.35 + 0.4 * v
                            Behavior on width { NumberAnimation { duration: 70 } }
                        }
                        // right edge
                        Rectangle {
                            height: slot * 0.76
                            width: 24 + v * vizLayer.width * 0.22
                            x: vizLayer.width - width + vizLayer.tuck
                            y: index * slot + slot * 0.12
                            radius: height / 2
                            color: Theme.tertiary
                            opacity: 0.35 + 0.4 * v
                            Behavior on width { NumberAnimation { duration: 70 } }
                        }
                    }
                }
            }

            // ---------- Content --------------------------------------------
            Item {
                id: content
                anchors.fill: parent

                property var now: new Date()
                Timer { interval: 1000; running: true; repeat: true; onTriggered: content.now = new Date() }

                Row {
                    anchors.centerIn: parent
                    spacing: 72

                    // ---- Clock + date --------------------------------------
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 24
                        transform: Translate { x: -root.exitProg * (surface.width / 2 + 400) }

                        Column {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: -28
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Qt.formatTime(content.now, "HH")
                                color: Theme.primary
                                font.family: "Helvetica Rounded"
                                font.pixelSize: 190
                                font.bold: true
                                renderType: Text.NativeRendering
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Qt.formatTime(content.now, "mm")
                                color: Theme.colorOnSurface
                                font.family: "Helvetica Rounded"
                                font.pixelSize: 190
                                font.bold: true
                                renderType: Text.NativeRendering
                            }
                        }

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            implicitWidth: dateText.implicitWidth + 40
                            implicitHeight: 40
                            radius: 20
                            color: Theme.primaryContainer
                            Text {
                                id: dateText
                                anchors.centerIn: parent
                                text: Qt.formatDate(content.now, "dddd, MMM d").toUpperCase()
                                color: Theme.colorOnPrimaryContainer
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                                font.bold: true
                                font.letterSpacing: 1
                                renderType: Text.NativeRendering
                            }
                        }
                    }

                    // ---- Quick settings + unlock card ----------------------
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 420
                        spacing: 14
                        transform: Translate { x: root.exitProg * (surface.width / 2 + 500) }

                        Text {
                            leftPadding: 6
                            text: "QUICK SETTINGS"
                            color: Theme.colorOnSurfaceVariant
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.letterSpacing: 1.5
                            renderType: Text.NativeRendering
                        }

                        Grid {
                            columns: 2
                            spacing: 12

                            component QuickButton: Rectangle {
                                id: qb
                                property string glyph
                                property string title
                                property string subtitle
                                property var cmd
                                width: 204; height: 64
                                radius: 32
                                color: qbMouse.pressed ? Theme.primary
                                     : qbMouse.containsMouse ? Theme.primaryContainer
                                     : Theme.surfaceContainerHigh
                                Behavior on color { ColorAnimation { duration: 150 } }

                                readonly property color fg: qbMouse.pressed ? Theme.colorOnPrimary
                                    : qbMouse.containsMouse ? Theme.colorOnPrimaryContainer : Theme.colorOnSurface

                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 12
                                    spacing: 12
                                    Rectangle {
                                        width: 40; height: 40; radius: 20
                                        color: Theme.secondaryContainer
                                        anchors.verticalCenter: parent.verticalCenter
                                        Text {
                                            anchors.centerIn: parent
                                            text: qb.glyph
                                            color: Theme.colorOnSecondaryContainer
                                            font.family: "Material Symbols Rounded"
                                            font.pixelSize: 22
                                            font.variableAxes: { "FILL": 0 }
                                        }
                                    }
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        Text {
                                            text: qb.title
                                            color: qb.fg
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 14
                                            font.bold: true
                                            renderType: Text.NativeRendering
                                        }
                                        Text {
                                            text: qb.subtitle
                                            color: qb.fg
                                            opacity: 0.7
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            renderType: Text.NativeRendering
                                        }
                                    }
                                }
                                MouseArea {
                                    id: qbMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Quickshell.execDetached(qb.cmd)
                                }
                            }

                            QuickButton { glyph: ""; title: "Power"; subtitle: "Shut down"; cmd: ["systemctl", "poweroff"] }
                            QuickButton { glyph: ""; title: "Reboot"; subtitle: "Restart"; cmd: ["systemctl", "reboot"] }
                            QuickButton { glyph: ""; title: "Session"; subtitle: "Log out"; cmd: ["hyprshutdown", "--no-fork"] }
                            QuickButton { glyph: ""; title: "Sleep"; subtitle: "Suspend"; cmd: ["systemctl", "suspend"] }
                        }

                        // ---- Unlock card -----------------------------------
                        Rectangle {
                            width: parent.width
                            height: cardCol.implicitHeight + 32
                            radius: 28
                            color: Theme.surfaceContainer
                            opacity: 0.96

                            Column {
                                id: cardCol
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 12

                                Row {
                                    spacing: 6
                                    Text {
                                        text: ""
                                        color: Theme.colorOnSurfaceVariant
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: 15
                                        font.variableAxes: { "FILL": 0 }
                                    }
                                    Text {
                                        text: root.failed ? "INCORRECT PASSWORD" : (root.busy ? "CHECKING…" : "LOCKED")
                                        color: root.failed ? Theme.error : Theme.colorOnSurfaceVariant
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.letterSpacing: 1.2
                                        renderType: Text.NativeRendering
                                    }
                                }

                                // password field
                                Rectangle {
                                    id: field
                                    width: parent.width
                                    height: 52
                                    radius: 26
                                    color: Theme.surfaceContainerHighest
                                    border.width: 2
                                    border.color: root.failed ? Theme.error : (input.activeFocus ? Theme.primary : Theme.outlineVariant)
                                    Behavior on border.color { ColorAnimation { duration: 150 } }

                                    transform: Translate { id: shake; x: 0 }
                                    SequentialAnimation {
                                        id: shakeAnim
                                        NumberAnimation { target: shake; property: "x"; to: -12; duration: 50 }
                                        NumberAnimation { target: shake; property: "x"; to: 12; duration: 80 }
                                        NumberAnimation { target: shake; property: "x"; to: -8; duration: 70 }
                                        NumberAnimation { target: shake; property: "x"; to: 0; duration: 60 }
                                    }
                                    Connections {
                                        target: root
                                        function onFailedChanged() { if (root.failed) shakeAnim.restart(); }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: input.text.length === 0
                                        text: "PASSWORD REQUIRED"
                                        color: Theme.colorOnSurfaceVariant
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.letterSpacing: 1.5
                                        renderType: Text.NativeRendering
                                    }

                                    // Animated password dots: each one pops in as you type and
                                    // shrinks away when deleted; neighbours glide to re-centre.
                                    ListModel { id: dotModel }

                                    function syncDots() {
                                        const want = Math.min(root.password.length, 18);
                                        let alive = 0;
                                        for (let i = 0; i < dotModel.count; i++)
                                            if (!dotModel.get(i).dying) alive++;
                                        while (alive < want) { dotModel.append({ dying: false }); alive++; }
                                        while (alive > want) {
                                            for (let j = dotModel.count - 1; j >= 0; j--) {
                                                if (!dotModel.get(j).dying) { dotModel.setProperty(j, "dying", true); break; }
                                            }
                                            alive--;
                                        }
                                    }
                                    Connections {
                                        target: root
                                        function onPasswordChanged() { field.syncDots(); }
                                    }

                                    Row {
                                        id: dotsRow
                                        spacing: 8
                                        height: 16
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: (parent.width - width) / 2
                                        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                        move: Transition { NumberAnimation { properties: "x"; duration: 220; easing.type: Easing.OutCubic } }

                                        Repeater {
                                            model: dotModel
                                            delegate: Item {
                                                id: d
                                                required property int index
                                                required property bool dying
                                                property bool shown: false
                                                width: 14; height: 16
                                                Component.onCompleted: shown = true

                                                Timer {
                                                    running: d.dying
                                                    interval: 200
                                                    onTriggered: dotModel.remove(d.index)
                                                }

                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: 14; height: 14; radius: 7
                                                    color: root.failed ? Theme.error : Theme.colorOnSurface
                                                    scale: (d.shown && !d.dying) ? 1 : 0
                                                    opacity: (d.shown && !d.dying) ? 1 : 0
                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                    Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
                                                    Behavior on opacity { NumberAnimation { duration: 160 } }
                                                }
                                            }
                                        }
                                    }

                                    TextInput {
                                        id: input
                                        anchors.fill: parent
                                        anchors.leftMargin: 20
                                        anchors.rightMargin: 20
                                        verticalAlignment: TextInput.AlignVCenter
                                        horizontalAlignment: TextInput.AlignHCenter
                                        echoMode: TextInput.Password
                                        passwordCharacter: "●"
                                        // real text is invisible; the dots below are the visual
                                        color: "transparent"
                                        selectionColor: "transparent"
                                        cursorDelegate: Item {}
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 18
                                        enabled: !root.busy && !root.unlocking
                                        focus: true
                                        clip: true
                                        text: root.password
                                        onTextChanged: { root.password = text; if (text.length > 0) root.failed = false; }
                                        Connections {
                                            target: root
                                            function onPasswordChanged() { if (input.text !== root.password) input.text = root.password; }
                                        }
                                        onAccepted: root.submit()
                                        Keys.onEscapePressed: root.password = ""
                                        Component.onCompleted: forceActiveFocus()
                                    }
                                }

                                Row {
                                    width: parent.width
                                    spacing: 12

                                    Rectangle {
                                        height: 48
                                        width: userRow.implicitWidth + 32
                                        radius: 24
                                        color: Theme.secondaryContainer
                                        Row {
                                            id: userRow
                                            anchors.centerIn: parent
                                            spacing: 6
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: ""
                                                color: Theme.colorOnSecondaryContainer
                                                font.family: "Material Symbols Rounded"
                                                font.pixelSize: 18
                                                font.variableAxes: { "FILL": 0 }
                                            }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: root.userName.toUpperCase()
                                                color: Theme.colorOnSecondaryContainer
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                                font.bold: true
                                                font.letterSpacing: 1
                                                renderType: Text.NativeRendering
                                            }
                                        }
                                    }

                                    Rectangle {
                                        id: unlockBtn
                                        height: 48
                                        width: parent.width - x
                                        radius: unlockMouse.containsMouse ? 16 : 24
                                        color: unlockMouse.pressed ? Qt.darker(Theme.primary, 1.15) : Theme.primary
                                        opacity: root.password.length > 0 && !root.busy ? 1.0 : 0.6
                                        Behavior on radius { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 8
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "UNLOCK"
                                                color: Theme.colorOnPrimary
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 13
                                                font.bold: true
                                                font.letterSpacing: 1.5
                                                renderType: Text.NativeRendering
                                            }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: ""
                                                color: Theme.colorOnPrimary
                                                font.family: "Material Symbols Rounded"
                                                font.pixelSize: 18
                                                font.variableAxes: { "FILL": 0 }
                                            }
                                        }
                                        MouseArea {
                                            id: unlockMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.submit()
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
}
