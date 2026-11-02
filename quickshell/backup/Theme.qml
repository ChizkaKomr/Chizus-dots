pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Core legacy properties (backward compatible with all existing modules)
    property color background: "#101418"
    property color foreground: "#9fcafc"
    property color secondary: "#bac8db"
    property color alertRed: "#ffb4ab"

    // Material 3 Color Roles from Matugen
    property color primary: foreground
    property color colorOnPrimary: "#003257"
    property color primaryContainer: "#174974"
    property color colorOnPrimaryContainer: "#d1e4ff"

    property color colorOnSecondary: "#253140"
    property color secondaryContainer: "#3b4858"
    property color colorOnSecondaryContainer: "#d6e4f7"

    property color tertiary: "#d6bee5"
    property color colorOnTertiary: "#3a2948"
    property color tertiaryContainer: "#524060"
    property color colorOnTertiaryContainer: "#f2daff"

    property color error: alertRed
    property color colorOnError: "#690005"
    property color errorContainer: "#93000a"
    property color colorOnErrorContainer: "#ffdad6"

    property color surface: background
    property color colorOnSurface: "#e1e2e8"
    property color surfaceVariant: "#42474e"
    property color colorOnSurfaceVariant: "#c3c7cf"
    property color surfaceContainerLowest: "#0b0e13"
    property color surfaceContainerLow: "#191c20"
    property color surfaceContainer: "#1d2024"
    property color surfaceContainerHigh: "#272a2f"
    property color surfaceContainerHighest: "#32353a"

    property color outline: "#8c9199"
    property color outlineVariant: "#42474e"
    property color shadow: "#000000"

    // Typography & Metrics
    property string fontFamily: "Helvetica Rounded, Helvetica, Arial, sans-serif"
    property string iconFamily: "0xProto Nerd Font Mono, MesloLGS Nerd Font, Symbols Nerd Font, sans-serif"

    property int fontSize: 15
    property int pillHeight: 32
    property int pillRadius: 16

    FileView {
        id: colorFile
        path: (Quickshell.env("HOME") || "/home/chizuko") + "/.config/quickshell/just_colors.json"
        watchChanges: true
        onFileChanged: colorFile.reload()
        onLoaded: root.reloadColors()
    }

    function reloadColors() {
        try {
            const raw = colorFile.text();
            if (!raw || raw.trim().length === 0) return;
            const c = JSON.parse(raw);

            // Background & Primary Roles
            if (c.surface) {
                root.surface = c.surface;
                root.background = c.surface;
            } else if (c.background) {
                root.surface = c.background;
                root.background = c.background;
            }

            if (c.primary) {
                root.primary = c.primary;
                root.foreground = c.primary;
            } else if (c.foreground) {
                root.primary = c.foreground;
                root.foreground = c.foreground;
            }

            if (c.secondary) root.secondary = c.secondary;
            if (c.error) {
                root.alertRed = c.error;
                root.error = c.error;
            }
            if (c.on_error) root.colorOnError = c.on_error;
            if (c.error_container) root.errorContainer = c.error_container;
            if (c.on_error_container) root.colorOnErrorContainer = c.on_error_container;

            if (c.on_primary) root.colorOnPrimary = c.on_primary;
            if (c.primary_container) root.primaryContainer = c.primary_container;
            if (c.on_primary_container) root.colorOnPrimaryContainer = c.on_primary_container;

            if (c.on_secondary) root.colorOnSecondary = c.on_secondary;
            if (c.secondary_container) root.secondaryContainer = c.secondary_container;
            if (c.on_secondary_container) root.colorOnSecondaryContainer = c.on_secondary_container;

            if (c.tertiary) root.tertiary = c.tertiary;
            if (c.on_tertiary) root.colorOnTertiary = c.on_tertiary;
            if (c.tertiary_container) root.tertiaryContainer = c.tertiary_container;
            if (c.on_tertiary_container) root.colorOnTertiaryContainer = c.on_tertiary_container;

            if (c.on_surface) root.colorOnSurface = c.on_surface;
            if (c.surface_variant) root.surfaceVariant = c.surface_variant;
            if (c.on_surface_variant) root.colorOnSurfaceVariant = c.on_surface_variant;
            if (c.surface_container_lowest) root.surfaceContainerLowest = c.surface_container_lowest;
            if (c.surface_container_low) root.surfaceContainerLow = c.surface_container_low;
            if (c.surface_container) root.surfaceContainer = c.surface_container;
            if (c.surface_container_high) root.surfaceContainerHigh = c.surface_container_high;
            if (c.surface_container_highest) root.surfaceContainerHighest = c.surface_container_highest;

            if (c.outline) root.outline = c.outline;
            if (c.outline_variant) root.outlineVariant = c.outline_variant;
            if (c.shadow) root.shadow = c.shadow;
        } catch (e) {
            console.warn("Theme: Failed to parse just_colors.json:", e);
        }
    }

    Component.onCompleted: {
        reloadColors();
    }
}
