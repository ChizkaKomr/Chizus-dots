import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import ".."

// Month calendar popup — same open/close behaviour as VolumeCenter.
PanelWindow {
    id: root

    property var parentWindow: null
    screen: parentWindow ? parentWindow.screen : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)

    anchors { top: true; bottom: true; left: true; right: true }
    visible: false
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-calendar"
    WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    property bool isOpen: false
    property real animProgress: 0.0
    property double lastCloseTime: 0

    // month being shown
    property int viewYear: new Date().getFullYear()
    property int viewMonth: new Date().getMonth()
    property var today: new Date()

    // ---- notes: { "yyyy-MM-dd": ["note", ...] } persisted as JSON -------
    property var notes: ({})
    property string selectedKey: Qt.formatDate(new Date(), "yyyy-MM-dd")

    FileView {
        id: notesFile
        path: (Quickshell.env("HOME") || "/home/chizuko") + "/.config/quickshell/calendar_notes.json"
        printErrors: false
        onLoaded: {
            try { root.notes = JSON.parse(notesFile.text() || "{}"); }
            catch (e) { root.notes = ({}); }
        }
        onLoadFailed: root.notes = ({})
    }

    function saveNotes() { notesFile.setText(JSON.stringify(root.notes, null, 2)); }

    function addNote(text) {
        const t = text.trim();
        if (t === "") return;
        const n = Object.assign({}, root.notes);
        n[selectedKey] = (n[selectedKey] || []).concat([t]);
        root.notes = n;
        saveNotes();
    }

    function removeNote(key, i) {
        const n = Object.assign({}, root.notes);
        const list = (n[key] || []).slice();
        list.splice(i, 1);
        if (list.length === 0) delete n[key]; else n[key] = list;
        root.notes = n;
        saveNotes();
    }

    // ---- month switch: two pages slide side to side ----------------------
    property real slideProg: 0          // 0..1
    property int slideDir: 1            // +1 = next month (slides left), -1 = previous
    property int nextYear: viewYear
    property int nextMonth: viewMonth

    function commitMonth() {
        // the page content is swapped under the ring: move it without flying
        pager.animateRing = false;
        viewYear = nextYear;
        viewMonth = nextMonth;
        slideProg = 0;
        pager.animateRing = true;
    }

    function goMonth(delta) {
        // finish an in-flight switch instantly so fast clicking still advances
        if (monthAnim.running) { monthAnim.stop(); commitMonth(); }
        const d = new Date(viewYear, viewMonth + delta, 1);
        nextYear = d.getFullYear();
        nextMonth = d.getMonth();
        slideDir = delta > 0 ? 1 : -1;
        monthAnim.restart();
    }

    NumberAnimation {
        id: monthAnim
        target: root; property: "slideProg"
        from: 0; to: 1; duration: 320
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.2, 0.0, 0.0, 1.0, 1.0, 1.0]
        onFinished: root.commitMonth()
    }

    function open() {
        if (isOpen && visible) return;
        const n = new Date();
        today = n; viewYear = n.getFullYear(); viewMonth = n.getMonth();
        selectedKey = Qt.formatDate(n, "yyyy-MM-dd");
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
        if (isOpen) close();
        else {
            if (Date.now() - lastCloseTime < 250) return;
            open();
        }
    }

    NumberAnimation { id: openAnim; target: root; property: "animProgress"; from: root.animProgress; to: 1.0; duration: 320; easing.type: Easing.OutCubic }
    NumberAnimation {
        id: closeAnim; target: root; property: "animProgress"; from: root.animProgress; to: 0.0; duration: 250; easing.type: Easing.InCubic
        onFinished: if (!root.isOpen) root.visible = false
    }

    HyprlandFocusGrab {
        windows: root.parentWindow ? [root, root.parentWindow] : [root]
        active: root.isOpen
        onCleared: root.close()
    }

    // outside click closes
    MouseArea {
        anchors.fill: parent
        onPressed: mouse => { root.close(); mouse.accepted = true; }
    }

    Rectangle {
        id: panel
        width: 340
        height: col.implicitHeight + 40
        y: 50
        x: (root.width - width - 12) + (1.0 - root.animProgress) * (width + 30)
        opacity: root.animProgress
        radius: 26
        color: Theme.background
        border.color: Theme.outlineVariant
        border.width: 1

        MouseArea { anchors.fill: parent; onPressed: mouse => mouse.accepted = true }

        Column {
            id: col
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            // ---- header: month/year + arrows
            Item {
                width: parent.width
                height: 40

                Item {
                    id: titleClip
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 200; height: parent.height
                    clip: true

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        x: -root.slideDir * root.slideProg * titleClip.width
                        opacity: 1.0 - root.slideProg
                        text: Qt.locale().monthName(root.viewMonth) + " " + root.viewYear
                        color: Theme.colorOnSurface
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                        font.bold: true
                        renderType: Text.NativeRendering
                    }
                    Text {
                        visible: monthAnim.running
                        anchors.verticalCenter: parent.verticalCenter
                        x: root.slideDir * (1 - root.slideProg) * titleClip.width
                        opacity: root.slideProg
                        text: Qt.locale().monthName(root.nextMonth) + " " + root.nextYear
                        color: Theme.colorOnSurface
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                        font.bold: true
                        renderType: Text.NativeRendering
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Repeater {
                        model: [{ g: "", d: -1 }, { g: "", d: 1 }]
                        delegate: Rectangle {
                            required property var modelData
                            width: 36; height: 36; radius: 18
                            color: arrowMouse.containsMouse ? Theme.surfaceContainerHigh : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData.g
                                color: Theme.colorOnSurfaceVariant
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: 22
                                font.variableAxes: { "FILL": 0 }
                            }
                            MouseArea {
                                id: arrowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.goMonth(parent.modelData.d)
                            }
                        }
                    }
                }
            }

            // ---- weekday labels (Monday first)
            Grid {
                columns: 7
                width: parent.width
                Repeater {
                    model: ["M", "T", "W", "T", "F", "S", "S"]
                    delegate: Text {
                        required property string modelData
                        width: panel.width / 7 - 40 / 7
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        color: Theme.colorOnSurfaceVariant
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: true
                        renderType: Text.NativeRendering
                    }
                }
            }

            // ---- day grid: two pages side by side, sliding horizontally
            Item {
                id: pager
                width: parent.width
                height: pageA.implicitHeight
                clip: true

                readonly property real cw: width / 7

                // --- shared selection ring: flies between cells ---
                property bool animateRing: true
                readonly property int selIndex: {
                    const first = new Date(root.viewYear, root.viewMonth, 1);
                    const offset = (first.getDay() + 6) % 7;
                    const start = new Date(root.viewYear, root.viewMonth, 1 - offset, 12);
                    const target = new Date(root.selectedKey + "T12:00:00");
                    const diff = Math.round((target - start) / 86400000);
                    return (diff >= 0 && diff < 42) ? diff : -1;
                }
                readonly property real tgtX: selIndex < 0 ? 0 : (selIndex % 7) * cw + (cw - 36) / 2
                readonly property real tgtY: selIndex < 0 ? 0 : Math.floor(selIndex / 7) * 42 + 2
                property real ringX: tgtX
                property real ringY: tgtY
                Behavior on ringX { enabled: pager.animateRing; NumberAnimation { duration: 180; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0.0, 0.0, 1.0, 1.0, 1.0] } }
                Behavior on ringY { enabled: pager.animateRing; NumberAnimation { duration: 180; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0.0, 0.0, 1.0, 1.0, 1.0] } }

                // trail: ghost discs follow the ring with increasing lag and fade out
                readonly property bool moving: Math.hypot(tgtX - ringX, tgtY - ringY) > 1.0

                Repeater {
                    model: 5
                    delegate: Rectangle {
                        required property int index
                        z: 0
                        width: 36; height: 36; radius: 18
                        color: Theme.primary
                        property real gx: pager.ringX
                        property real gy: pager.ringY
                        Behavior on gx { enabled: pager.animateRing; NumberAnimation { duration: 14 * (index + 1) } }
                        Behavior on gy { enabled: pager.animateRing; NumberAnimation { duration: 14 * (index + 1) } }
                        x: pageA.x + gx
                        y: gy
                        opacity: (pager.moving && pager.selIndex >= 0) ? 0.28 - index * 0.05 : 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }
                }

                Rectangle {
                    id: ring
                    z: 1
                    width: 36; height: 36; radius: 18
                    color: "transparent"
                    border.width: 2
                    border.color: Theme.primary
                    x: pageA.x + pager.ringX
                    y: pager.ringY
                    opacity: pager.selIndex >= 0 ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }

                CalendarDays {
                    id: pageA
                    year: root.viewYear; month: root.viewMonth
                    today: root.today; notes: root.notes; selectedKey: root.selectedKey
                    cellWidth: pager.cw
                    x: -root.slideDir * root.slideProg * pager.width
                    onPicked: key => root.selectedKey = key
                }
                CalendarDays {
                    id: pageB
                    visible: monthAnim.running
                    year: root.nextYear; month: root.nextMonth
                    today: root.today; notes: root.notes; selectedKey: root.selectedKey
                    cellWidth: pager.cw
                    x: root.slideDir * (1 - root.slideProg) * pager.width
                    onPicked: key => root.selectedKey = key
                }
            }

            // ---- notes for the selected day
            Rectangle {
                id: notesCard
                width: parent.width
                height: notesCol.implicitHeight + 24
                radius: 20
                color: Theme.surfaceContainer

                readonly property var list: root.notes[root.selectedKey] || []

                Column {
                    id: notesCol
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    Text {
                        text: Qt.formatDate(new Date(root.selectedKey + "T12:00:00"), "dddd, MMMM d")
                        color: Theme.colorOnSurfaceVariant
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: true
                        font.letterSpacing: 0.5
                        renderType: Text.NativeRendering
                    }

                    Text {
                        visible: notesCard.list.length === 0
                        text: "No notes"
                        color: Theme.outline
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        renderType: Text.NativeRendering
                    }

                    Flickable {
                        width: parent.width
                        height: Math.min(contentHeight, 150)
                        contentHeight: noteList.implicitHeight
                        clip: true
                        visible: notesCard.list.length > 0
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: noteList
                            width: parent.width
                            spacing: 6
                            Repeater {
                                model: notesCard.list
                                delegate: Rectangle {
                                    required property int index
                                    required property string modelData
                                    width: noteList.width
                                    height: Math.max(36, noteText.implicitHeight + 16)
                                    radius: 14
                                    color: Theme.surfaceContainerHigh

                                    Text {
                                        id: noteText
                                        anchors.left: parent.left
                                        anchors.right: delBtn.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 4
                                        text: modelData
                                        wrapMode: Text.Wrap
                                        color: Theme.colorOnSurface
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        renderType: Text.NativeRendering
                                    }
                                    Rectangle {
                                        id: delBtn
                                        anchors.right: parent.right
                                        anchors.rightMargin: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 28; height: 28; radius: 14
                                        color: delMouse.containsMouse ? Theme.errorContainer : "transparent"
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        Text {
                                            anchors.centerIn: parent
                                            text: "\ue5cd"
                                            color: delMouse.containsMouse ? Theme.colorOnErrorContainer : Theme.colorOnSurfaceVariant
                                            font.family: "Material Symbols Rounded"
                                            font.pixelSize: 18
                                            font.variableAxes: { "FILL": 0 }
                                        }
                                        MouseArea {
                                            id: delMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.removeNote(root.selectedKey, index)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // add-note field
                    Rectangle {
                        width: parent.width
                        height: 40
                        radius: 20
                        color: Theme.surfaceContainerHighest
                        border.width: 2
                        border.color: noteInput.activeFocus ? Theme.primary : "transparent"
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            visible: noteInput.text.length === 0
                            text: "Add a note…"
                            color: Theme.colorOnSurfaceVariant
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            renderType: Text.NativeRendering
                        }
                        TextInput {
                            id: noteInput
                            anchors.left: parent.left
                            anchors.right: addBtn.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 16
                            anchors.rightMargin: 4
                            color: Theme.colorOnSurface
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            clip: true
                            onAccepted: { root.addNote(text); text = ""; }
                            Keys.onEscapePressed: { text = ""; focus = false; }
                        }
                        Rectangle {
                            id: addBtn
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: 32; height: 32; radius: 16
                            color: noteInput.text.length > 0 ? Theme.primary : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text {
                                anchors.centerIn: parent
                                text: "\ue145"
                                color: noteInput.text.length > 0 ? Theme.colorOnPrimary : Theme.colorOnSurfaceVariant
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: 20
                                font.variableAxes: { "FILL": 0 }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { root.addNote(noteInput.text); noteInput.text = ""; }
                            }
                        }
                    }
                }
            }
        }
    }
}
