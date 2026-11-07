import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import ".."

// App launcher — same look and behaviour as the clipboard manager.
//   quickshell ipc call launcher toggle
PanelWindow {
    id: root

    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    anchors { top: true; bottom: true; left: true; right: true }
    visible: false
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-launcher"
    WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    property bool isOpen: false
    property real animProgress: 0.0
    property double lastCloseTime: 0

    property var results: []
    property int selectedIndex: 0

    // ---- open / close --------------------------------------------------
    function open() {
        if (isOpen && visible) return;
        isOpen = true;
        visible = true;
        searchField.text = "";
        selectedIndex = 0;
        scanScripts();
        updateResults();
        closeAnim.stop();
        openAnim.restart();
        searchField.forceActiveFocus();
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

    NumberAnimation { id: openAnim; target: root; property: "animProgress"; from: root.animProgress; to: 1.0; duration: 228; easing.type: Easing.OutQuart }
    NumberAnimation {
        id: closeAnim; target: root; property: "animProgress"; from: root.animProgress; to: 0.0; duration: 156; easing.type: Easing.InQuad
        onFinished: if (!root.isOpen) root.visible = false
    }

    HyprlandFocusGrab {
        windows: [root]
        active: root.isOpen
        onCleared: root.close()
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void { root.toggle(); }
        function open(): void { root.open(); }
        function close(): void { root.close(); }
    }

    // ---- scripts (~/scripts), shown when the query starts with "@" ------
    property var scripts: []
    property var scriptsTmp: []
    readonly property string scriptsDir: (Quickshell.env("HOME") || "/home/chizuko") + "/scripts"
    readonly property bool scriptMode: searchField.text.startsWith("@")

    Process {
        id: scriptsProc
        command: ["bash", "-c", "find \"$HOME/scripts\" -type f -not -path '*/.*' -printf '%P\\t%m\\n' 2>/dev/null"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                const t = data.indexOf("\t");
                if (t === -1) return;
                const rel = data.substring(0, t);
                const mode = parseInt(data.substring(t + 1), 8);
                const path = root.scriptsDir + "/" + rel;
                const base = rel.substring(rel.lastIndexOf("/") + 1);
                const dir = rel.indexOf("/") === -1 ? "" : rel.substring(0, rel.lastIndexOf("/"));
                root.scriptsTmp.push({
                    id: "script:" + rel,
                    isScript: true,
                    name: base,
                    comment: dir === "" ? "~/scripts" : "~/scripts/" + dir,
                    path: path,
                    executable: (mode & 73) !== 0       // any of the x bits
                });
            }
        }
        onRunningChanged: {
            if (!running) {
                root.scripts = root.scriptsTmp;
                if (root.isOpen && root.scriptMode) root.updateResults();
            }
        }
    }

    function scanScripts() {
        scriptsTmp = [];
        scriptsProc.running = false;
        scriptsProc.running = true;
    }

    function runScript(sc) {
        let cmd;
        if (sc.executable) cmd = [sc.path];
        else if (sc.name.endsWith(".py")) cmd = ["python3", sc.path];
        else if (sc.name.endsWith(".fish")) cmd = ["fish", sc.path];
        else cmd = ["bash", sc.path];
        Quickshell.execDetached({ command: cmd, workingDirectory: scriptsDir });
    }

    // ---- search --------------------------------------------------------
    function updateResults() {
        if (searchField.text.startsWith("@")) {
            const sq = searchField.text.substring(1).trim().toLowerCase();
            let sres = scripts.slice();
            if (sq !== "") {
                const scored = [];
                for (let i = 0; i < sres.length; i++) {
                    const n = sres[i].name.toLowerCase();
                    let sc = -1;
                    if (n === sq) sc = 100;
                    else if (n.startsWith(sq)) sc = 80;
                    else if (n.includes(sq)) sc = 40;
                    else if (sres[i].comment.toLowerCase().includes(sq)) sc = 10;
                    if (sc >= 0) scored.push({ a: sres[i], s: sc });
                }
                scored.sort((x, y) => y.s - x.s || x.a.name.localeCompare(y.a.name));
                sres = scored.map(x => x.a);
            } else {
                sres.sort((a, b) => a.name.localeCompare(b.name));
            }
            results = sres;
            selectedIndex = Math.min(selectedIndex, Math.max(0, sres.length - 1));
            syncModel(sres);
            return;
        }

        const q = searchField.text.trim().toLowerCase();
        const apps = DesktopEntries.applications.values.filter(a => !a.noDisplay);

        let out;
        if (q === "") {
            out = apps.slice();
            out.sort((a, b) => a.name.localeCompare(b.name));
        } else {
            const scored = [];
            for (let i = 0; i < apps.length; i++) {
                const a = apps[i];
                const name = a.name.toLowerCase();
                let score = -1;
                if (name === q) score = 100;
                else if (name.startsWith(q)) score = 80;
                else if (name.split(/[\s\-_]+/).some(w => w.startsWith(q))) score = 60;
                else if (name.includes(q)) score = 40;
                else if ((a.genericName || "").toLowerCase().includes(q)) score = 25;
                else if ((a.keywords || []).some(k => k.toLowerCase().includes(q))) score = 20;
                else if ((a.comment || "").toLowerCase().includes(q)) score = 10;
                if (score >= 0) scored.push({ a: a, s: score });
            }
            scored.sort((x, y) => y.s - x.s || x.a.name.localeCompare(y.a.name));
            out = scored.map(x => x.a);
        }
        results = out;
        syncModel(out);
        selectedIndex = Math.min(selectedIndex, Math.max(0, out.length - 1));
    }

    // Backing model, updated by diffing (remove / move / insert) so ListView can animate.
    // Entries are looked up by id; the map is only ever added to, so a card that is
    // fading out can still read its own data.
    ListModel { id: appModel }
    property var entryMap: ({})

    function syncModel(items) {
        const want = {};
        for (let i = 0; i < items.length; i++) {
            want[items[i].id] = true;
            entryMap[items[i].id] = items[i];
        }
        for (let i = appModel.count - 1; i >= 0; i--) {
            if (!want[appModel.get(i).aid]) appModel.remove(i);
        }
        for (let i = 0; i < items.length; i++) {
            const id = items[i].id;
            if (i < appModel.count && appModel.get(i).aid === id) continue;
            let found = -1;
            for (let j = i + 1; j < appModel.count; j++) {
                if (appModel.get(j).aid === id) { found = j; break; }
            }
            if (found !== -1) appModel.move(found, i, 1);
            else appModel.insert(i, { aid: id });
        }
    }

    function launch(entry) {
        if (!entry) return;
        if (entry.isScript) runScript(entry);
        else entry.execute();
        close();
    }
    function launchSelected() {
        if (results.length > 0) launch(results[selectedIndex]);
    }
    function move(delta) {
        if (results.length === 0) return;
        selectedIndex = Math.max(0, Math.min(results.length - 1, selectedIndex + delta));
        list.positionViewAtIndex(selectedIndex, ListView.Contain);
    }

    // ---- backdrop ------------------------------------------------------
    MouseArea {
        anchors.fill: parent
        onPressed: mouse => { root.close(); mouse.accepted = true; }
    }

    // ---- dialog --------------------------------------------------------
    Rectangle {
        id: dialog
        anchors.horizontalCenter: parent.horizontalCenter
        width: 640
        height: 560
        radius: 28
        color: Theme.surfaceContainer
        border.color: Theme.outlineVariant
        border.width: 1
        clip: true

        readonly property real targetY: Math.round((root.height - height) / 2)
        y: targetY + (1.0 - root.animProgress) * (root.height - targetY + 40)
        opacity: root.animProgress

        MouseArea { anchors.fill: parent; onPressed: mouse => { mouse.accepted = true; } }

        Column {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 16

            // search bar
            Rectangle {
                width: parent.width
                height: 56
                radius: 28
                color: Theme.surfaceContainerHighest
                border.width: 2
                border.color: searchField.activeFocus ? Theme.primary : "transparent"
                Behavior on border.color { ColorAnimation { duration: 150 } }

                Text {
                    id: searchIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.scriptMode ? "\ueb8e" : "\ue8b6"
                    color: root.scriptMode ? Theme.primary : Theme.colorOnSurfaceVariant
                    Behavior on color { ColorAnimation { duration: 150 } }
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 24
                    font.variableAxes: { "FILL": 0 }
                }

                TextInput {
                    id: searchField
                    anchors.left: searchIcon.right
                    anchors.leftMargin: 12
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.colorOnSurface
                    font.family: Theme.fontFamily
                    font.pixelSize: 17
                    selectByMouse: true
                    clip: true
                    renderType: Text.NativeRendering

                    Text {
                        text: "Search apps  ·  type @ for scripts"
                        visible: !searchField.text
                        color: Theme.colorOnSurfaceVariant
                        font.family: Theme.fontFamily
                        font.pixelSize: 17
                        anchors.verticalCenter: parent.verticalCenter
                        renderType: Text.NativeRendering
                    }

                    onTextChanged: { root.selectedIndex = 0; list.positionViewAtBeginning(); root.updateResults(); }

                    Keys.onUpPressed: event => { event.accepted = true; root.move(-1); }
                    Keys.onDownPressed: event => { event.accepted = true; root.move(1); }
                    Keys.onReturnPressed: event => { event.accepted = true; root.launchSelected(); }
                    Keys.onEnterPressed: event => { event.accepted = true; root.launchSelected(); }
                    Keys.onEscapePressed: event => { event.accepted = true; root.close(); }
                    Keys.onTabPressed: event => { event.accepted = true; root.move(1); }
                }
            }

            // results
            Item {
                width: parent.width
                height: parent.height - 56 - 16
                clip: true

                Column {
                    anchors.centerIn: parent
                    spacing: 10
                    visible: root.results.length === 0
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: ""
                        color: Theme.outline
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 56
                        font.variableAxes: { "FILL": 0 }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.scriptMode ? "No scripts in ~/scripts" : "No apps found"
                        color: Theme.colorOnSurfaceVariant
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        renderType: Text.NativeRendering
                    }
                }

                ListView {
                    id: list
                    anchors.fill: parent
                    spacing: 6
                    model: appModel
                    boundsBehavior: Flickable.StopAtBounds

                    // MD3 emphasized easing for results appearing / disappearing / reordering
                    displaced: Transition {
                        NumberAnimation { properties: "y"; duration: 340; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0.0, 0.0, 1.0, 1.0, 1.0] }
                    }
                    move: Transition {
                        NumberAnimation { properties: "y"; duration: 340; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0.0, 0.0, 1.0, 1.0, 1.0] }
                    }
                    add: Transition {
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 240; easing.type: Easing.OutCubic }
                            NumberAnimation { property: "scale"; from: 0.92; to: 1; duration: 300; easing.type: Easing.OutCubic }
                        }
                    }
                    remove: Transition {
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; to: 0; duration: 160; easing.type: Easing.InCubic }
                            NumberAnimation { property: "scale"; to: 0.92; duration: 160; easing.type: Easing.InCubic }
                        }
                    }
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Rectangle {
                        id: card
                        required property string aid
                        required property int index
                        readonly property var entry: root.entryMap[aid] || ({})
                        readonly property bool isSelected: root.selectedIndex === index

                        width: list.width
                        height: 64
                        radius: 20
                        color: isSelected ? Theme.secondaryContainer : Theme.surfaceContainerHigh
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: card.isSelected ? Theme.colorOnSecondaryContainer : Theme.colorOnSurface
                            opacity: mouse.pressed ? 0.12 : (mouse.containsMouse ? 0.08 : 0)
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                        }

                        IconImage {
                            id: appIcon
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            implicitSize: 36
                            visible: !card.entry.isScript
                            source: card.entry.isScript ? "" : Quickshell.iconPath(card.entry.icon, "application-x-executable")
                        }
                        // scripts get a terminal glyph in a tonal circle
                        Rectangle {
                            visible: card.entry.isScript === true
                            anchors.fill: appIcon
                            radius: width / 2
                            color: card.isSelected ? Theme.primary : Theme.primaryContainer
                            Text {
                                anchors.centerIn: parent
                                text: "\ueb8e"
                                color: card.isSelected ? Theme.colorOnPrimary : Theme.colorOnPrimaryContainer
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: 20
                                font.variableAxes: { "FILL": 0 }
                            }
                        }

                        Column {
                            anchors.left: appIcon.right
                            anchors.leftMargin: 16
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                width: parent.width
                                text: card.entry.name || ""
                                color: card.isSelected ? Theme.colorOnSecondaryContainer : Theme.colorOnSurface
                                font.family: Theme.fontFamily
                                font.pixelSize: 15
                                font.bold: true
                                elide: Text.ElideRight
                                renderType: Text.NativeRendering
                            }
                            Text {
                                width: parent.width
                                visible: text !== ""
                                text: card.entry.comment || card.entry.genericName || ""
                                color: Theme.colorOnSurfaceVariant
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                renderType: Text.NativeRendering
                            }
                        }

                        MouseArea {
                            id: mouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.selectedIndex = card.index; root.launch(card.entry); }
                        }
                    }
                }
            }
        }
    }
}
