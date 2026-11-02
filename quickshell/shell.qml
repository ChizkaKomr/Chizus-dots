//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Wayland
import "modules"

ShellRoot {
    Variants {
        model: Quickshell.screens

        Scope {
            required property var modelData

            PanelWindow {
                id: barWindow
                screen: modelData

                anchors {
                    top: true
                    left: true
                    right: true
                }

                implicitHeight: 44
                color: "transparent"

                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.namespace: "quickshell-bar"

                Item {
                    anchors.fill: parent

                    // Left module: Power / Moon
                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        PowerModule {}
                    }

                    // Center module: Workspaces
                    Row {
                        anchors.centerIn: parent
                        spacing: 6

                        WorkspacesModule {}
                    }

                    // Right modules: Tray, Notifications, Audio, Language, Clock — all in one pill
                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter

                        color: Theme.background
                        radius: Theme.pillRadius
                        implicitHeight: Theme.pillHeight
                        implicitWidth: rightRow.implicitWidth + 20

                        Row {
                            id: rightRow
                            anchors.centerIn: parent
                            spacing: 6

                            TrayModule {
                                barWindow: barWindow
                            }
                            Rectangle {
                                width: 2
                                height: Theme.pillHeight * 0.55 - 1
                                radius: 1
                                color: Theme.secondaryContainer
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            NotificationModule {
                                barWindow: barWindow
                            }
                            AudioModule {
                                barWindow: barWindow
                            }
                            LanguageModule {}
                            ClockModule {}
                        }
                    }
                }
            }

            NotificationToasts {
                parentScreen: modelData
            }
        }
    }

    ClipboardManager {
        id: clipboardManager
    }
}
