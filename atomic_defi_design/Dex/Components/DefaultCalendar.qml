import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../Qaterial" as Qaterial
import Dex.Themes 1.0 as Dex

// NOTE: This calendar deliberately does NOT use Qt.labs.calendar
// (MonthGrid/DayOfWeekRow). That plugin segfaults on instantiation in this
// environment (conda-forge Qt 5.15.15 on macOS/arm64): a bare `MonthGrid {}`
// dies in QQuickControl contentItem/addChild handling with no delegates,
// locales or properties involved, which crashed the app on every login once
// the Dashboard built the order pages. The grid below is plain
// Repeater + JS date math with identical visuals and API.
Item
{
    id: root
    width: 300
    height: 450

    // Properties exposed directly on the root item for the DatePicker aliases
    property date selectedDate: new Date()
    property var minimumDate: undefined
    property var maximumDate: undefined

    // Separate tracking property for visual month scrolling layout behavior
    // Automatically initializes to match whichever selection date the app loads!
    property date visualTrackingDate: selectedDate

    // Properties required for the inner layout calculations (Now map to visualTrackingDate)
    readonly property int currentMonth: visualTrackingDate.getMonth()
    readonly property int currentYear: visualTrackingDate.getFullYear()

    // Locale-aware week layout. Qt DayOfWeek is Monday=1..Sunday=7 while JS
    // Date.getDay() is Sunday=0..Saturday=6; fall back to Sunday start when
    // the locale reports an out-of-range value.
    property var loc: Qt.locale()
    readonly property int weekStartQt: (loc.firstDayOfWeek >= 1 && loc.firstDayOfWeek <= 7) ? loc.firstDayOfWeek : 7
    readonly property int weekStartJS: weekStartQt % 7

    // Date shown in cell `index` (0..41): the 6x7 frame containing the whole
    // visible month, padded with the adjacent months' edge days.
    function cellDate(index)
    {
        var firstDayOffset = (new Date(currentYear, currentMonth, 1).getDay() - weekStartJS + 7) % 7;
        return new Date(currentYear, currentMonth, 1 - firstDayOffset + index);
    }

    function showPreviousYear() { root.visualTrackingDate = new Date(currentYear - 1, currentMonth, 1) }
    function showNextYear() { root.visualTrackingDate = new Date(currentYear + 1, currentMonth, 1) }
    function showPreviousMonth() { root.visualTrackingDate = new Date(currentYear, currentMonth - 1, 1) }
    function showNextMonth() { root.visualTrackingDate = new Date(currentYear, currentMonth + 1, 1) }

    // Safety check: If the app changes selectedDate externally, sync the visual frame
    onSelectedDateChanged: { root.visualTrackingDate = selectedDate }

    // Background Panel
    DefaultRectangle
    {
        anchors.fill: parent
        color: Dex.CurrentTheme.floatingBackgroundColor
        radius: 18
    }

    ColumnLayout
    {
        anchors.fill: parent
        Layout.margins: 10
        spacing: 5

        // Navigation Bar
        DefaultRectangle
        {
            Layout.fillWidth: true
            Layout.preferredHeight: 50
            color: Dex.CurrentTheme.floatingBackgroundColor
            radius: 18

            DefaultButton
            {
                id: previousYear
                width: previousMonth.width
                height: width
                anchors.left: parent.left
                anchors.leftMargin: 5
                anchors.verticalCenter: parent.verticalCenter
                iconSource: "qrc:/assets/images/qaterial/arrow-left.svg"
                onClicked: root.showPreviousYear()
            }

            DefaultButton
            {
                id: previousMonth
                width: parent.height - 14
                height: width
                anchors.left: previousYear.right
                anchors.leftMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                iconSource: "qrc:/assets/images/qaterial/arrow-left.svg"
                onClicked: root.showPreviousMonth()
            }

            DexLabel
            {
                id: dateText
                text: Qt.locale().standaloneMonthName(root.currentMonth, Locale.LongFormat) + " " + root.currentYear
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: previousMonth.right
                anchors.leftMargin: 2
                anchors.right: nextMonth.left
                anchors.rightMargin: 2
            }

            DefaultButton
            {
                id: nextYear
                width: nextMonth.width
                height: width
                anchors.right: parent.right
                anchors.rightMargin: 5
                anchors.verticalCenter: parent.verticalCenter
                iconSource: "qrc:/assets/images/qaterial/arrow-right.svg"
                onClicked: root.showNextYear()
            }

            DefaultButton
            {
                id: nextMonth
                width: parent.height - 14
                height: width
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: nextYear.left
                anchors.rightMargin: 2
                iconSource: "qrc:/assets/images/qaterial/arrow-right.svg"
                onClicked: root.showNextMonth()
            }
        }

        // Days of Week Header Row (Mon, Tue, Wed...), ordered from the
        // locale's first day of week.
        RowLayout
        {
            Layout.fillWidth: true
            Layout.preferredHeight: 20

            Repeater
            {
                model: 7
                DefaultRectangle
                {
                    Layout.fillWidth: true
                    implicitHeight: 20
                    color: "transparent"
                    DexLabel
                    {
                        text: root.loc.standaloneDayName(((root.weekStartQt - 1 + index) % 7) + 1, Locale.ShortFormat)
                        anchors.centerIn: parent
                        color: Dex.CurrentTheme.foregroundColor
                    }
                }
            }
        }

        // Calendar Days Grid Matrix
        GridLayout
        {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 7
            rows: 6
            columnSpacing: 0
            rowSpacing: 0

            Repeater
            {
                model: 42
                DefaultRectangle
                {
                    id: dayCell
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    readonly property date cellDay: root.cellDate(index)
                    readonly property bool isSelected: cellDay.getDate() === root.selectedDate.getDate() &&
                                                        cellDay.getMonth() === root.selectedDate.getMonth() &&
                                                        cellDay.getFullYear() === root.selectedDate.getFullYear()
                    readonly property bool isVisibleMonth: cellDay.getMonth() === root.currentMonth

                    color: isSelected ? selectedDateColor : cellMouseArea.containsMouse ? hoveredDateColor : "transparent"

                    readonly property color sameMonthDateTextColor: Dex.CurrentTheme.foregroundColor
                    readonly property color hoveredDateColor: Dex.CurrentTheme.buttonColorHovered
                    readonly property color selectedDateColor: Dex.CurrentTheme.buttonColorPressed
                    readonly property color selectedDateTextColor: Dex.CurrentTheme.foregroundColor
                    readonly property color differentMonthDateTextColor: Dex.CurrentTheme.foregroundColor3

                    DexLabel
                    {
                        id: dayDelegateText
                        text: dayCell.cellDay.getDate()
                        anchors.centerIn: parent // This anchor is perfectly safe because it's inside the rectangle cell, not the grid!
                        horizontalAlignment: Text.AlignRight
                        font.pixelSize: Math.min(parent.height/3, parent.width/3)
                        color: {
                            var isTooEarly = root.minimumDate !== undefined && dayCell.cellDay < root.minimumDate;
                            var isTooLate = root.maximumDate !== undefined && dayCell.cellDay > root.maximumDate;
                            var isValidRange = !isTooEarly && !isTooLate;

                            var theColor = (dayCell.isVisibleMonth && isValidRange) ? sameMonthDateTextColor : differentMonthDateTextColor;

                            if (!isValidRange) {
                                theColor = Dex.CurrentTheme.textDisabledColor;
                            } else if (dayCell.isSelected) {
                                theColor = selectedDateTextColor;
                            }
                            theColor;
                        }
                    }

                    MouseArea
                    {
                        id: cellMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            var isTooEarly = root.minimumDate !== undefined && dayCell.cellDay < root.minimumDate;
                            var isTooLate = root.maximumDate !== undefined && dayCell.cellDay > root.maximumDate;
                            if (!isTooEarly && !isTooLate) {
                                root.selectedDate = dayCell.cellDay;
                            }
                        }
                    }
                }
            }
        }
    }
}
