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

                    // Right modules: Tray, Notifications, Audio, Language, Clock
                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        TrayModule {
                            barWindow: barWindow
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

            NotificationToasts {
                parentScreen: modelData
            }
        }
    }
}
