import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15

import AtomicDEX.TradingMode 1.0
import App 1.0
import Dex.Themes 1.0 as Dex
import "../../../Components"

// Simple/Pro toggle group.
//
// NOTE (ported from the 0.6.1 tree): the original also hosted a "Pro View
// Settings" popup toggling individual Pro panels (ticker selectors, order
// book, ...). Those panel ids are not exposed by this tree's ProView, so
// only the mode toggle is ported; the popup is intentionally dropped.
Item
{
    Item
    {
        width: 350
        height: parent.height

        // Simple/Pro select cursor
        Rectangle
        {
            id: cursorRect
            width: _simpleLabel.width + 28
            height: _simpleLabel.height + 14
            radius: 16
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: API.app.trading_pg.current_trading_mode == TradingMode.Simple ? _simpleLabel.horizontalCenter : _proLabel.horizontalCenter
            color: Dex.CurrentTheme.tabSelectedColor
        }

        DexLabel
        {
            id: _simpleLabel
            text: "Simple"
            color: API.app.trading_pg.current_trading_mode == TradingMode.Simple ? Dex.CurrentTheme.foregroundColor : Dex.CurrentTheme.foregroundColor2
            anchors.leftMargin: 16
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: 14
            font.weight: Font.Bold

            DefaultMouseArea
            {
                id: simple_area
                hoverEnabled: true
                anchors.fill: parent
                onClicked: API.app.trading_pg.current_trading_mode = TradingMode.Simple
            }
        }

        DexLabel
        {
            id: _proLabel
            text: "Pro"
            color: API.app.trading_pg.current_trading_mode == TradingMode.Pro ? Dex.CurrentTheme.foregroundColor : Dex.CurrentTheme.foregroundColor2
            anchors.left: _simpleLabel.right
            anchors.leftMargin: 10 + cursorRect.width / 2
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: 14
            font.weight: Font.Bold

            DefaultMouseArea
            {
                id: pro_area
                hoverEnabled: true
                anchors.fill: parent
                onClicked: API.app.trading_pg.current_trading_mode = TradingMode.Pro
            }
        }
    }
}
