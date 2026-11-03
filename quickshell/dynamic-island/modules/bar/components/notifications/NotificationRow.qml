pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Widgets
import qs.modules.services.notifications

import qs
import qs.modules.services.config

// Eine Benachrichtigung: Bild/Icon, Titel, Text, Alter, Schliessen-Knopf –
// und darunter die Aktionsknoepfe, falls die App welche mitschickt.
//
// Dieselbe Zeile in zwei Groessen: `compact` ist die Fassung fuer die
// aufgeklappte Pille (eine Zeile hoch, ohne Kreuz und ohne Knoepfe), sonst
// die Fassung fuer die Liste.
Item {
    id: row

    // { notif, time } aus dem Dienst; darf null sein (leere Liste)
    property var entry: null
    property bool compact: false
    // In einer Gruppe traegt der Kopf das App-Icon, die Zeilen brauchen keins
    property bool showIcon: true
    // Zeilen unter einem Gruppenkopf ruecken ein, damit sie dazugehoerig wirken
    property real leftInset: 0
    // Zur Seite ziehen entfernt die Nachricht
    property bool swipeable: false

    // Versatz beim Wegziehen; das Wegblenden haengt daran
    property real slide: 0

    readonly property var notif: row.entry?.notif ?? null
    readonly property bool critical: row.notif?.urgency === NotificationUrgency.Critical
    readonly property real iconSize: row.compact ? 20 : 26

    // "default" gehoert dem Klick auf die Zeile, der Rest wird zu Knoepfen
    readonly property var buttons: row.compact ? [] : Notifications.actionButtons(row.entry)
    readonly property var defaultAction: Notifications.defaultAction(row.entry)

    readonly property real textHeight: row.compact ? 30 : 52
    readonly property real buttonsHeight: 32

    // Grosse Bildvorschau (Screenshots der Shell setzen den Hint
    // x-dynamic-island-preview, andere Apps behalten das kleine Icon)
    readonly property bool hasPreview: !row.compact && (row.notif?.image ?? "") !== ""
                                       && (row.notif?.hints?.["x-dynamic-island-preview"] ?? false) === true
    readonly property real previewHeight: row.hasPreview ? preview.height + 8 : 0

    implicitHeight: row.textHeight + row.previewHeight + (row.buttons.length > 0 ? row.buttonsHeight : 0)

    transform: Translate {
        x: row.slide
    }
    // Je weiter weg, desto blasser – damit man sieht, dass es gleich weg ist
    opacity: row.slide === 0 ? 1
           : 1 - Math.min(0.85, Math.abs(row.slide) / Math.max(1, row.width * 0.7))

    // Dezente Flaeche unter der Zeile, damit man sieht, worauf man zeigt
    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: -6
        anchors.rightMargin: -6
        radius: 10
        color: !row.compact && rowHover.hovered ? Colors.alpha(Colors.fgSurface, 0.05) : "transparent"

        Behavior on color {
            ColorAnimation { duration: 120 }
        }
    }

    // Klick auf die Zeile loest die Standard-Aktion aus – die schickt fast
    // jede App mit ("oeffnen"), und laut Spezifikation gehoert sie genau
    // hierhin und nicht auf einen Knopf.
    TapHandler {
        enabled: row.defaultAction !== null
        onTapped: row.defaultAction.invoke()
    }

    // Zwei Handler statt einem: der erste meldet nur, ob der Zeiger ueber der
    // Zeile steht (fuer die Hover-Flaeche). Wuerde er zugleich eine Cursorform
    // setzen, beanspruchte er sie fuer die ganze Zeile – die Aktionsknoepfe
    // darunter bekaemen ihre Hand dann nicht mehr durch.
    HoverHandler {
        id: rowHover
    }

    HoverHandler {
        enabled: row.defaultAction !== null
        cursorShape: Qt.PointingHandCursor
    }

    // Zur Seite ziehen: ueber ein Drittel der Breite fliegt die Nachricht raus,
    // darunter federt sie zurueck. Nur die Waagerechte gehoert dem Handler,
    // damit die Liste weiter senkrecht scrollen kann.
    DragHandler {
        id: swipe

        target: null
        yAxis.enabled: false
        enabled: row.swipeable && row.entry !== null

        readonly property real threshold: row.width * 0.3

        onTranslationChanged: if (swipe.active)
            row.slide = swipe.activeTranslation.x
        onActiveChanged: {
            if (swipe.active) {
                slideBack.stop();
                slideOut.stop();
                return;
            }
            if (Math.abs(row.slide) > swipe.threshold) {
                slideOut.to = row.slide > 0 ? row.width : -row.width;
                slideOut.start();
            } else {
                slideBack.start();
            }
        }
    }

    NumberAnimation {
        id: slideBack

        target: row
        property: "slide"
        to: 0
        duration: 180
        easing.type: Easing.OutCubic
    }

    // Erst rausfliegen lassen, dann entfernen – sonst ist der Delegat weg,
    // bevor man die Bewegung sieht
    NumberAnimation {
        id: slideOut

        target: row
        property: "slide"
        duration: 140
        easing.type: Easing.OutCubic
        onFinished: Notifications.dismiss(row.entry)
    }

    // ---- Kopfteil: Icon, Text, Alter, Kreuz ----
    Item {
        id: head

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: row.textHeight

        // Bild/Icon dreistufig: mitgeschicktes Bild, sonst App-Icon aus dem
        // Icon-Theme, sonst ein Material-Symbol.
        Item {
            id: iconBox

            anchors {
                left: parent.left
                leftMargin: row.leftInset
                verticalCenter: parent.verticalCenter
            }
            width: row.showIcon ? row.iconSize : 0
            height: row.iconSize
            visible: row.showIcon

            Image {
                id: icon

                anchors.fill: parent
                source: {
                    const n = row.notif;
                    // Das Bild steht schon gross darunter
                    if (!n || row.hasPreview)
                        return "";
                    if (n.image !== "")
                        return Qt.resolvedUrl(n.image);
                    if (n.appIcon !== "")
                        return Quickshell.iconPath(n.appIcon, true);
                    return "";
                }
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                sourceSize.width: row.iconSize * 2
                sourceSize.height: row.iconSize * 2
                visible: status === Image.Ready
            }

            Text {
                anchors.centerIn: parent
                visible: icon.status !== Image.Ready

                text: row.critical ? "release_alert" : row.hasPreview ? "screenshot_region" : "chat"
                color: row.critical ? Colors.error : Colors.fgSurfaceVariant
                font.family: "Material Symbols Outlined"
                font.pixelSize: row.iconSize - 4
            }
        }

        Column {
            anchors {
                left: iconBox.right
                leftMargin: row.showIcon ? 10 : 0
                right: meta.left
                rightMargin: 8
                verticalCenter: parent.verticalCenter
            }
            spacing: row.compact ? 0 : 2

            Text {
                font.family: Config.font
                width: parent.width
                text: row.notif?.summary ?? ""
                color: row.critical ? Colors.error : Colors.fgBackground
                font.pixelSize: row.compact ? 11 : 12
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                font.family: Config.font
                width: parent.width
                visible: text !== ""
                // Die Spec meint ein HTML-Subset, nicht Markdown
                textFormat: Text.StyledText
                text: row.notif?.body ?? ""
                color: Colors.fgSurfaceVariant
                font.pixelSize: row.compact ? 10 : 11
                elide: Text.ElideRight
                maximumLineCount: row.compact ? 1 : 2
                wrapMode: row.compact ? Text.NoWrap : Text.Wrap
            }
        }

        Row {
            id: meta

            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
            spacing: 4

            Text {
                font.family: Config.font
                anchors.verticalCenter: parent.verticalCenter

                text: {
                    // `tick` haengt nur mit drin, damit sich die Angabe auffrischt
                    void Notifications.tick;
                    return Notifications.formatAge(row.entry?.time ?? null);
                }
                color: Colors.alpha(Colors.fgSurfaceVariant, 0.8)
                font.pixelSize: 10
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: !row.compact

                width: 22
                height: 22
                radius: height / 2
                color: closeArea.containsMouse ? Colors.alpha(Colors.fgSurface, 0.14) : "transparent"

                Behavior on color {
                    ColorAnimation { duration: 120 }
                }

                Text {
                    anchors.centerIn: parent
                    text: "close"
                    color: Colors.fgSurfaceVariant
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 14
                }

                MouseArea {
                    id: closeArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Notifications.dismiss(row.entry)
                }
            }
        }
    }

    // ---- Bildvorschau ----
    ClippingRectangle {
        id: preview

        anchors {
            left: parent.left
            leftMargin: row.leftInset + (row.showIcon ? row.iconSize + 10 : 0)
            top: head.bottom
        }
        visible: row.hasPreview
        width: Math.min(parent.width - anchors.leftMargin, 360)
        // Seitenverhaeltnis des Bilds, flache Streifen nicht unter 48 px
        height: visible && shot.status === Image.Ready
                ? Math.max(48, Math.min(180, width * shot.implicitHeight / Math.max(1, shot.implicitWidth)))
                : (visible ? 120 : 0)
        radius: 10
        color: Colors.alpha(Colors.fgSurface, 0.06)

        Image {
            id: shot

            anchors.fill: parent
            source: row.hasPreview ? Qt.resolvedUrl(row.notif.image) : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 720
        }

        TapHandler {
            onTapped: row.defaultAction?.invoke()
        }
    }

    // ---- Aktionsknoepfe ----
    Row {
        anchors {
            left: parent.left
            leftMargin: row.leftInset + (row.showIcon ? row.iconSize + 10 : 0)
            top: row.hasPreview ? preview.bottom : head.bottom
            topMargin: row.hasPreview ? 6 : 0
        }
        height: row.buttonsHeight
        spacing: 6
        visible: row.buttons.length > 0

        Repeater {
            model: row.buttons

            Rectangle {
                id: button

                required property var modelData

                implicitWidth: buttonText.implicitWidth + 22
                implicitHeight: 26
                radius: height / 2
                color: buttonArea.containsMouse ? Colors.alpha(Colors.primary, 0.28)
                                                : Colors.alpha(Colors.primary, 0.16)

                Behavior on color {
                    ColorAnimation { duration: 120 }
                }

                Text {
                    id: buttonText
                    font.family: Config.font

                    anchors.centerIn: parent
                    text: button.modelData.text
                    color: Colors.primary
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: buttonArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: button.modelData.invoke()
                }
            }
        }
    }
}
