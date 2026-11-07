import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import ".."

PanelWindow {
    id: root

    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    visible: false
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-clipboard"
    WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // State
    property bool isOpen: false
    property real animProgress: 0.0
    property double lastCloseTime: 0

    // Data lists
    property var tempBuffer: []
    property var rawItems: []
    property var filteredItems: []
    property var pinnedIds: []
    property string activeFilter: "all" // Default to All
    property int selectedIndex: 0
    property int thumbsVersion: 0

    // Dynamic theme palette derived from Theme.qml
    readonly property color colBg: Theme.background
    readonly property color colBorder: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.18)
    readonly property color colCardBg: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.06)
    readonly property color colCardHover: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.14)
    readonly property color colAccent: Theme.foreground
    readonly property color colAccentHover: Qt.lighter(Theme.foreground, 1.2)
    readonly property color colTextPrimary: Theme.secondary
    readonly property color colTextMuted: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.65)
    readonly property color colTextDim: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.4)
    readonly property color colInputBg: Qt.rgba(0, 0, 0, 0.28)
    readonly property color colDanger: Theme.alertRed

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
        searchField.text = "";
        activeFilter = "all";
        selectedIndex = 0;
        refresh();
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
        if (isOpen) {
            close();
        } else {
            if (Date.now() - lastCloseTime < 200) return;
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
        windows: [ root ]
        active: root.isOpen
        onCleared: root.close()
    }

    IpcHandler {
        target: "clipboard"
        function toggle() {
            root.toggle();
        }
        function open() {
            root.open();
        }
        function close() {
            root.close();
        }
        function togglePin(id: string) {
            root.togglePin(id);
        }
        function deleteItem(id: string) {
            root.deleteItem(id);
        }
        function clearAll() {
            root.clearAll();
        }
    }

    // -------------------------------------------------------------
    // Persistent Pin Storage (FileView)
    // -------------------------------------------------------------
    FileView {
        id: pinStorage
        path: (Quickshell.env("HOME") || "/home/chizuko") + "/.cache/quickshell/clipboard_pins.json"
        watchChanges: true
        onLoaded: {
            try {
                const raw = pinStorage.text();
                if (raw && raw.trim().length > 0) {
                    const parsed = JSON.parse(raw);
                    if (Array.isArray(parsed)) {
                        root.pinnedIds = parsed;
                        root.applyFilter();
                    }
                }
            } catch (e) {
                console.warn("Failed to parse clipboard pins:", e);
            }
        }
        onLoadFailed: err => {
            pinStorage.setText("[]");
        }
    }

    function savePins() {
        try {
            pinStorage.setText(JSON.stringify(root.pinnedIds));
        } catch (e) {
            console.error("Failed to save clipboard pins:", e);
        }
    }

    // -------------------------------------------------------------
    // Cliphist Data Integration & Image Thumbnail Generation
    // -------------------------------------------------------------
    Process {
        id: initDirProc
        command: ["mkdir", "-p", "/tmp/cliphist_thumbs"]
    }

    Process {
        id: listProc
        command: ["cliphist", "list"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (!data || data.trim().length === 0) return;
                const tabIdx = data.indexOf("\t");
                if (tabIdx === -1) return;
                const id = data.substring(0, tabIdx).trim();
                const text = data.substring(tabIdx + 1).trim();
                if (id.length > 0 && text.length > 0) {
                    root.tempBuffer.push({
                        id: id,
                        text: text
                    });
                }
            }
        }
        onRunningChanged: {
            if (!running) {
                root.rawItems = root.tempBuffer;
                root.applyFilter();
                root.generateThumbnails();
            }
        }
    }

    Process {
        id: copyProc
    }

    Process {
        id: deleteProc
    }

    Process {
        id: wipeProc
        onRunningChanged: {
            if (!running) {
                root.refresh();
            }
        }
    }

    Process {
        id: thumbProc
        onRunningChanged: {
            if (!running) {
                root.thumbsVersion++;
            }
        }
    }

    Process {
        id: cleanThumbsProc
    }

    Component.onCompleted: {
        initDirProc.running = true;
        try {
            if (pinStorage.loaded) {
                const raw = pinStorage.text();
                if (raw && raw.trim().length > 0) {
                    const parsed = JSON.parse(raw);
                    if (Array.isArray(parsed)) {
                        root.pinnedIds = parsed;
                    }
                }
            }
        } catch (e) {}
    }

    function refresh() {
        root.tempBuffer = [];
        listProc.running = false;
        listProc.running = true;
    }

    function generateThumbnails() {
        if (thumbProc.running) return;
        const imgIds = [];
        for (let i = 0; i < root.rawItems.length; i++) {
            const item = root.rawItems[i];
            if (item.text.startsWith("[[ binary data")) {
                imgIds.push(item.id);
            }
        }
        if (imgIds.length === 0) return;

        const script = 'dir="/tmp/cliphist_thumbs"; for id in "$@"; do target="$dir/$id.png"; if [ ! -s "$target" ]; then printf "%s\\t" "$id" | cliphist decode > "$target" 2>/dev/null; fi; done';
        thumbProc.exec(["bash", "-c", script, "--"].concat(imgIds));
    }

    function parseImageMeta(text) {
        const match = text.match(/\[\[ binary data (.*?) ([a-zA-Z0-9]+) (\d+x\d+) \]\]/);
        if (match) {
            return {
                size: match[1],
                format: match[2].toUpperCase(),
                dimensions: match[3].replace("x", " × "),
                title: "Image (" + match[2].toUpperCase() + ")"
            };
        }
        return {
            size: "",
            format: "IMAGE",
            dimensions: "",
            title: "Image"
        };
    }

    function copyItem(id) {
        if (!id) return;
        copyProc.exec(["bash", "-c", "printf '%s\\t' '" + id + "' | cliphist decode | wl-copy"]);
        root.close();
    }

    function deleteItem(id) {
        if (!id) return;
        deleteProc.exec(["bash", "-c", "printf '%s\\t' '" + id + "' | cliphist delete; rm -f '/tmp/cliphist_thumbs/" + id + ".png'"]);

        // Remove from pinned IDs if it was pinned
        const pinIdx = root.pinnedIds.indexOf(id);
        if (pinIdx !== -1) {
            const copy = root.pinnedIds.slice();
            copy.splice(pinIdx, 1);
            root.pinnedIds = copy;
            root.savePins();
        }

        // Remove immediately from in-memory lists for responsive UI
        root.rawItems = root.rawItems.filter(item => item.id !== id);
        root.applyFilter();
    }

    function clearAll() {
        if (wipeProc.running) return;

        // Keep only pins that currently exist in rawItems (or retain existing pinnedIds if rawItems is empty)
        const pinned = root.rawItems.length > 0
            ? (root.pinnedIds || []).filter(id => root.rawItems.some(item => item.id === id))
            : (root.pinnedIds || []);
        root.pinnedIds = pinned;
        root.savePins();

        // Immediately filter in-memory lists to keep only pinned items for responsive UI
        root.rawItems = root.rawItems.filter(item => pinned.indexOf(item.id) !== -1);
        root.applyFilter();

        const script = 'if [ "$#" -eq 0 ]; then ' +
            'cliphist wipe; ' +
            'rm -rf /tmp/cliphist_thumbs/*; ' +
            'else ' +
            'declare -A pinned; ' +
            'for id in "$@"; do pinned["$id"]=1; done; ' +
            'IFS="$(printf \'\\t\')"; ' +
            'cliphist list | while read -r id rest; do ' +
            'if [ -n "$id" ] && [ -z "${pinned[$id]}" ]; then ' +
            'printf "%s\\t\\n" "$id"; ' +
            'rm -f "/tmp/cliphist_thumbs/$id.png"; ' +
            'fi; ' +
            'done | cliphist delete; ' +
            'fi';

        wipeProc.exec(["bash", "-c", script, "--"].concat(pinned));
    }

    function togglePin(id) {
        const idx = root.pinnedIds.indexOf(id);
        const copy = root.pinnedIds.slice();
        if (idx === -1) {
            copy.push(id);
        } else {
            copy.splice(idx, 1);
        }
        root.pinnedIds = copy;
        root.savePins();
        root.applyFilter();
    }

    function applyFilter() {
        const query = searchField.text.trim().toLowerCase();
        const filter = root.activeFilter;

        const filtered = root.rawItems.filter(item => {
            const isImg = item.text.startsWith("[[ binary data");
            const isLink = item.text.startsWith("http://") || item.text.startsWith("https://") || item.text.startsWith("www.");

            if (filter === "text" && (isImg || isLink)) return false;
            if (filter === "images" && !isImg) return false;
            if (filter === "links" && !isLink) return false;

            if (query.length > 0) {
                return item.text.toLowerCase().includes(query);
            }
            return true;
        });

        // Sort: newest -> oldest (cliphist ids only ever grow), pinned always at the very bottom.
        // Explicit numeric ids as the key: the old comparator returned 0 for ties and
        // relied on a stable sort, which the QML engine doesn't guarantee (-> scattered order).
        const pinSet = {};
        for (let i = 0; i < root.pinnedIds.length; i++) pinSet[root.pinnedIds[i]] = true;
        filtered.sort((a, b) => {
            const aPin = pinSet[a.id] ? 1 : 0;
            const bPin = pinSet[b.id] ? 1 : 0;
            if (aPin !== bPin) return aPin - bPin;
            return Number(b.id) - Number(a.id);
        });

        root.filteredItems = filtered;
        root.syncModel(filtered);
        root.selectedIndex = Math.min(root.selectedIndex, Math.max(0, filtered.length - 1));
    }

    // Backing model for the list. Kept in sync with filteredItems by *diffing*
    // (remove / move / insert) so ListView can animate pin, unpin, add and delete.
    ListModel { id: clipModel }

    function syncModel(items) {
        const want = {};
        for (let i = 0; i < items.length; i++) want[items[i].id] = true;

        for (let i = clipModel.count - 1; i >= 0; i--) {
            if (!want[clipModel.get(i).cid]) clipModel.remove(i);
        }
        for (let i = 0; i < items.length; i++) {
            const it = items[i];
            if (i < clipModel.count && clipModel.get(i).cid === it.id) continue;
            let found = -1;
            for (let j = i + 1; j < clipModel.count; j++) {
                if (clipModel.get(j).cid === it.id) { found = j; break; }
            }
            if (found !== -1) clipModel.move(found, i, 1);
            else clipModel.insert(i, { cid: it.id, ctext: it.text });
        }
    }

    function selectPrevious() {
        if (root.filteredItems.length === 0) return;
        if (root.selectedIndex > 0) {
            root.selectedIndex--;
            root.smoothScrollTo(root.selectedIndex);
        }
    }

    function selectNext() {
        if (root.filteredItems.length === 0) return;
        if (root.selectedIndex < root.filteredItems.length - 1) {
            root.selectedIndex++;
            root.smoothScrollTo(root.selectedIndex);
        }
    }

    function copySelected() {
        if (root.filteredItems.length > 0 && root.selectedIndex >= 0 && root.selectedIndex < root.filteredItems.length) {
            root.copyItem(root.filteredItems[root.selectedIndex].id);
        }
    }

    function smoothScrollTo(idx) {
        if (idx < 0 || idx >= root.filteredItems.length) return;
        const it = itemsList.itemAtIndex(idx);
        if (it) {
            const pad = 14;
            const top = itemsList.contentY;
            const bottom = top + itemsList.height;
            let targetY = top;

            if (it.y < top) {
                targetY = it.y - pad;
            } else if (it.y + it.height > bottom) {
                targetY = it.y + it.height - itemsList.height + pad;
            }

            const maxScroll = Math.max(0, itemsList.contentHeight - itemsList.height);
            targetY = Math.max(0, Math.min(maxScroll, targetY));

            if (Math.abs(targetY - top) > 1) {
                scrollAnim.stop();
                scrollAnim.to = targetY;
                scrollAnim.start();
            }
        } else {
            itemsList.positionViewAtIndex(idx, ListView.Contain);
        }
    }


    // Fullscreen backdrop to dismiss on outside click
    MouseArea {
        id: backdropArea
        anchors.fill: parent
        hoverEnabled: false
        onPressed: mouse => {
            root.close();
            mouse.accepted = true;
        }
    }

    // =============================================================
    // Main Clipboard Dialog (Material 3)
    // =============================================================
    Rectangle {
        id: dialog
        anchors.horizontalCenter: parent.horizontalCenter
        width: 720
        height: 600
        radius: 28
        color: Theme.surfaceContainer
        border.color: Theme.outlineVariant
        border.width: 1
        clip: true

        readonly property real targetY: Math.round((root.height - height) / 2)
        y: targetY + (1.0 - root.animProgress) * (root.height - targetY + 40)
        opacity: root.animProgress

        // Consume clicks inside dialog
        MouseArea {
            anchors.fill: parent
            onPressed: mouse => { mouse.accepted = true; }
        }

        // ---- reusable M3 pieces -------------------------------------
        component Glyph: Text {
            font.family: "Material Symbols Rounded"
            font.pixelSize: 22
            font.variableAxes: { "FILL": 0 }
            renderType: Text.NativeRendering
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        // M3 filter chip: outlined when off; on select the container fills (secondary-container),
        // a check mark scales in over the type icon, and a ripple spreads from the press point.
        component FilterChip: Rectangle {
            id: chip
            property string label
            property string glyph
            property bool active: false
            signal clicked()

            height: 34
            width: chipRow.implicitWidth + 28
            radius: 10
            color: active ? Theme.secondaryContainer : "transparent"
            border.width: 1
            border.color: active ? "transparent" : Theme.outline
            Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on border.color { ColorAnimation { duration: 220 } }

            // press feedback: slight squash like an M3 pressed state
            scale: chipMouse.pressed ? 0.96 : 1.0
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

            // ---- ripple, clipped to the chip's rounded shape ----
            Item {
                id: rippleHost
                anchors.fill: parent
                visible: false
                layer.enabled: true

                Rectangle {
                    id: ripple
                    property real cx: 0
                    property real cy: 0
                    property real d: 0
                    x: cx - d / 2; y: cy - d / 2
                    width: d; height: d; radius: d / 2
                    color: chip.active ? Theme.colorOnSecondaryContainer : Theme.colorOnSurface
                    opacity: 0
                }
            }
            Rectangle {
                id: rippleMask
                anchors.fill: parent
                radius: chip.radius
                visible: false
                layer.enabled: true
            }
            MultiEffect {
                anchors.fill: parent
                source: rippleHost
                maskEnabled: true
                maskSource: rippleMask
            }

            ParallelAnimation {
                id: rippleAnim
                NumberAnimation { target: ripple; property: "d"; from: 0; to: chip.width * 2.2; duration: 380; easing.type: Easing.OutCubic }
                SequentialAnimation {
                    NumberAnimation { target: ripple; property: "opacity"; to: 0.16; duration: 90 }
                    NumberAnimation { target: ripple; property: "opacity"; to: 0; duration: 330; easing.type: Easing.OutCubic }
                }
            }

            // hover state layer
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: chip.active ? Theme.colorOnSecondaryContainer : Theme.colorOnSurface
                opacity: chipMouse.containsMouse ? 0.08 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }

            Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: 6

                // icon slot: type icon scales out, check scales in
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18; height: 18
                    Glyph {
                        anchors.centerIn: parent
                        text: chip.glyph
                        font.pixelSize: 18
                        color: Theme.colorOnSurfaceVariant
                        opacity: chip.active ? 0 : 1
                        scale: chip.active ? 0.3 : 1
                        Behavior on opacity { NumberAnimation { duration: 180 } }
                        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    }
                    Glyph {
                        anchors.centerIn: parent
                        text: "\ue5ca"
                        font.pixelSize: 18
                        color: Theme.colorOnSecondaryContainer
                        opacity: chip.active ? 1 : 0
                        scale: chip.active ? 1 : 0.3
                        Behavior on opacity { NumberAnimation { duration: 180 } }
                        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: chip.label
                    color: chip.active ? Theme.colorOnSecondaryContainer : Theme.colorOnSurfaceVariant
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                    renderType: Text.NativeRendering
                    Behavior on color { ColorAnimation { duration: 220 } }
                }
            }
            MouseArea {
                id: chipMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse => {
                    ripple.cx = mouse.x;
                    ripple.cy = mouse.y;
                    rippleAnim.restart();
                }
                onClicked: chip.clicked()
            }
        }

        // M3 icon button (40px, circular, state layer)
        component IconBtn: Rectangle {
            id: ib
            property string glyph
            property color fg: Theme.colorOnSurfaceVariant
            property color activeFill: "transparent"
            property bool filled: false
            signal clicked()

            width: 40; height: 40; radius: 20
            color: filled ? activeFill : "transparent"
            Behavior on color { ColorAnimation { duration: 150 } }
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: ib.filled ? Theme.colorOnPrimary : ib.fg
                opacity: ibMouse.pressed ? 0.14 : (ibMouse.containsMouse ? 0.10 : 0)
            }
            Glyph {
                anchors.centerIn: parent
                text: ib.glyph
                color: ib.filled ? Theme.colorOnPrimary : ib.fg
                font.variableAxes: { "FILL": ib.filled ? 1 : 0 }
            }
            MouseArea {
                id: ibMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: ib.clicked()
            }
        }

        // ---- keyboard handlers --------------------------------------
        Keys.onUpPressed: event => { event.accepted = true; root.selectPrevious(); }
        Keys.onDownPressed: event => { event.accepted = true; root.selectNext(); }
        Keys.onReturnPressed: event => { event.accepted = true; root.copySelected(); }
        Keys.onEnterPressed: event => { event.accepted = true; root.copySelected(); }
        Keys.onEscapePressed: event => { event.accepted = true; root.close(); }
        Keys.onDeletePressed: event => {
            if (root.filteredItems.length > 0 && root.selectedIndex >= 0 && root.selectedIndex < root.filteredItems.length) {
                event.accepted = true;
                root.deleteItem(root.filteredItems[root.selectedIndex].id);
            }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 16

            // ---------------------------------------------------------
            // 1. Header: title + item count, tonal "Clear all" button
            // ---------------------------------------------------------
            Item {
                width: parent.width
                height: 48

                Column {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        text: "Clipboard"
                        color: Theme.colorOnSurface
                        font.family: Theme.fontFamily
                        font.pixelSize: 24
                        font.bold: true
                        renderType: Text.NativeRendering
                    }
                    Text {
                        text: root.filteredItems.length + (root.filteredItems.length === 1 ? " item" : " items")
                        color: Theme.colorOnSurfaceVariant
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        renderType: Text.NativeRendering
                    }
                }

                // Tonal button
                Rectangle {
                    id: clearAllBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 40
                    width: clearRow.implicitWidth + 40
                    radius: 20
                    color: Theme.secondaryContainer

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: Theme.colorOnSecondaryContainer
                        opacity: clearMouse.pressed ? 0.12 : (clearMouse.containsMouse ? 0.08 : 0)
                    }
                    Row {
                        id: clearRow
                        anchors.centerIn: parent
                        spacing: 8
                        Glyph {
                            anchors.verticalCenter: parent.verticalCenter
                            text: ""
                            font.pixelSize: 20
                            color: Theme.colorOnSecondaryContainer
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Clear all"
                            color: Theme.colorOnSecondaryContainer
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.bold: true
                            renderType: Text.NativeRendering
                        }
                    }
                    MouseArea {
                        id: clearMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.clearAll()
                    }
                }
            }

            // ---------------------------------------------------------
            // 2. Search bar (M3 filled pill)
            // ---------------------------------------------------------
            Rectangle {
                id: searchBar
                width: parent.width
                height: 52
                radius: 26
                color: Theme.surfaceContainerHighest
                border.width: 2
                border.color: searchField.activeFocus ? Theme.primary : "transparent"
                Behavior on border.color { ColorAnimation { duration: 150 } }

                Glyph {
                    id: searchIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: ""
                    color: Theme.colorOnSurfaceVariant
                }

                TextInput {
                    id: searchField
                    anchors.left: searchIcon.right
                    anchors.leftMargin: 12
                    anchors.right: clearSearch.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.colorOnSurface
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    selectByMouse: true
                    clip: true
                    renderType: Text.NativeRendering

                    Text {
                        text: "Search clipboard"
                        color: Theme.colorOnSurfaceVariant
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        visible: !searchField.text
                        anchors.verticalCenter: parent.verticalCenter
                        renderType: Text.NativeRendering
                    }

                    onTextChanged: {
                        root.selectedIndex = 0;
                        itemsList.contentY = 0;
                        root.applyFilter();
                    }

                    Keys.onUpPressed: event => { event.accepted = true; root.selectPrevious(); }
                    Keys.onDownPressed: event => { event.accepted = true; root.selectNext(); }
                    Keys.onReturnPressed: event => { event.accepted = true; root.copySelected(); }
                    Keys.onEnterPressed: event => { event.accepted = true; root.copySelected(); }
                    Keys.onEscapePressed: event => { event.accepted = true; root.close(); }
                    Keys.onDeletePressed: event => {
                        if (searchField.text.length === 0 && root.filteredItems.length > 0) {
                            event.accepted = true;
                            root.deleteItem(root.filteredItems[root.selectedIndex].id);
                        }
                    }
                }

                IconBtn {
                    id: clearSearch
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: ""
                    visible: searchField.text.length > 0
                    onClicked: { searchField.text = ""; searchField.forceActiveFocus(); }
                }
            }

            // ---------------------------------------------------------
            // 3. Filter chips
            // ---------------------------------------------------------
            Row {
                width: parent.width
                spacing: 8

                FilterChip {
                    label: "All"; glyph: ""
                    active: root.activeFilter === "all"
                    onClicked: { root.activeFilter = "all"; root.selectedIndex = 0; itemsList.contentY = 0; root.applyFilter(); }
                }
                FilterChip {
                    label: "Text"; glyph: ""
                    active: root.activeFilter === "text"
                    onClicked: { root.activeFilter = root.activeFilter === "text" ? "all" : "text"; root.selectedIndex = 0; itemsList.contentY = 0; root.applyFilter(); }
                }
                FilterChip {
                    label: "Images"; glyph: ""
                    active: root.activeFilter === "images"
                    onClicked: { root.activeFilter = root.activeFilter === "images" ? "all" : "images"; root.selectedIndex = 0; itemsList.contentY = 0; root.applyFilter(); }
                }
                FilterChip {
                    label: "Links"; glyph: ""
                    active: root.activeFilter === "links"
                    onClicked: { root.activeFilter = root.activeFilter === "links" ? "all" : "links"; root.selectedIndex = 0; itemsList.contentY = 0; root.applyFilter(); }
                }
            }

            // ---------------------------------------------------------
            // 4. Items list
            // ---------------------------------------------------------
            Item {
                width: parent.width
                height: parent.height - 48 - 52 - 34 - 16 * 3
                clip: true

                // Empty state
                Column {
                    anchors.centerIn: parent
                    spacing: 10
                    visible: root.filteredItems.length === 0

                    Glyph {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: ""
                        font.pixelSize: 56
                        color: Theme.outline
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: searchField.text.length > 0 ? "No matches" : "Clipboard is empty"
                        color: Theme.colorOnSurfaceVariant
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        renderType: Text.NativeRendering
                    }
                }

                ListView {
                    id: itemsList
                    anchors.fill: parent
                    spacing: 8
                    model: clipModel
                    boundsBehavior: Flickable.StopAtBounds

                    // MD3 emphasized easing for list reordering
                    displaced: Transition {
                        NumberAnimation { properties: "y"; duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0.0, 0.0, 1.0, 1.0, 1.0] }
                    }
                    move: Transition {
                        NumberAnimation { properties: "y"; duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0.0, 0.0, 1.0, 1.0, 1.0] }
                    }
                    add: Transition {
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }
                            NumberAnimation { property: "scale"; from: 0.92; to: 1; duration: 320; easing.type: Easing.OutCubic }
                        }
                    }
                    remove: Transition {
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; to: 0; duration: 180; easing.type: Easing.InCubic }
                            NumberAnimation { property: "scale"; to: 0.92; duration: 180; easing.type: Easing.InCubic }
                        }
                    }

                    NumberAnimation {
                        id: scrollAnim
                        target: itemsList
                        property: "contentY"
                        duration: 160
                        easing.type: Easing.OutCubic
                    }

                    ScrollBar.vertical: ScrollBar {
                        active: itemsList.moving || itemsList.flicking
                        policy: ScrollBar.AsNeeded
                    }

                    delegate: Item {
                        id: row
                        required property string cid
                        required property string ctext
                        required property int index

                        readonly property bool isSelected: root.selectedIndex === index
                        readonly property bool isPinned: root.pinnedIds.indexOf(cid) !== -1
                        readonly property bool prevPinned: index > 0 && root.pinnedIds.indexOf(root.filteredItems[index - 1].id) !== -1
                        readonly property bool showPinnedHeader: isPinned && !prevPinned
                        readonly property bool isImage: ctext.startsWith("[[ binary data")
                        readonly property bool isLink: ctext.startsWith("http://") || ctext.startsWith("https://") || ctext.startsWith("www.")
                        readonly property var imageMeta: isImage ? root.parseImageMeta(ctext) : null

                        width: itemsList.width
                        height: (showPinnedHeader ? 32 : 0) + itemCard.height

                        // "Pinned" section label above the first pinned card
                        Row {
                            visible: row.showPinnedHeader
                            x: 8
                            height: 32
                            spacing: 6
                            Glyph {
                                anchors.verticalCenter: parent.verticalCenter
                                text: ""
                                font.pixelSize: 16
                                color: Theme.primary
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Pinned"
                                color: Theme.primary
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.bold: true
                                font.letterSpacing: 0.8
                                renderType: Text.NativeRendering
                            }
                        }

                        Rectangle {
                            id: itemCard
                            y: row.showPinnedHeader ? 32 : 0
                            width: parent.width
                            height: Math.max(72, contentCol.implicitHeight + 28)
                            radius: 20
                            color: row.isSelected ? Theme.secondaryContainer : Theme.surfaceContainerHigh
                            Behavior on color { ColorAnimation { duration: 150 } }

                            // hover / press state layer
                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                color: row.isSelected ? Theme.colorOnSecondaryContainer : Theme.colorOnSurface
                                opacity: cardMouse.pressed ? 0.12 : (cardMouse.containsMouse ? 0.08 : 0)
                                Behavior on opacity { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                id: cardMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton) {
                                        root.deleteItem(row.cid);
                                    } else {
                                        root.selectedIndex = row.index;
                                        root.copyItem(row.cid);
                                    }
                                }
                            }

                            // leading type icon
                            Rectangle {
                                id: leading
                                anchors.left: parent.left
                                anchors.leftMargin: 16
                                anchors.verticalCenter: parent.verticalCenter
                                width: 40; height: 40; radius: 20
                                color: row.isSelected ? Theme.primary : Theme.primaryContainer
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Glyph {
                                    anchors.centerIn: parent
                                    text: row.isImage ? "" : (row.isLink ? "" : "")
                                    color: row.isSelected ? Theme.colorOnPrimary : Theme.colorOnPrimaryContainer
                                    font.pixelSize: 20
                                }
                            }

                            // content
                            Column {
                                id: contentCol
                                anchors.left: leading.right
                                anchors.leftMargin: 16
                                anchors.right: actions.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4

                                Text {
                                    visible: !row.isImage
                                    width: parent.width
                                    text: row.ctext
                                    textFormat: Text.PlainText
                                    color: row.isSelected ? Theme.colorOnSecondaryContainer : Theme.colorOnSurface
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 15
                                    lineHeight: 1.15
                                    maximumLineCount: row.isSelected ? 3 : 2
                                    wrapMode: Text.Wrap
                                    elide: Text.ElideRight
                                    renderType: Text.NativeRendering
                                }

                                Row {
                                    visible: row.isImage
                                    width: parent.width
                                    spacing: 14

                                    Rectangle {
                                        id: thumbBox
                                        width: 104; height: 64
                                        radius: 12
                                        color: Theme.surfaceContainerHighest
                                        clip: true

                                        Image {
                                            id: thumbImg
                                            anchors.fill: parent
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            cache: false
                                            source: row.isImage ? ("file:///tmp/cliphist_thumbs/" + row.cid + ".png?v=" + root.thumbsVersion) : ""
                                            visible: status === Image.Ready
                                        }
                                        Glyph {
                                            anchors.centerIn: parent
                                            visible: thumbImg.status !== Image.Ready
                                            text: ""
                                            color: Theme.outline
                                            font.pixelSize: 28
                                        }
                                    }

                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - thumbBox.width - parent.spacing
                                        spacing: 4
                                        Text {
                                            width: parent.width
                                            text: row.imageMeta ? row.imageMeta.title : "Image"
                                            color: row.isSelected ? Theme.colorOnSecondaryContainer : Theme.colorOnSurface
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 15
                                            font.bold: true
                                            elide: Text.ElideRight
                                            renderType: Text.NativeRendering
                                        }
                                        Text {
                                            width: parent.width
                                            text: row.imageMeta ? ((row.imageMeta.size ? row.imageMeta.size + " • " : "") + row.imageMeta.dimensions) : ""
                                            color: Theme.colorOnSurfaceVariant
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                            elide: Text.ElideRight
                                            renderType: Text.NativeRendering
                                        }
                                    }
                                }
                            }

                            // trailing actions: pin (toggle) + delete
                            Row {
                                id: actions
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 0

                                IconBtn {
                                    glyph: ""
                                    filled: row.isPinned
                                    activeFill: Theme.primary
                                    fg: row.isPinned ? Theme.primary : Theme.colorOnSurfaceVariant
                                    opacity: row.isPinned ? 1.0 : ((cardMouse.containsMouse || row.isSelected) ? 1.0 : 0.0)
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                    onClicked: root.togglePin(row.cid)
                                }
                                IconBtn {
                                    glyph: ""
                                    fg: Theme.error
                                    opacity: (cardMouse.containsMouse || row.isSelected) ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                    onClicked: root.deleteItem(row.cid)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
