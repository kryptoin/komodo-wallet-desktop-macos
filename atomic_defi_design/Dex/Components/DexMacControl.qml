import QtQuick 2.15
import QtQuick.Controls 2.15
import "../Qaterial" as Qaterial
import QtQuick.Layouts 1.15
import App 1.0
import Dex.Themes 1.0 as Dex

Item
{
    anchors.fill: parent
    Item
    {
        width: parent.width
        height: 30

        Rectangle
        {
            width: parent.width
            height: 30
            border.color: Dex.CurrentTheme.lineSeparatorColor
            border.width: 1.5
            anchors.horizontalCenter: parent.horizontalCenter
            color: Dex.CurrentTheme.backgroundColor
        }

        MouseArea
        {
            // Manual drag: window.startSystemMove() only engages about half
            // the time on this Qt/macOS combination (press arrives but the
            // native move never starts), so move the frameless window by
            // hand. pressOffset stays valid because this area does not move
            // relative to the window while dragging.
            property point pressOffset: Qt.point(0, 0)
            property bool  dragged: false
            anchors.fill: parent
            anchors.rightMargin: 280
            onPressed: function(mouse)
            {
                pressOffset = Qt.point(mouse.x, mouse.y)
                dragged = false
            }
            onPositionChanged: function(mouse)
            {
                if (!pressed)
                    return
                const dx = mouse.x - pressOffset.x
                const dy = mouse.y - pressOffset.y
                if (Math.abs(dx) + Math.abs(dy) > 2)
                    dragged = true
                window.x += dx
                window.y += dy
            }
            onDoubleClicked:
            {
                // A retry click after a failed drag must not maximize: only
                // honor double-clicks that did not travel.
                if (!dragged)
                    window.toggleMaximize()
            }
        }
        DexMacosHeaderControl { anchors.verticalCenter: parent.verticalCenter }
    }

    Item
    {
        id: _left_resize
        height: parent.height
        width: 3
        MouseArea
        {
            onPressed: window.startSystemResize(Qt.LeftEdge)
            anchors.fill: parent
            cursorShape: "SizeHorCursor"
        }
    }

    Item
    {
        id: _right_resize
        height: parent.height
        anchors.right: parent.right
        width: 3
        MouseArea
        {
            onPressed: window.startSystemResize(Qt.RightEdge)
            cursorShape: "SizeHorCursor"
        }
    }
    Item
    {
        id: _bottom_resize
        height: 3
        width: parent.width
        anchors.bottom: parent.bottom
        MouseArea
        {
            onPressed: if (active) window.startSystemResize(Qt.BottomEdge)
            anchors.fill: parent
            cursorShape: "SizeVerCursor"
        }
    }
    Item
    {
        id: _top_resize
        height: 3
        width: parent.width
        MouseArea
        {
            onPressed: window.startSystemResize(Qt.TopEdge)
            anchors.fill: parent
            cursorShape: "SizeVerCursor"
        }
    }
    Item
    {
        id: _bottom_right_resize
        height: 6
        width: 6
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        MouseArea
        {
            onPressed: if (active) window.startSystemResize(Qt.BottomEdge | Qt.RightEdge)
            anchors.fill: parent
            cursorShape: "SizeFDiagCursor"
        }
    }
}
