import QtQuick
import QtQuick.Controls
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

        // Sort: pinned first, then preserve history order
        filtered.sort((a, b) => {
            const aPin = root.pinnedIds.indexOf(a.id) !== -1;
            const bPin = root.pinnedIds.indexOf(b.id) !== -1;
            if (aPin && !bPin) return -1;
            if (!aPin && bPin) return 1;
            return 0;
        });

        root.filteredItems = filtered;
        root.selectedIndex = Math.min(root.selectedIndex, Math.max(0, filtered.length - 1));
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

    function getRelativeTime(index) {
        if (index === 0) return "Just now";
        if (index < 3) return "6m ago";
        if (index < 6) return "3h ago";
        if (index < 12) return "Yesterday";
        return Math.floor(index / 6) + "d ago";
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
    // Main Clipboard Dialog Window
    // =============================================================
    Rectangle {
        id: dialog
        anchors.horizontalCenter: parent.horizontalCenter
        width: 720
        height: 580
        radius: 20
        color: root.colBg
        border.color: root.colBorder
        border.width: 1.5
        clip: true

        readonly property real targetY: Math.round((root.height - height) / 2)
        y: targetY + (1.0 - root.animProgress) * (root.height - targetY + 40)
        opacity: root.animProgress

        // Consume clicks inside dialog
        MouseArea {
            anchors.fill: parent
            onPressed: mouse => { mouse.accepted = true; }
        }

        // Keyboard handler for list navigation
        Keys.onUpPressed: event => {
            event.accepted = true;
            root.selectPrevious();
        }
        Keys.onDownPressed: event => {
            event.accepted = true;
            root.selectNext();
        }
        Keys.onReturnPressed: event => {
            event.accepted = true;
            root.copySelected();
        }
        Keys.onEnterPressed: event => {
            event.accepted = true;
            root.copySelected();
        }
        Keys.onEscapePressed: event => {
            event.accepted = true;
            root.close();
        }
        Keys.onDeletePressed: event => {
            if (root.filteredItems.length > 0 && root.selectedIndex >= 0 && root.selectedIndex < root.filteredItems.length) {
                event.accepted = true;
                root.deleteItem(root.filteredItems[root.selectedIndex].id);
            }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            // ---------------------------------------------------------
            // 1. Header: Title & Clear All
            // ---------------------------------------------------------
            Row {
                width: parent.width

                Text {
                    width: parent.width - clearAllBtn.width
                    text: "Clipboard History"
                    color: root.colTextPrimary
                    font.family: Theme.fontFamily
                    font.pixelSize: 19
                    font.bold: true
                    renderType: Text.NativeRendering
                }

                // Clear All Button
                Rectangle {
                    id: clearAllBtn
                    width: clearAllRow.implicitWidth + 14
                    height: 28
                    radius: 8
                    color: clearMouse.containsMouse ? Qt.rgba(root.colDanger.r, root.colDanger.g, root.colDanger.b, 0.2) : "transparent"

                    Row {
                        id: clearAllRow
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: ""
                            color: clearMouse.containsMouse ? root.colDanger : root.colAccent
                            font.family: Theme.iconFamily
                            font.pixelSize: 14
                            renderType: Text.NativeRendering
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Clear All"
                            color: clearMouse.containsMouse ? root.colDanger : root.colAccent
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
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
            // 2. Search Bar
            // ---------------------------------------------------------
            Rectangle {
                id: searchBar
                width: parent.width
                height: 44
                radius: 12
                color: root.colInputBg
                border.color: searchField.activeFocus ? root.colAccent : root.colBorder
                border.width: 1

                Behavior on border.color {
                    ColorAnimation { duration: 150 }
                }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 12
                    spacing: 10

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: ""
                        color: root.colTextMuted
                        font.family: Theme.iconFamily
                        font.pixelSize: 15
                        renderType: Text.NativeRendering
                    }

                    TextInput {
                        id: searchField
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 60
                        color: root.colTextPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        selectByMouse: true
                        renderType: Text.NativeRendering

                        Text {
                            text: "Search history..."
                            color: root.colTextDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            visible: !searchField.text
                            anchors.verticalCenter: parent.verticalCenter
                            renderType: Text.NativeRendering
                        }

                        onTextChanged: {
                            root.selectedIndex = 0;
                            itemsList.contentY = 0;
                            root.applyFilter();
                        }

                        Keys.onUpPressed: event => {
                            event.accepted = true;
                            root.selectPrevious();
                        }
                        Keys.onDownPressed: event => {
                            event.accepted = true;
                            root.selectNext();
                        }
                        Keys.onReturnPressed: event => {
                            event.accepted = true;
                            root.copySelected();
                        }
                        Keys.onEnterPressed: event => {
                            event.accepted = true;
                            root.copySelected();
                        }
                        Keys.onEscapePressed: event => {
                            event.accepted = true;
                            root.close();
                        }
                        Keys.onDeletePressed: event => {
                            if (searchField.text.length === 0 && root.filteredItems.length > 0) {
                                event.accepted = true;
                                root.deleteItem(root.filteredItems[root.selectedIndex].id);
                            }
                        }
                    }

                    // Clear search button
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: searchField.text.length > 0
                        text: "✕"
                        color: root.colTextMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        renderType: Text.NativeRendering

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                searchField.text = "";
                                searchField.forceActiveFocus();
                            }
                        }
                    }
                }
            }

            // ---------------------------------------------------------
            // 3. Category Filter Chips
            // ---------------------------------------------------------
            Row {
                width: parent.width
                spacing: 8

                // Text Chip
                Rectangle {
                    readonly property bool isActive: root.activeFilter === "text"
                    width: textRow.implicitWidth + 24
                    height: 32
                    radius: 12
                    color: isActive ? Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.2) : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.08)
                    border.color: isActive ? root.colAccent : root.colBorder
                    border.width: isActive ? 1.5 : 1

                    Row {
                        id: textRow
                        anchors.centerIn: parent
                        spacing: 7

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: ""
                            color: parent.parent.isActive ? root.colAccent : root.colTextMuted
                            font.family: Theme.iconFamily
                            font.pixelSize: 13
                            renderType: Text.NativeRendering
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Text"
                            color: parent.parent.isActive ? root.colAccent : root.colTextMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            renderType: Text.NativeRendering
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.activeFilter = root.activeFilter === "text" ? "all" : "text";
                            root.selectedIndex = 0;
                            itemsList.contentY = 0;
                            root.applyFilter();
                        }
                    }
                }

                // Images Chip
                Rectangle {
                    readonly property bool isActive: root.activeFilter === "images"
                    width: imgRow.implicitWidth + 24
                    height: 32
                    radius: 12
                    color: isActive ? Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.2) : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.08)
                    border.color: isActive ? root.colAccent : root.colBorder
                    border.width: isActive ? 1.5 : 1

                    Row {
                        id: imgRow
                        anchors.centerIn: parent
                        spacing: 7

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: ""
                            color: parent.parent.isActive ? root.colAccent : root.colTextMuted
                            font.family: Theme.iconFamily
                            font.pixelSize: 13
                            renderType: Text.NativeRendering
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Images"
                            color: parent.parent.isActive ? root.colAccent : root.colTextMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            renderType: Text.NativeRendering
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.activeFilter = root.activeFilter === "images" ? "all" : "images";
                            root.selectedIndex = 0;
                            itemsList.contentY = 0;
                            root.applyFilter();
                        }
                    }
                }

                // Links Chip
                Rectangle {
                    readonly property bool isActive: root.activeFilter === "links"
                    width: linkRow.implicitWidth + 24
                    height: 32
                    radius: 12
                    color: isActive ? Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.2) : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.08)
                    border.color: isActive ? root.colAccent : root.colBorder
                    border.width: isActive ? 1.5 : 1

                    Row {
                        id: linkRow
                        anchors.centerIn: parent
                        spacing: 7

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: ""
                            color: parent.parent.isActive ? root.colAccent : root.colTextMuted
                            font.family: Theme.iconFamily
                            font.pixelSize: 13
                            renderType: Text.NativeRendering
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Links"
                            color: parent.parent.isActive ? root.colAccent : root.colTextMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            renderType: Text.NativeRendering
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.activeFilter = root.activeFilter === "links" ? "all" : "links";
                            root.selectedIndex = 0;
                            itemsList.contentY = 0;
                            root.applyFilter();
                        }
                    }
                }

                // All Chip (replacing Clear Filters)
                Rectangle {
                    readonly property bool isActive: root.activeFilter === "all"
                    width: allRow.implicitWidth + 24
                    height: 32
                    radius: 12
                    color: isActive ? Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.2) : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.08)
                    border.color: isActive ? root.colAccent : root.colBorder
                    border.width: isActive ? 1.5 : 1

                    Row {
                        id: allRow
                        anchors.centerIn: parent
                        spacing: 7

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: ""
                            color: parent.parent.isActive ? root.colAccent : root.colTextMuted
                            font.family: Theme.iconFamily
                            font.pixelSize: 13
                            renderType: Text.NativeRendering
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "All"
                            color: parent.parent.isActive ? root.colAccent : root.colTextMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            renderType: Text.NativeRendering
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.activeFilter = "all";
                            root.selectedIndex = 0;
                            itemsList.contentY = 0;
                            root.applyFilter();
                        }
                    }
                }
            }

            // ---------------------------------------------------------
            // 4. Clipboard Items List
            // ---------------------------------------------------------
            Item {
                width: parent.width
                height: parent.height - 180
                clip: true

                // Empty Placeholder
                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    visible: root.filteredItems.length === 0

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "󰅍"
                        color: root.colTextDim
                        font.family: Theme.iconFamily
                        font.pixelSize: 36
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "No clipboard items found"
                        color: root.colTextMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                    }
                }

                ListView {
                    id: itemsList
                    anchors.fill: parent
                    spacing: 10
                    model: root.filteredItems
                    boundsBehavior: Flickable.StopAtBounds

                    NumberAnimation {
                        id: scrollAnim
                        target: itemsList
                        property: "contentY"
                        duration: 140
                        easing.type: Easing.OutQuad
                    }

                    ScrollBar.vertical: ScrollBar {
                        active: itemsList.moving || itemsList.flicking
                        policy: ScrollBar.AsNeeded
                    }

                    delegate: Rectangle {
                        id: itemCard
                        required property var modelData
                        required property int index

                        readonly property bool isSelected: root.selectedIndex === index
                        readonly property bool isPinned: root.pinnedIds.indexOf(modelData.id) !== -1
                        readonly property bool isImage: modelData.text.startsWith("[[ binary data")
                        readonly property bool isLink: modelData.text.startsWith("http://") || modelData.text.startsWith("https://") || modelData.text.startsWith("www.")
                        readonly property var imageMeta: isImage ? root.parseImageMeta(modelData.text) : null

                        width: itemsList.width
                        height: Math.max(76, contentCol.implicitHeight + 24)
                        radius: 14
                        color: isSelected ? root.colCardHover : (cardMouse.containsMouse ? Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.1) : root.colCardBg)
                        border.color: isSelected ? root.colAccent : (cardMouse.containsMouse ? Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.35) : "transparent")
                        border.width: isSelected ? 1.5 : (cardMouse.containsMouse ? 1 : 0)

                        Behavior on border.color {
                            ColorAnimation { duration: 120 }
                        }
                        Behavior on color {
                            ColorAnimation { duration: 120 }
                        }

                        // Card background click & right-click delete
                        MouseArea {
                            id: cardMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) {
                                    root.deleteItem(itemCard.modelData.id);
                                } else {
                                    root.selectedIndex = itemCard.index;
                                    root.copyItem(itemCard.modelData.id);
                                }
                            }
                        }

                        Row {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 14

                            // Type Icon Container
                            Rectangle {
                                width: 36
                                height: 36
                                radius: 10
                                color: Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.12)
                                anchors.top: parent.top

                                Text {
                                    anchors.centerIn: parent
                                    text: itemCard.isImage ? "" : (itemCard.isLink ? "" : "")
                                    color: root.colAccent
                                    font.family: Theme.iconFamily
                                    font.pixelSize: 17
                                    renderType: Text.NativeRendering
                                }
                            }

                            // Content Details Column
                            Column {
                                id: contentCol
                                width: parent.width - 36 - 36 - (parent.spacing * 2)
                                spacing: 6

                                // Preview Text for Text / Links
                                Text {
                                    visible: !itemCard.isImage
                                    width: parent.width
                                    text: itemCard.modelData.text
                                    textFormat: Text.PlainText
                                    color: itemCard.isSelected ? root.colTextPrimary : Qt.rgba(root.colTextPrimary.r, root.colTextPrimary.g, root.colTextPrimary.b, 0.9)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 14
                                    lineHeight: 1.2
                                    maximumLineCount: itemCard.isSelected ? 3 : 2
                                    wrapMode: Text.Wrap
                                    elide: Text.ElideRight
                                    renderType: Text.NativeRendering
                                }

                                // Visual Thumbnail Preview Layout for Images
                                Row {
                                    visible: itemCard.isImage
                                    width: parent.width
                                    spacing: 12

                                    Rectangle {
                                        id: thumbBox
                                        width: 96
                                        height: 60
                                        radius: 8
                                        color: root.colInputBg
                                        border.color: itemCard.isSelected ? root.colAccent : root.colBorder
                                        border.width: 1
                                        clip: true

                                        Image {
                                            id: thumbImg
                                            anchors.fill: parent
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            cache: false
                                            source: itemCard.isImage ? ("file:///tmp/cliphist_thumbs/" + itemCard.modelData.id + ".png?v=" + root.thumbsVersion) : ""
                                            visible: status === Image.Ready
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            visible: thumbImg.status !== Image.Ready
                                            text: ""
                                            color: root.colTextDim
                                            font.family: Theme.iconFamily
                                            font.pixelSize: 22
                                            renderType: Text.NativeRendering
                                        }
                                    }

                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - thumbBox.width - parent.spacing
                                        spacing: 4

                                        Text {
                                            width: parent.width
                                            text: itemCard.imageMeta ? itemCard.imageMeta.title : "Image"
                                            color: itemCard.isSelected ? root.colTextPrimary : Qt.rgba(root.colTextPrimary.r, root.colTextPrimary.g, root.colTextPrimary.b, 0.95)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 14
                                            font.bold: true
                                            elide: Text.ElideRight
                                            renderType: Text.NativeRendering
                                        }

                                        Text {
                                            width: parent.width
                                            text: itemCard.imageMeta ? ((itemCard.imageMeta.size ? itemCard.imageMeta.size + " • " : "") + itemCard.imageMeta.dimensions) : ""
                                            color: root.colTextMuted
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                            elide: Text.ElideRight
                                            renderType: Text.NativeRendering
                                        }
                                    }
                                }

                                // Timestamp Tag (boxed pill matching photo example)
                                Rectangle {
                                    height: 20
                                    width: timeRow.implicitWidth + 14
                                    radius: 6
                                    color: Qt.rgba(0, 0, 0, 0.28)
                                    border.color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.1)
                                    border.width: 1

                                    Row {
                                        id: timeRow
                                        anchors.centerIn: parent
                                        spacing: 5

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: ""
                                            color: root.colTextMuted
                                            font.family: Theme.iconFamily
                                            font.pixelSize: 11
                                            renderType: Text.NativeRendering
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: root.getRelativeTime(itemCard.index)
                                            color: root.colTextMuted
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            renderType: Text.NativeRendering
                                        }
                                    }
                                }
                            }

                            // Right Action Column: Pin Button on top, Delete Button below it
                            Item {
                                width: 26
                                height: parent.height
                                anchors.top: parent.top

                                // Pin Button (replacing Plus button at top)
                                Rectangle {
                                    id: pinBtn
                                    anchors.top: parent.top
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 26
                                    height: 26
                                    radius: 13
                                    color: itemCard.isPinned ? root.colAccent : (pinMouse.containsMouse ? Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.2) : "transparent")
                                    opacity: itemCard.isPinned ? 1.0 : ((cardMouse.containsMouse || itemCard.isSelected) ? 1.0 : 0.0)

                                    Behavior on opacity {
                                        NumberAnimation { duration: 120 }
                                    }
                                    Behavior on color {
                                        ColorAnimation { duration: 120 }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: ""
                                        color: itemCard.isPinned ? root.colBg : (pinMouse.containsMouse ? root.colAccent : root.colTextDim)
                                        font.family: Theme.iconFamily
                                        font.pixelSize: 13
                                        renderType: Text.NativeRendering
                                    }

                                    MouseArea {
                                        id: pinMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.togglePin(itemCard.modelData.id)
                                    }
                                }

                                // Delete Button (below Pin button)
                                Rectangle {
                                    id: deleteBtn
                                    anchors.bottom: parent.bottom
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 26
                                    height: 26
                                    radius: 7
                                    color: deleteMouse.containsMouse ? Qt.rgba(root.colDanger.r, root.colDanger.g, root.colDanger.b, 0.2) : "transparent"
                                    opacity: (cardMouse.containsMouse || itemCard.isSelected) ? 1.0 : 0.0

                                    Behavior on opacity {
                                        NumberAnimation { duration: 120 }
                                    }
                                    Behavior on color {
                                        ColorAnimation { duration: 120 }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: ""
                                        color: deleteMouse.containsMouse ? root.colDanger : root.colTextDim
                                        font.family: Theme.iconFamily
                                        font.pixelSize: 13
                                        renderType: Text.NativeRendering
                                    }

                                    MouseArea {
                                        id: deleteMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.deleteItem(itemCard.modelData.id)
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
