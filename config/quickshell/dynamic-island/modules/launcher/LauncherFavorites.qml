pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// Favoriten des Launchers: eine Liste von Desktop-Entry-IDs, gespeichert unter
// ~/.local/state/quickshell/by-shell/<id>/launcher-favorites.json
Singleton {
    id: root

    readonly property var ids: adapter.ids

    function isFavorite(id: string): bool {
        return root.ids.includes(id);
    }

    function toggle(id: string): void {
        const next = [...root.ids];
        const at = next.indexOf(id);
        if (at < 0)
            next.push(id);
        else
            next.splice(at, 1);

        adapter.ids = next;
        file.writeAdapter();
    }

    FileView {
        id: file

        path: Quickshell.statePath("launcher-favorites.json")
        watchChanges: true
        onFileChanged: reload()
        // Beim ersten Start gibt es die Datei noch nicht – dann einmal anlegen
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                file.writeAdapter();
        }

        adapter: JsonAdapter {
            id: adapter

            property list<string> ids: []
        }
    }
}
