import QtQuick
import ".."

// One month page: 6 weeks x 7 days (Monday first).
Grid {
    id: g
    property int year
    property int month
    property var today
    property var notes: ({})
    property string selectedKey: ""
    property real cellWidth: 40
    signal picked(string key)

    columns: 7
    rowSpacing: 2

    Repeater {
        model: 42
        delegate: Item {
            required property int index
            readonly property int offset: (new Date(g.year, g.month, 1).getDay() + 6) % 7
            readonly property var date: new Date(g.year, g.month, 1 - offset + index)
            readonly property bool inMonth: date.getMonth() === g.month
            readonly property bool isToday: date.getFullYear() === g.today.getFullYear()
                && date.getMonth() === g.today.getMonth()
                && date.getDate() === g.today.getDate()
            readonly property string dkey: Qt.formatDate(date, "yyyy-MM-dd")
            readonly property bool hasNotes: (g.notes[dkey] || []).length > 0
            readonly property bool selected: g.selectedKey === dkey

            width: g.cellWidth
            height: 40

            Rectangle {
                anchors.centerIn: parent
                width: 36; height: 36; radius: 18
                color: isToday ? Theme.primary
                     : dayMouse.containsMouse ? Theme.surfaceContainerHigh : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: date.getDate()
                    color: isToday ? Theme.colorOnPrimary
                         : inMonth ? Theme.colorOnSurface : Theme.outline
                    opacity: (inMonth || isToday) ? 1.0 : 0.55
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.bold: isToday
                    renderType: Text.NativeRendering
                }
                Rectangle {
                    visible: hasNotes
                    width: 5; height: 5; radius: 2.5
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 3
                    color: isToday ? Theme.colorOnPrimary : Theme.primary
                }
                MouseArea {
                    id: dayMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: g.picked(dkey)
                }
            }
        }
    }
}
