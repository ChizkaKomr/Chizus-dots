pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property color background: "#0e1513"
    property color foreground: "#83d5c5"
    property color secondary: "#ccc2db"
    property color alertRed: "#ff3b30"

    property string fontFamily: "Helvetica Rounded, Helvetica, Arial, sans-serif"
    property string iconFamily: "0xProto Nerd Font Mono, MesloLGS Nerd Font, Symbols Nerd Font, sans-serif"

    property int fontSize: 15
    property int pillHeight: 32
    property int pillRadius: 16

    FileView {
        id: colorFile
	path: "/home/chizuko/.config/waybar/matugen_colors.css"
	watchChanges: true
	onFileChanged: colorFile.reload()
        onLoaded: root.reloadColors()
    }

    function reloadColors() {
        try {
            const content = colorFile.text();
            const bgMatch = content.match(/@define-color\s+background\s+(#[0-9a-fA-F]+);/);
            const fgMatch = content.match(/@define-color\s+foreground\s+(#[0-9a-fA-F]+);/);
            const secMatch = content.match(/@define-color\s+secondary\s+(#[0-9a-fA-F]+);/);
            if (bgMatch && bgMatch[1]) root.background = bgMatch[1];
            if (fgMatch && fgMatch[1]) root.foreground = fgMatch[1];
            if (secMatch && secMatch[1]) root.secondary = secMatch[1];
        } catch (e) {
            // Keep defaults
        }
    }

    Component.onCompleted: {
        reloadColors();
    }
}
