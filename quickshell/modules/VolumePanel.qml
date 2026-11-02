import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import ".."

Rectangle {
    id: root

    property int currentTab: 0 // 0: Output, 1: Input

    implicitWidth: 440
    implicitHeight: 520

    color: Theme.background
    radius: 26
    clip: true

    border.color: Theme.outlineVariant
    border.width: 1

    // Prevent clicks inside the panel from propagating to the dismiss backdrop
    MouseArea {
        anchors.fill: parent
        onPressed: mouse => { mouse.accepted = true; }
    }

    // -------------------------------------------------------------
    // PipeWire Object Tracking: Binds and tracks all nodes reactively
    // -------------------------------------------------------------
    PwObjectTracker {
        id: pwTracker
        objects: root.trackedList
    }

    readonly property var allNodes: Pipewire.nodes ? Pipewire.nodes.values : []

    readonly property var trackedList: {
        const list = [];
        if (Pipewire.defaultAudioSink) list.push(Pipewire.defaultAudioSink);
        if (Pipewire.defaultAudioSource) list.push(Pipewire.defaultAudioSource);
        if (root.allNodes) {
            for (let i = 0; i < root.allNodes.length; i++) {
                const n = root.allNodes[i];
                if (n && n.audio) list.push(n);
            }
        }
        return list;
    }

    // Helper Reactive Lists
    readonly property var outputDevices: {
        const list = [];
        const nodes = root.allNodes;
        for (let i = 0; i < nodes.length; i++) {
            const n = nodes[i];
            if (n && n.isSink && !n.isStream && n.audio) list.push(n);
        }
        return list;
    }

    readonly property var outputStreams: {
        const list = [];
        const nodes = root.allNodes;
        for (let i = 0; i < nodes.length; i++) {
            const n = nodes[i];
            if (n && n.isSink && n.isStream && n.audio) list.push(n);
        }
        return list;
    }

    readonly property var inputDevices: {
        const list = [];
        const nodes = root.allNodes;
        for (let i = 0; i < nodes.length; i++) {
            const n = nodes[i];
            if (n && !n.isSink && !n.isStream && n.audio) list.push(n);
        }
        return list;
    }

    readonly property var inputStreams: {
        const list = [];
        const nodes = root.allNodes;
        for (let i = 0; i < nodes.length; i++) {
            const n = nodes[i];
            if (n && !n.isSink && n.isStream && n.audio) list.push(n);
        }
        return list;
    }

    Column {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 16

        // =========================================================
        // 1. PINNED HEADER: Master / System Volume Slider
        // =========================================================
        Rectangle {
            id: masterCard
            width: parent.width
            height: masterCol.implicitHeight + 24
            radius: 18
            color: Theme.surfaceContainerHighest
            border.color: Theme.outlineVariant
            border.width: 1

            Column {
                id: masterCol
                anchors.centerIn: parent
                width: parent.width - 24
                spacing: 8

                Row {
                    width: parent.width
                    spacing: 8

                    Text {
                        text: "MASTER VOLUME"
                        color: Theme.colorOnSurfaceVariant
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: true
                        font.letterSpacing: 1.0
                        renderType: Text.NativeRendering
                    }

                    Text {
                        width: parent.width - 120
                        text: Pipewire.defaultAudioSink ? (Pipewire.defaultAudioSink.description || Pipewire.defaultAudioSink.name) : "No Default Sink"
                        color: Theme.colorOnSurface
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        renderType: Text.NativeRendering
                    }
                }

                VolumeSlider {
                    width: parent.width
                    node: Pipewire.defaultAudioSink
                    title: "System Audio"
                    isInput: false
                }
            }
        }

        // =========================================================
        // 2. CATEGORY TABS (Matching the Figma Sketch)
        // =========================================================
        Rectangle {
            id: tabContainer
            width: parent.width
            height: 52
            radius: 26
            color: Theme.surfaceContainerHigh
            border.color: Theme.outlineVariant
            border.width: 1

            // Animated Tab Highlight Pill
            Rectangle {
                id: tabHighlight
                width: (tabContainer.width - 8) / 2
                height: tabContainer.height - 8
                y: 4
                x: 4 + root.currentTab * width
                radius: 22
                color: Theme.primary

                Behavior on x {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }
            }

            Row {
                anchors.fill: parent

                // Output Tab
                Item {
                    width: parent.width / 2
                    height: parent.height

                    Row {
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: ""
                            color: root.currentTab === 0 ? Theme.colorOnPrimary : Theme.colorOnSurfaceVariant
                            font.family: Theme.iconFamily
                            font.pixelSize: 18
                            renderType: Text.NativeRendering

                            Behavior on color {
                                ColorAnimation { duration: 180 }
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "output"
                            color: root.currentTab === 0 ? Theme.colorOnPrimary : Theme.colorOnSurfaceVariant
                            font.family: Theme.fontFamily
                            font.pixelSize: 19
                            font.bold: true
                            renderType: Text.NativeRendering

                            Behavior on color {
                                ColorAnimation { duration: 180 }
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.currentTab = 0
                    }
                }

                // Input Tab
                Item {
                    width: parent.width / 2
                    height: parent.height

                    Row {
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰍬"
                            color: root.currentTab === 1 ? Theme.colorOnPrimary : Theme.colorOnSurfaceVariant
                            font.family: Theme.iconFamily
                            font.pixelSize: 18
                            renderType: Text.NativeRendering

                            Behavior on color {
                                ColorAnimation { duration: 180 }
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "input"
                            color: root.currentTab === 1 ? Theme.colorOnPrimary : Theme.colorOnSurfaceVariant
                            font.family: Theme.fontFamily
                            font.pixelSize: 19
                            font.bold: true
                            renderType: Text.NativeRendering

                            Behavior on color {
                                ColorAnimation { duration: 180 }
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.currentTab = 1
                    }
                }
            }
        }

        // =========================================================
        // 3. TAB CONTENT (Output & Input Sections)
        // =========================================================
        Item {
            id: contentArea
            width: parent.width
            height: parent.height - masterCard.height - tabContainer.height - (parent.spacing * 2)
            clip: true

            // -----------------------------------------------------
            // SECTION 1: OUTPUT
            // -----------------------------------------------------
            Flickable {
                id: outputFlick
                anchors.fill: parent
                contentWidth: width
                contentHeight: outputContent.implicitHeight + 20
                visible: root.currentTab === 0
                opacity: root.currentTab === 0 ? 1.0 : 0.0
                boundsBehavior: Flickable.StopAtBounds

                Behavior on opacity {
                    NumberAnimation { duration: 180 }
                }

                Column {
                    id: outputContent
                    width: parent.width
                    spacing: 14

                    // Applications List
                    Column {
                        width: parent.width
                        spacing: 10

                        Text {
                            text: "APPLICATIONS"
                            color: Theme.colorOnSurfaceVariant
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: true
                            font.letterSpacing: 1.0
                            renderType: Text.NativeRendering
                        }

                        Repeater {
                            model: root.outputStreams
                            delegate: VolumeSlider {
                                required property var modelData
                                width: outputContent.width
                                node: modelData
                                title: (modelData.properties && modelData.properties["application.name"]) ? modelData.properties["application.name"] : (modelData.name || "App Stream")
                                iconName: (modelData.properties && modelData.properties["application.icon-name"]) ? modelData.properties["application.icon-name"] : ""
                                isAppStream: true
                                isInput: false
                            }
                        }

                        // Placeholder if no apps are playing
                        Item {
                            width: parent.width
                            height: 70
                            visible: root.outputStreams.length === 0

                            Column {
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "󰝛"
                                    color: Theme.colorOnSurfaceVariant
                                    font.family: Theme.iconFamily
                                    font.pixelSize: 24
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "No active application audio streams"
                                    color: Theme.colorOnSurfaceVariant
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                }
                            }
                        }
                    }
                }
            }

            // -----------------------------------------------------
            // SECTION 2: INPUT
            // -----------------------------------------------------
            Flickable {
                id: inputFlick
                anchors.fill: parent
                contentWidth: width
                contentHeight: inputContent.implicitHeight + 20
                visible: root.currentTab === 1
                opacity: root.currentTab === 1 ? 1.0 : 0.0
                boundsBehavior: Flickable.StopAtBounds

                Behavior on opacity {
                    NumberAnimation { duration: 180 }
                }

                Column {
                    id: inputContent
                    width: parent.width
                    spacing: 18

                    // 1. Input Device Selector (Microphone list / picker)
                    Column {
                        width: parent.width
                        spacing: 10

                        Text {
                            text: "SELECT INPUT DEVICE"
                            color: Theme.colorOnSurfaceVariant
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: true
                            font.letterSpacing: 1.0
                            renderType: Text.NativeRendering
                        }

                        Repeater {
                            model: root.inputDevices
                            delegate: Rectangle {
                                id: inputItem
                                required property var modelData
                                readonly property bool isSelected: Pipewire.defaultAudioSource === modelData

                                width: inputContent.width
                                height: 50
                                radius: 14
                                color: isSelected ? Theme.secondaryContainer : Theme.surfaceContainerHigh
                                border.color: isSelected ? Theme.primary : Theme.outlineVariant
                                border.width: isSelected ? 1.5 : 1

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    spacing: 12

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: isSelected ? "󰍬" : "󰍭"
                                        color: isSelected ? Theme.colorOnSecondaryContainer : Theme.colorOnSurfaceVariant
                                        font.family: Theme.iconFamily
                                        font.pixelSize: 18
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 70
                                        text: modelData.description || modelData.name
                                        color: isSelected ? Theme.colorOnSecondaryContainer : Theme.colorOnSurfaceVariant
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 14
                                        font.bold: isSelected
                                        elide: Text.ElideRight
                                    }

                                    // Active check indicator
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 18
                                        height: 18
                                        radius: 9
                                        color: isSelected ? Theme.primary : "transparent"
                                        border.color: isSelected ? Theme.primary : Theme.outline
                                        border.width: 2

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 8
                                            height: 8
                                            radius: 4
                                            color: Theme.colorOnPrimary
                                            visible: isSelected
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Pipewire.preferredDefaultAudioSource = modelData;
                                    }
                                }
                            }
                        }
                    }

                    // 2. Active Input Volume Slider
                    Column {
                        width: parent.width
                        spacing: 10

                        Text {
                            text: "INPUT VOLUME"
                            color: Theme.colorOnSurfaceVariant
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: true
                            font.letterSpacing: 1.0
                            renderType: Text.NativeRendering
                        }

                        VolumeSlider {
                            width: inputContent.width
                            node: Pipewire.defaultAudioSource
                            title: Pipewire.defaultAudioSource ? (Pipewire.defaultAudioSource.description || Pipewire.defaultAudioSource.name) : "Microphone"
                            isInput: true
                        }
                    }

                    // 3. Recording Applications (Per-App Input Streams)
                    Column {
                        width: parent.width
                        spacing: 10
                        visible: root.inputStreams.length > 0

                        Rectangle {
                            width: parent.width
                            height: 1
                            color: Theme.outlineVariant
                        }

                        Text {
                            text: "RECORDING APPLICATIONS"
                            color: Theme.colorOnSurfaceVariant
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: true
                            font.letterSpacing: 1.0
                            renderType: Text.NativeRendering
                        }

                        Repeater {
                            model: root.inputStreams
                            delegate: VolumeSlider {
                                required property var modelData
                                width: inputContent.width
                                node: modelData
                                title: (modelData.properties && modelData.properties["application.name"]) ? modelData.properties["application.name"] : (modelData.name || "Recording Stream")
                                iconName: (modelData.properties && modelData.properties["application.icon-name"]) ? modelData.properties["application.icon-name"] : ""
                                isAppStream: true
                                isInput: true
                            }
                        }
                    }
                }
            }
        }
    }
}
