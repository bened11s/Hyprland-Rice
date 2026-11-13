pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

import qs
import qs.modules.services.config
import qs.modules.services.user
import qs.modules.widgets
import qs.modules.settings.system
import qs.modules.settings.account

// Einstellungsseite Konto (Config.meta editor "account"): Kopf mit
// Profilbild, Anzeigename und Login wie der Kopf der Info-Seite, darunter
// Profil (Bild, Name) und Sicherheit (Passwort).
// Geschrieben wird ueber User (usermgr.py -> AccountsService); das
// Passwort bestaetigt der polkit-Dialog mit dem aktuellen Passwort.
Item {
    id: editor

    implicitHeight: content.implicitHeight

    // Passwort-Felder aufgeklappt
    property bool pwOpen: false
    readonly property bool pwValid: newPw.text !== "" && newPw.text === repeatPw.text
    readonly property bool pwMismatch: repeatPw.text !== "" && newPw.text !== repeatPw.text

    // Beim Oeffnen frisch lesen (Name koennte anderswo geaendert sein)
    onVisibleChanged: if (visible) User.refresh()

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
            height: 230
            radius: 16
            color: Colors.alpha(Colors.fgSurface, 0.04)

            Column {
                anchors.centerIn: parent
                width: parent.width - 32
                spacing: 4

                Item {
                    id: avatar

                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 104
                    height: 104

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Colors.alpha(Colors.fgSurface, 0.08)
                    }

                    Image {
                        id: face

                        anchors.fill: parent
                        source: User.faceUrl
                        sourceSize: Qt.size(208, 208)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                        visible: false
                    }

                    Rectangle {
                        id: faceMask

                        anchors.fill: parent
                        radius: width / 2
                        layer.enabled: true
                        visible: false
                    }

                    MultiEffect {
                        anchors.fill: parent
                        source: face
                        maskEnabled: true
                        maskSource: faceMask
                        visible: face.status === Image.Ready
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: face.status !== Image.Ready
                        text: "person"
                        color: Colors.fgSurfaceVariant
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 52
                    }

                    // Beim Hovern: abgedunkelt mit Stift, Klick waehlt ein Bild
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Colors.alpha("#000000", 0.45)
                        opacity: avatarHover.hovered || User.busy === "face" ? 1 : 0

                        Fade on opacity {}

                        Text {
                            anchors.centerIn: parent
                            text: User.busy === "face" ? "hourglass_empty" : "edit"
                            color: "#ffffff"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 26
                        }
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
