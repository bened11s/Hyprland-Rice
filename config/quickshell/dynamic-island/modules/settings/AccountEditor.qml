pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config
import qs.modules.services.system
import qs.modules.services.user
import qs.modules.widgets
import qs.modules.settings.system
import qs.modules.settings.account

// Einstellungsseite Konto (Config.meta editor "account"): Kopf mit
// Profilbild, Anzeigename und Login wie der Kopf der Info-Seite, darunter
// Profil (Bild, Name), Sicherheit (Passwort) und Sitzung (seit wann,
// welche, Abmelden mit Rueckfrage). Im Kopf Chips: Kontotyp, Shell, Dauer.
// Geschrieben wird ueber User (usermgr.py -> AccountsService); das
// Passwort bestaetigt der polkit-Dialog mit dem aktuellen Passwort.
Item {
    id: editor

    implicitHeight: content.implicitHeight

    // Passwort-Felder aufgeklappt
    property bool pwOpen: false
    readonly property bool pwValid: newPw.text !== "" && newPw.text === repeatPw.text
    readonly property bool pwMismatch: repeatPw.text !== "" && newPw.text !== repeatPw.text
    // Abmelden-Rueckfrage offen
    property bool logoutAsk: false

    // Sekunden-Uhr fuer "seit …", tickt nur bei offener Seite
    property real now: Date.now() / 1000
    readonly property real since: User.session?.since ?? 0

    function sinceText(): string {
        const d = new Date(editor.since * 1000);
        const time = Qt.formatTime(d, Config.appearance.clock === "12h" ? "h:mm AP" : "HH:mm");
        const days = Math.round((new Date().setHours(0, 0, 0, 0) - new Date(d).setHours(0, 0, 0, 0)) / 86400000);
        if (days === 0)
            return I18n.tr("Heute, %1").arg(time);
        if (days === 1)
            return I18n.tr("Gestern, %1").arg(time);
        return `${Qt.formatDate(d, "dd.MM.")}, ${time}`;
    }

    function sessionText(): string {
        const s = User.session ?? {};
        const kind = s.type === "wayland" ? "Wayland" : s.type === "x11" ? "X11" : "";
        const what = s.desktop && kind ? `${s.desktop} (${kind})` : s.desktop || kind;
        return what && s.tty ? I18n.tr("%1 auf %2").arg(what).arg(s.tty) : what || s.tty || "";
    }

    Timer {
        interval: 60000
        repeat: true
        running: editor.visible
        triggeredOnStart: true
        onTriggered: editor.now = Date.now() / 1000
    }

    // Beim Oeffnen frisch lesen (Name koennte anderswo geaendert sein)
    onVisibleChanged: {
        if (visible)
            User.refresh();
        else
            editor.logoutAsk = false;
    }

    Connections {
        target: User

        function onBusyChanged(): void {
            if (User.busy === "" && User.lastDone === "password" && User.lastError === "") {
                newPw.clear();
                repeatPw.clear();
                editor.pwOpen = false;
            }
        }
    }

    Column {
        id: content

        width: parent.width
        spacing: 20
        bottomPadding: 4

        // ---- Kopf: Bild, Name, Login ----
        Rectangle {
            width: parent.width
            height: chips.visible ? 266 : 230
            radius: 16
            color: Colors.alpha(Colors.fgSurface, 0.04)

            Column {
                anchors.centerIn: parent
                width: parent.width - 32
                spacing: 4

                Item {
                    id: avatar

                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 116
                    height: 116

                    AvatarShape {
                        anchors.fill: parent
                        source: User.faceUrl
                        dim: avatarHover.hovered || User.busy === "face" ? 1 : 0

                        Behavior on dim {
                            NumberAnimation { duration: Appearance.fadeDuration }
                        }
                    }

                    // Beim Hovern: abgedunkelt (AvatarShape.dim) mit Stift, Klick waehlt ein Bild
                    Text {
                        anchors.centerIn: parent
                        opacity: avatarHover.hovered || User.busy === "face" ? 1 : 0
                        text: User.busy === "face" ? "hourglass_empty" : "edit"
                        color: "#ffffff"
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 26

                        Fade on opacity {}
                    }

                    HoverHandler {
                        id: avatarHover

                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        onTapped: User.pickFace()
                    }
                }

                Item {
                    width: 1
                    height: 10
                }

                Text {
                    width: parent.width
                    text: User.name || User.user
                    color: Colors.fgSurface
                    font.family: Config.font
                    font.pixelSize: 28
                    font.weight: Font.Medium
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: User.user
                    color: Colors.fgSurfaceVariant
                    font.family: Config.font
                    font.pixelSize: 13
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Item {
                    width: 1
                    height: 10
                    visible: chips.visible
                }

                // Chips: Kontotyp, Login-Shell, seit wann angemeldet
                Row {
                    id: chips

                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6
                    visible: User.shell !== ""

                    Repeater {
                        model: [
                            User.admin ? ["shield_person", I18n.tr("Administrator")] : ["person", I18n.tr("Standardkonto")],
                            ["terminal", User.shell],
                            ["schedule", editor.since > 0 ? I18n.tr("seit %1").arg(SystemInfo.formatUptime(Math.max(0, editor.now - editor.since))) : ""]
                        ].filter(c => c[1] !== "")

                        Rectangle {
                            id: chip

                            required property var modelData

                            width: chipRow.implicitWidth + 20
                            height: 26
                            radius: 13
                            color: Colors.alpha(Colors.fgSurface, 0.08)

                            Row {
                                id: chipRow

                                anchors.centerIn: parent
                                spacing: 5

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: chip.modelData[0]
                                    color: Colors.fgSurfaceVariant
                                    font.family: "Material Symbols Outlined"
                                    font.pixelSize: 14
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: chip.modelData[1]
                                    color: Colors.fgSurface
                                    font.family: Config.font
                                    font.pixelSize: 11
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- Profil ----
        SectionCard {
            width: parent.width
            title: I18n.tr("Profil")

            Item {
                width: parent.width
                height: 50

                Text {
                    anchors {
                        left: parent.left
                        leftMargin: 16
                        verticalCenter: parent.verticalCenter
                    }
                    text: I18n.tr("Profilbild")
                    color: Colors.fgSurface
                    font.family: Config.font
                    font.pixelSize: 13
                }

                TextButton {
                    anchors {
                        right: parent.right
                        rightMargin: 14
                        verticalCenter: parent.verticalCenter
                    }
                    label: User.busy === "face" ? "…" : I18n.tr("Ändern")
                    enabled: User.busy === ""
                    onClicked: User.pickFace()
                }

                Divider {}
            }

            Item {
                width: parent.width
                height: 50

                Text {
                    anchors {
                        left: parent.left
                        leftMargin: 16
                        verticalCenter: parent.verticalCenter
                    }
                    text: I18n.tr("Anzeigename")
                    color: Colors.fgSurface
                    font.family: Config.font
                    font.pixelSize: 13
                }

                // Gespeichert wird mit Enter oder beim Verlassen des Felds
                AccountField {
                    id: nameField

                    anchors {
                        right: parent.right
                        rightMargin: 14
                        verticalCenter: parent.verticalCenter
                    }
                    width: 200
                    value: User.name
                    onEditingFinished: {
                        const name = nameField.text.trim();
                        if (name !== "" && name !== User.name && User.busy === "")
                            User.setName(name);
                    }
                }
            }
        }

        // ---- Sicherheit ----
        SectionCard {
            width: parent.width
            title: I18n.tr("Sicherheit")

            Item {
                width: parent.width
                height: 50

                Column {
                    anchors {
                        left: parent.left
                        leftMargin: 16
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 2

                    Text {
                        text: I18n.tr("Passwort")
                        color: Colors.fgSurface
                        font.family: Config.font
                        font.pixelSize: 13
                    }

                    // Live-Status: wartet auf polkit bzw. gerade geaendert
                    Text {
                        visible: text !== ""
                        text: User.busy === "password" ? I18n.tr("Warte auf Bestätigung …")
                            : User.lastDone === "password" && !editor.pwOpen ? I18n.tr("Geändert") : ""
                        color: Colors.fgSurfaceVariant
                        font.family: Config.font
                        font.pixelSize: 11
                    }
                }

                TextButton {
                    anchors {
                        right: parent.right
                        rightMargin: 14
                        verticalCenter: parent.verticalCenter
                    }
                    visible: !editor.pwOpen
                    label: I18n.tr("Ändern")
                    enabled: User.busy === ""
                    onClicked: {
                        editor.pwOpen = true;
                        newPw.forceActiveFocus();
                    }
                }

                Divider {
                    visible: editor.pwOpen
                }
            }

            // Aufgeklappt: neues Passwort zweimal, dann polkit
            Column {
                width: parent.width
                visible: editor.pwOpen
                padding: 16
                topPadding: 12
                spacing: 8

                AccountField {
                    id: newPw

                    width: parent.width - 32
                    password: true
                    placeholder: I18n.tr("Neues Passwort")
                    onAccepted: repeatPw.forceActiveFocus()
                }

                AccountField {
                    id: repeatPw

                    width: parent.width - 32
                    password: true
                    placeholder: I18n.tr("Wiederholen")
                    border.color: editor.pwMismatch ? Colors.alpha(Colors.error, 0.7) : "transparent"
                    onAccepted: if (editor.pwValid) User.setPassword(newPw.text)
                }

                Item {
                    width: parent.width - 32
                    height: 30

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: editor.pwMismatch
                        text: I18n.tr("Stimmt nicht überein")
                        color: Colors.error
                        font.family: Config.font
                        font.pixelSize: 11
                    }

                    Row {
                        anchors.right: parent.right
                        spacing: 8

                        TextButton {
                            label: I18n.tr("Abbrechen")
                            enabled: User.busy === ""
                            onClicked: {
                                newPw.clear();
                                repeatPw.clear();
                                editor.pwOpen = false;
                            }
                        }

                        TextButton {
                            filled: true
                            label: User.busy === "password" ? "…" : I18n.tr("Speichern")
                            enabled: editor.pwValid && User.busy === ""
                            onClicked: User.setPassword(newPw.text)
                        }
                    }
                }
            }
        }

        // ---- Sitzung (nur mit logind) ----
        SectionCard {
            width: parent.width
            visible: editor.since > 0
            title: I18n.tr("Sitzung")

            InfoLine {
                label: I18n.tr("Angemeldet seit")
                value: editor.since > 0 ? editor.sinceText() : ""
            }

            InfoLine {
                label: I18n.tr("Sitzung")
                value: editor.sessionText()
            }

            // Abmelden schliesst alle Fenster: erst nachfragen
            Item {
                width: parent.width
                height: 50

                Text {
                    anchors {
                        left: parent.left
                        leftMargin: 16
                        verticalCenter: parent.verticalCenter
                    }
                    text: editor.logoutAsk ? I18n.tr("Wirklich abmelden?") : I18n.tr("Abmelden")
                    color: Colors.fgSurface
                    font.family: Config.font
                    font.pixelSize: 13
                }

                Row {
                    anchors {
                        right: parent.right
                        rightMargin: 14
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 8

                    TextButton {
                        visible: editor.logoutAsk
                        label: I18n.tr("Abbrechen")
                        onClicked: editor.logoutAsk = false
                    }

                    TextButton {
                        filled: editor.logoutAsk
                        label: I18n.tr("Abmelden")
                        onClicked: {
                            if (editor.logoutAsk)
                                User.logout();
                            editor.logoutAsk = !editor.logoutAsk;
                        }
                    }
                }
            }
        }

        // Fehler der letzten Aktion (abgebrochener polkit-Dialog, kaputtes Bild …)
        Text {
            width: parent.width
            visible: User.lastError !== ""
            leftPadding: 4
            text: User.lastError
            color: Colors.error
            font.family: Config.font
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }
    }
}
