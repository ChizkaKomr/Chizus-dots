pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

Singleton {
    id: root

    property bool dnd: false
    property var notificationList: []
    property var timestamps: ({})
    property int count: notificationList.length
    property bool hasUnread: count > 0

    signal notificationReceived(var notification)
    signal toggleCenterRequested()

    function toggleDnd() {
        dnd = !dnd;
    }

    function updateList() {
        if (!notifServer.trackedNotifications || !notifServer.trackedNotifications.values) {
            notificationList = [];
            return;
        }
        // Newest notifications first
        notificationList = [...notifServer.trackedNotifications.values].reverse();
    }

    function dismiss(notif) {
        if (notif) {
            try {
                notif.dismiss();
            } catch (e) {}
        }
        updateList();
    }

    function clearAll() {
        if (!notifServer.trackedNotifications || !notifServer.trackedNotifications.values) return;
        const items = [...notifServer.trackedNotifications.values];
        for (const item of items) {
            try {
                item.dismiss();
            } catch (e) {}
        }
        notificationList = [];
    }

    function formatTimestamp(notifId) {
        const t = timestamps[notifId];
        if (!t) return "Just now";
        const diffSec = Math.floor((new Date() - t) / 1000);
        if (diffSec < 60) return "Just now";
        const diffMin = Math.floor(diffSec / 60);
        if (diffMin < 60) return diffMin + "m ago";
        const diffHours = Math.floor(diffMin / 60);
        if (diffHours < 24) return diffHours + "h ago";
        return Qt.formatDateTime(t, "hh:mm");
    }

    function playSound(notif) {
        const isCritical = Boolean(notif && (
            notif.urgency === NotificationUrgency.Critical ||
            (notif.hints && (notif.hints["urgency"] === 2 || notif.hints["urgency"] === "2" || notif.hints["urgency"] === "critical"))
        ));

        // In DND mode, silence normal notifications; allow critical notifications through
        if (root.dnd && !isCritical) {
            return;
        }

        const home = Quickshell.env("HOME") || "";
        const soundDir = home ? (home + "/.config/quickshell/sound") : (Quickshell.shellDir + "/sound");
        const soundFile = soundDir + (isCritical ? "/critical.mp3" : "/normal.mp3");

        Quickshell.execDetached([
            "sh", "-c",
            'file="$1"; dir="$(dirname "$file")"; name="$(basename "$file" .mp3)"; for ext in ".mp3" ".wav" ".ogg"; do target="$dir/$name$ext"; if [ -f "$target" ]; then (pw-play --media-role=Notification "$target" 2>/dev/null || paplay "$target" 2>/dev/null || mpv --no-video --really-quiet "$target" 2>/dev/null) & exit 0; fi; done',
            "--", soundFile
        ]);
    }

    NotificationServer {
        id: notifServer
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        actionsSupported: true
        imageSupported: true

        onNotification: notif => {
            notif.tracked = true;
            let map = Object.assign({}, root.timestamps);
            map[notif.id] = new Date();
            root.timestamps = map;
            root.updateList();
            root.playSound(notif);
            root.notificationReceived(notif);
        }
    }

    Connections {
        target: notifServer.trackedNotifications
        function onValuesChanged() {
            root.updateList();
        }
    }

    IpcHandler {
        target: "notifications"
        function toggle() {
            root.toggleCenterRequested();
        }
        function toggleDnd() {
            root.toggleDnd();
        }
        function clear() {
            root.clearAll();
        }
    }

    Component.onCompleted: {
        updateList();
    }
}
