pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets

import qs
import qs.modules.services.config

// Tray-Menue als undurchsichtige Karte in der Formensprache der Bar:
// runde Karte mit 1px-Border, Eintraege als Pillen, Untermenues auf einem
// StackView. Alles aus dem Colors-Singleton. Kein Grab -> Hover-Oeffnen UND
// Schliessen-beim-Verlassen bleiben moeglich.
Item {
    id: menuRoot

    signal closeRequested()

    // Von aussen (StatusBar) gesetzt, sobald das Popup sichtbar wird -> triggert
    // die Einblend-Animation. Ohne das liefe sie, waehrend das Popup noch
    // unsichtbar auf die D-Bus-Eintraege wartet.
    property bool shown: false

    // Unsichtbare Bruecke zwischen Icon-Unterkante und Karte: das Popup beginnt
    // direkt am Icon, damit auf dem Weg nach unten keine hover-freie Luecke
    // liegt (sonst schliesst das Menue beim Hinuebergehen).
    readonly property real bridge: 18
    readonly property real pad: 6           // Innenabstand der Karte
    readonly property real rowPad: 11       // Innenabstand einer Zeile
    readonly property real rowHeight: 32
    readonly property real leadSize: 17     // Icon/Checkbox-Spalte
    readonly property real fontSize: 13
    readonly property real minWidth: 170
    readonly property real maxWidth: 330
    readonly property real maxHeight: 460

    // Das Popup darf erst sichtbar werden, wenn die Eintraege der ersten Seite
    // per D-Bus da sind (kommen ~100-500ms nach dem ersten Oeffnen).
    readonly property bool ready: stack.depth > 1 || (stack.currentItem ? stack.currentItem.loaded : false)

    implicitWidth: stack.implicitWidth
    implicitHeight: bridge + stack.implicitHeight

    // Groesse sanft mitwachsen lassen (Untermenue-Wechsel)
    Behavior on implicitWidth {
        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }
    Behavior on implicitHeight {
        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }

    function open(handle: var): void {
        stack.clear();
        stack.push(pageComp.createObject(null, { handle: handle }));
    }

    Component {
        id: pageComp

        MenuPage {}
    }

    // ---- Karte ----
    Rectangle {
        id: card

        anchors {
            fill: parent
            topMargin: menuRoot.bridge
        }
        radius: 16
        // bewusst deckend und eine Stufe heller als die Bar (Colors.background),
        // damit die Karte sich abhebt statt mit ihr zu verschmelzen
        color: Colors.surfaceContainer
        border.width: 1
        border.color: Colors.outlineVariant

        opacity: menuRoot.shown ? 1 : 0
        scale: menuRoot.shown ? 1 : 0.95
        transformOrigin: Item.Top

        Behavior on opacity {
            NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
        }

        StackView {
            id: stack

            anchors.fill: parent
            implicitWidth: currentItem ? currentItem.implicitWidth : menuRoot.minWidth
            implicitHeight: currentItem ? currentItem.implicitHeight : 0
            clip: true

            // Seiten bringen ihre eigene Einblendung mit
            pushEnter: NoAnim {}
            pushExit: NoAnim {}
            popEnter: NoAnim {}
            popExit: NoAnim {}
        }
    }

    component NoAnim: Transition {
        NumberAnimation { duration: 0 }
    }

    component MaterialSymbol: Text {
        font.family: "Material Symbols Outlined"
        font.pixelSize: 16
        verticalAlignment: Text.AlignVCenter
    }

    // ---- Eine Menue-Ebene ----
    component MenuPage: Item {
        id: page

        required property QsMenuHandle handle
        property bool isSubMenu: false
        property string title: ""

        readonly property bool loaded: opener.children.values.length > 0
        // Hat irgendein Eintrag ein Icon oder eine Checkbox, wird die Spalte für
        // ALLE Zeilen reserviert – sonst springen die Labels zeilenweise ein.
        readonly property bool leadColumn: {
            const entries = opener.children.values;
            for (let i = 0; i < entries.length; i++) {
                const e = entries[i];
                if (e.icon !== "" || e.buttonType !== QsMenuButtonType.None)
                    return true;
            }
            return false;
        }
        // Einblenden erst, wenn das Popup wirklich sichtbar und die Seite aktiv ist
        readonly property bool shown: menuRoot.shown && StackView.status === StackView.Active
        // Breite aus dem breitesten Eintrag (unsichtbarer Messer unten), geklemmt
        readonly property real rowWidth: Math.max(menuRoot.minWidth, Math.min(menuRoot.maxWidth, sizer.implicitWidth))

        implicitWidth: rowWidth + menuRoot.pad * 2
        implicitHeight: Math.min(menuRoot.maxHeight, column.implicitHeight + menuRoot.pad * 2)

        StackView.onRemoved: destroy()

        QsMenuOpener {
            id: opener

            menu: page.handle
        }

        Flickable {
            id: flick

            anchors.fill: parent
            anchors.margins: menuRoot.pad
            contentWidth: width
            contentHeight: column.implicitHeight
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            // Mausrad: drei Zeilen pro Rastung, weich animiert. Ohne das
            // scrollt Flickable mit Qt-Default zäh zeilenweise.
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    const step = (menuRoot.rowHeight + column.spacing) * 3;
                    const from = scrollAnim.running ? scrollAnim.to : flick.contentY;
                    const max = Math.max(0, flick.contentHeight - flick.height);
                    const to = Math.max(0, Math.min(max, from - event.angleDelta.y / 120 * step));

                    scrollAnim.stop();
                    scrollAnim.from = flick.contentY;
                    scrollAnim.to = to;
                    scrollAnim.start();
                    event.accepted = true;
                }
            }

            NumberAnimation {
                id: scrollAnim

                target: flick
                property: "contentY"
                duration: 160
                easing.type: Easing.OutCubic
            }

            ScrollBar.vertical: ScrollBar {
                id: scrollBar

                width: 3
                policy: flick.interactive ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

                contentItem: Rectangle {
                    radius: width / 2
                    color: Colors.alpha(Colors.fgSurfaceVariant, scrollBar.pressed ? 0.7 : 0.35)

                    Behavior on color {
                        ColorAnimation { duration: 120 }
                    }
                }
                background: null
            }

            Column {
                id: column

                width: page.rowWidth
                spacing: 1

                // "Zurueck"-Kopfzeile, nur auf Untermenue-Seiten
                Item {
                    width: parent.width
                    height: page.isSubMenu ? menuRoot.rowHeight + 5 : 0
                    visible: page.isSubMenu

                    Rectangle {
                        id: backRow

                        width: parent.width
                        height: menuRoot.rowHeight
                        radius: height / 2
                        color: backArea.containsMouse ? Colors.alpha(Colors.primary, backArea.pressed ? 0.28 : 0.15)
                                                      : "transparent"

                        Behavior on color {
                            ColorAnimation { duration: 90 }
                        }

                        MouseArea {
                            id: backArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: stack.pop()
                        }

                        MaterialSymbol {
                            id: backIcon

                            anchors {
                                left: parent.left
                                leftMargin: menuRoot.rowPad - 2
                                verticalCenter: parent.verticalCenter
                            }
                            text: "chevron_left"
                            color: Colors.primary
                        }

                        Text {
                            font.family: Config.font
                            anchors {
                                left: backIcon.right
                                leftMargin: 6
                                right: parent.right
                                rightMargin: menuRoot.rowPad
                                verticalCenter: parent.verticalCenter
                            }
                            text: page.title || I18n.tr("Zurück")
                            color: Colors.primary
                            font.pixelSize: menuRoot.fontSize
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        anchors {
                            bottom: parent.bottom
                            bottomMargin: 2
                            horizontalCenter: parent.horizontalCenter
                        }
                        width: parent.width - menuRoot.rowPad
                        height: 1
                        color: Colors.alpha(Colors.outline, 0.35)
                    }
                }

                Repeater {
                    model: opener.children

                    Rectangle {
                        id: entry

                        required property QsMenuEntry modelData
                        required property int index

                        readonly property bool separator: modelData.isSeparator
                        readonly property bool actionable: !separator && modelData.enabled
                        readonly property bool checkable: !separator && modelData.buttonType !== QsMenuButtonType.None
                        readonly property bool checked: modelData.checkState === Qt.Checked

                        width: page.rowWidth
                        height: separator ? 9 : menuRoot.rowHeight
                        radius: separator ? 0 : height / 2
                        color: entry.actionable && entryArea.containsMouse
                               ? Colors.alpha(Colors.primary, entryArea.pressed ? 0.28 : 0.15)
                               : "transparent"

                        // gestaffeltes Einblenden von oben nach unten
                        opacity: page.shown ? 1 : 0
                        transform: Translate {
                            y: page.shown ? 0 : -6

                            Behavior on y {
                                SequentialAnimation {
                                    PauseAnimation { duration: Math.max(0, Math.min(entry.index * 16, 160)) }
                                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                                }
                            }
                        }

                        Behavior on opacity {
                            SequentialAnimation {
                                PauseAnimation { duration: Math.max(0, Math.min(entry.index * 16, 160)) }
                                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                            }
                        }
                        Behavior on color {
                            ColorAnimation { duration: 90 }
                        }

                        // Trennlinie
                        Rectangle {
                            visible: entry.separator
                            anchors.centerIn: parent
                            width: parent.width - menuRoot.rowPad
                            height: 1
                            color: Colors.alpha(Colors.outline, 0.35)
                        }

                        MouseArea {
                            id: entryArea

                            anchors.fill: parent
                            enabled: entry.actionable
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const e = entry.modelData;
                                if (e.hasChildren)
                                    stack.push(pageComp.createObject(null, {
                                        handle: e,
                                        isSubMenu: true,
                                        title: e.text
                                    }));
                                else {
                                    e.triggered();
                                    menuRoot.closeRequested();
                                }
                            }
                        }

                        // Inhalt: Icon/Checkbox links, Label, Chevron rechts
                        Loader {
                            anchors.fill: parent
                            active: !entry.separator

                            sourceComponent: Item {
                                IconImage {
                                    id: entryIcon

                                    visible: (entry.modelData?.icon ?? "") !== ""
                                    anchors {
                                        left: parent.left
                                        leftMargin: menuRoot.rowPad
                                        verticalCenter: parent.verticalCenter
                                    }
                                    implicitSize: menuRoot.leadSize
                                    opacity: (entry.modelData?.enabled ?? false) ? 1 : 0.4
                                    source: entry.modelData?.icon ?? ""
                                }

                                MaterialSymbol {
                                    id: checkMark

                                    visible: entry.checkable && !entryIcon.visible
                                    anchors {
                                        left: parent.left
                                        leftMargin: menuRoot.rowPad - 1
                                        verticalCenter: parent.verticalCenter
                                    }
                                    text: entry.modelData?.buttonType === QsMenuButtonType.RadioButton
                                          ? (entry.checked ? "radio_button_checked" : "radio_button_unchecked")
                                          : (entry.checked ? "check_box" : "check_box_outline_blank")
                                    color: entry.checked ? Colors.primary
                                         : Colors.alpha(Colors.fgSurfaceVariant, (entry.modelData?.enabled ?? false) ? 0.8 : 0.4)
                                }

                                MaterialSymbol {
                                    id: chevron

                                    visible: entry.modelData?.hasChildren ?? false
                                    anchors {
                                        right: parent.right
                                        rightMargin: menuRoot.rowPad - 3
                                        verticalCenter: parent.verticalCenter
                                    }
                                    text: "chevron_right"
                                    color: entryArea.containsMouse ? Colors.primary : Colors.fgSurfaceVariant

                                    Behavior on color {
                                        ColorAnimation { duration: 90 }
                                    }
                                }

                                Text {
                                    font.family: Config.font
                                    anchors {
                                        left: parent.left
                                        leftMargin: page.leadColumn ? menuRoot.rowPad + menuRoot.leadSize + 9 : menuRoot.rowPad
                                        right: parent.right
                                        rightMargin: chevron.visible ? menuRoot.rowPad + menuRoot.leadSize : menuRoot.rowPad
                                        verticalCenter: parent.verticalCenter
                                    }
                                    text: entry.modelData?.text ?? ""
                                    color: (entry.modelData?.enabled ?? false) ? Colors.fgSurface
                                         : Colors.alpha(Colors.fgSurface, 0.38)
                                    font.pixelSize: menuRoot.fontSize
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }

        // Unsichtbarer Messer: liefert die natuerliche Breite des breitesten
        // Eintrags. Muss vom echten Layout getrennt sein, sonst haengt die
        // Breite der Column an ihren eigenen Kindern (Binding-Loop).
        Column {
            id: sizer

            // nicht `visible: false` – ein unsichtbarer Positioner rechnet seine
            // Inhaltsgröße evtl. nicht aus. Die Kinder zeichnen ohnehin nichts.
            opacity: 0
            enabled: false

            Repeater {
                model: opener.children

                Item {
                    id: measure

                    required property QsMenuEntry modelData

                    implicitWidth: modelData.isSeparator ? 0
                                 : menuRoot.rowPad * 2 + metrics.width
                                   + (page.leadColumn ? menuRoot.leadSize + 9 : 0)
                                   + (modelData.hasChildren ? menuRoot.leadSize : 0)
                    implicitHeight: 0

                    TextMetrics {
                        id: metrics

                        text: measure.modelData.text ?? ""
                        font.pixelSize: menuRoot.fontSize
                    }
                }
            }
        }
    }
}
