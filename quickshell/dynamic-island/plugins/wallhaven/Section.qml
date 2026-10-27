pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

import qs
import qs.modules.services.config
import qs.modules.widgets

// Sektion des Plugins in der Wallpaper-Auswahl (Manifest panels.wallpaper):
// eigene Suchzeile mit Sortier-Chips und darunter das Treffer-Karussell
// (WallhavenList). Entsteht beim Aufklappen und wird beim Zuklappen wieder
// zerstoert – Suchtext und Treffer liegen im Dienst (plugin.main, Main.qml).
//
// Vertrag mit dem Panel (plugins/README.md, "Sektionen"): `plugin` und
// `host` kommen beim Laden; host.focused sagt, ob die Tastatur hier ist,
// zurueck gehen takeFocus/leaveFocus/toggle/close/cycleStyle.
//
// Tasten im Suchfeld:
//   Esc               Auswahl schliessen
//   Links/Rechts, Tab blaettern
//   Hoch/Runter       zurueck in die lokale Reihe
//   Enter             herunterladen + setzen; Shift+Enter nur herunterladen
//   Strg+Links/Rechts Stil des markierten lokalen Bilds (wie im Panel)
//   Strg+W            Sektion zu (bzw. naechste)
Item {
    id: section

    required property var plugin
    required property var host

    readonly property var wh: section.plugin.main
    readonly property bool focused: section.host.focused

    implicitHeight: whRow.height + 1 + whWrapper.implicitHeight

    // Die Tastatur kommt (auch gleich beim Erzeugen): ins Suchfeld, und die
    // Vorschau der markierten Kachel nachholen. forceActiveFocus greift nur
    // bei sichtbarem Feld – beim Aufklappen blendet das Panel die Sektion
    // aber erst ein (opacity 0 -> visible false), deshalb notfalls warten,
    // bis das Feld sichtbar ist
    property bool wantFocus: false

    function focusIn(): void {
        section.wantFocus = true;
        section.applyFocus();
        whList.item?.previewNow();
    }

    function applyFocus(): void {
        if (section.wantFocus && whSearch.visible) {
            section.wantFocus = false;
            whSearch.forceActiveFocus();
        }
    }

    onFocusedChanged: {
        if (section.focused)
            section.focusIn();
        else
            section.wantFocus = false;
    }

    Component.onCompleted: {
        // Der letzte Suchtext bleibt stehen – ohne neue Anfrage, der Dienst
        // kennt ihn schon (die Tipp-Pause darf davon nicht anspringen)
        whSearch.text = section.wh.query;
        searchDelay.stop();
        section.wh.refresh();
        if (section.focused)
            section.focusIn();
    }

    // Enter: steht eine Suche noch aus (Tipp-Pause), erst die; sonst den
    // markierten Treffer uebernehmen
    function apply(set: bool): void {
        if (searchDelay.running) {
            searchDelay.stop();
            section.wh.search(whSearch.text, false);
        } else {
            whList.item?.apply(set);
        }
    }

    // Sortierung als Chips – dieselben Werte wie die Einstellung `sorting`
    readonly property var sortings: [
        { name: "relevanz", label: I18n.tr("Relevanz"), icon: "manage_search" },
        { name: "neu", label: I18n.tr("Neu"), icon: "schedule" },
        { name: "zufall", label: I18n.tr("Zufall"), icon: "casino" },
        { name: "views", label: "Views", icon: "visibility" },
        { name: "favoriten", label: "Favs", icon: "favorite" },
        { name: "top", label: "Top", icon: "trending_up" }
    ]

    // Kurzer Stand rechts neben dem Suchfeld; die leeren Zustaende
    // (Suche, keine Treffer, Fehler) stehen gross im Karussellbereich
    readonly property string status: {
        if (section.wh.downloading)
            return I18n.tr("lädt herunter…");
        if (section.wh.prefetching)
            return I18n.tr("HQ-Vorschau lädt…");
        if (section.wh.error !== "" && section.wh.items.count > 0)
            return section.wh.error;
        if (section.wh.items.count === 0)
            return "";
        const pages = Math.min(section.wh.lastPage, section.wh.maxPages);
        return I18n.tr("%1 Treffer · Seite %2/%3").arg(section.wh.total).arg(section.wh.page).arg(pages)
            + (section.wh.searching ? I18n.tr(" · lädt…") : "");
    }

    Item {
        id: whRow

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: 46

        Text {
            id: whIcon

            anchors {
                left: parent.left
                leftMargin: 16
                verticalCenter: parent.verticalCenter
            }
            text: "travel_explore"
            font.family: "Material Symbols Outlined"
            font.pixelSize: 19
            color: Colors.primary
        }

        TextInput {
            id: whSearch
            font.family: Config.font

            anchors {
                left: whIcon.right
                leftMargin: 12
                right: whStatus.left
                rightMargin: 12
                verticalCenter: parent.verticalCenter
            }
            color: Colors.fgSurface
            font.pixelSize: 14
            selectionColor: Colors.alpha(Colors.primary, 0.35)
            selectedTextColor: Colors.fgSurface
            clip: true

            // Tipp-Pause statt jeder Taste: die API erlaubt 45 Anfragen
            // pro Minute
            onTextChanged: searchDelay.restart()
            // `visible` ist die wirksame Sichtbarkeit (samt Eltern)
            onVisibleChanged: section.applyFocus()

            Keys.onEscapePressed: section.host.close()
            Keys.onReturnPressed: event => section.apply(!(event.modifiers & Qt.ShiftModifier))
            Keys.onEnterPressed: event => section.apply(!(event.modifiers & Qt.ShiftModifier))
            Keys.onLeftPressed: event => {
                if (event.modifiers & Qt.ControlModifier)
                    section.host.cycleStyle(-1);
                else
                    whList.item?.moveBy(-1);
            }
            Keys.onRightPressed: event => {
                if (event.modifiers & Qt.ControlModifier)
                    section.host.cycleStyle(1);
                else
                    whList.item?.moveBy(1);
            }
            Keys.onUpPressed: section.host.leaveFocus()
            Keys.onDownPressed: section.host.leaveFocus()
            Keys.onTabPressed: whList.item?.moveBy(1)
            Keys.onPressed: event => {
                if (event.key === Qt.Key_W && (event.modifiers & Qt.ControlModifier)) {
                    section.host.toggle();
                    event.accepted = true;
                }
            }

            Text {
                anchors.fill: parent
                visible: whSearch.text === ""
                text: I18n.tr("Wallhaven durchsuchen…   tag, -tag, like:ID")
                color: Colors.alpha(Colors.fgSurfaceVariant, 0.7)
                font: whSearch.font
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }

        Text {
            id: whStatus

            anchors {
                right: whChips.left
                rightMargin: 14
                verticalCenter: parent.verticalCenter
            }
            text: section.status
            font.family: Config.font
            font.pixelSize: 11
            color: section.wh.error !== "" ? Colors.error : Colors.fgSurfaceVariant
        }

        Row {
            id: whChips

            anchors {
                right: parent.right
                rightMargin: 14
                verticalCenter: parent.verticalCenter
            }
            spacing: 4

            Repeater {
                model: section.sortings

                delegate: Rectangle {
                    id: sortChip

                    required property var modelData

                    readonly property bool selected: section.plugin.settings.sorting === sortChip.modelData.name

                    implicitWidth: sortContent.implicitWidth + 18
                    implicitHeight: 26
                    radius: height / 2
                    color: sortChip.selected ? Colors.primary
                        : sortArea.containsMouse ? Colors.alpha(Colors.fgSurface, 0.08)
                        : Colors.alpha(Colors.fgSurface, 0.04)

                    Behavior on color {
                        ColorAnimation { duration: 120 }
                    }

                    Row {
                        id: sortContent

                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: sortChip.modelData.icon
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 13
                            color: sortChip.selected ? Colors.fgPrimary : Colors.fgSurfaceVariant
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: sortChip.modelData.label
                            font.family: Config.font
                            font.pixelSize: 11
                            color: sortChip.selected ? Colors.fgPrimary : Colors.fgSurface
                        }
                    }

                    MouseArea {
                        id: sortArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: section.wh.setSorting(sortChip.modelData.name)
                    }
                }
            }
        }
    }

    Timer {
        id: searchDelay

        interval: 500
        onTriggered: section.wh.search(whSearch.text, false)
    }

    Rectangle {
        id: whSeparator

        anchors {
            top: whRow.bottom
            left: parent.left
            right: parent.right
        }
        height: 1
        color: Colors.alpha(Colors.outline, 0.2)
    }

    Item {
        id: whWrapper

        anchors {
            top: whSeparator.bottom
            left: parent.left
            right: parent.right
        }
        implicitHeight: section.host.listHeight

        // Treffer-Karussell (WallhavenList.qml), gleiche Vignette wie die
        // lokale Reihe. Per Loader statt als Typ: Plugin-Dateien sehen sich
        // untereinander nicht als Typen (qs:-Schema ohne Verzeichnis-Import),
        // deshalb ueber den Pfad – Anfangswerte beim Laden, die Bindungen
        // danach.
        Loader {
            id: whList

            anchors.fill: parent
            anchors.margins: 6

            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: whEdgeMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
            }

            Component.onCompleted: whList.setSource(section.plugin.url("WallhavenList.qml"), {
                wh: section.wh,
                imageWidth: section.host.imageWidth,
                focused: section.focused
            })
            onLoaded: {
                whList.item.imageWidth = Qt.binding(() => section.host.imageWidth);
                whList.item.focused = Qt.binding(() => section.focused);
                whList.item.activated.connect(section.host.takeFocus);
                whList.item.wheeled.connect(section.host.takeFocus);
            }
            onStatusChanged: if (whList.status === Loader.Error) section.plugin.log("WallhavenList.qml laedt nicht")
        }

        EdgeMask {
            id: whEdgeMask

            anchors.fill: whList
            fade: 200
        }

        // Leere Zustaende mitten im Karussellbereich
        Column {
            anchors.centerIn: parent
            spacing: 4
            // Vor der ersten Suche bleibt die Flaeche leer
            visible: section.wh.items.count === 0 && (section.wh.searching || section.wh.error !== "" || section.wh.answered)

            Text {
                id: emptyIcon

                anchors.horizontalCenter: parent.horizontalCenter
                text: section.wh.searching ? "progress_activity"
                    : section.wh.error !== "" ? "cloud_off"
                    : section.wh.answered ? "search_off" : "travel_explore"
                font.family: "Material Symbols Outlined"
                font.pixelSize: 26
                color: section.wh.error !== "" ? Colors.error : Colors.fgSurfaceVariant

                RotationAnimation on rotation {
                    running: section.wh.searching && section.wh.items.count === 0
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 900
                    onStopped: emptyIcon.rotation = 0
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: section.wh.searching ? I18n.tr("Suche auf wallhaven.cc…")
                    : section.wh.error !== "" ? section.wh.error
                    : I18n.tr("Keine Treffer")
                font.family: Config.font
                font.pixelSize: 12
                color: section.wh.error !== "" ? Colors.error : Colors.fgSurfaceVariant
            }
        }
    }
}
