pragma ComponentBehavior: Bound
import QtQuick

// Eine Anforderung an einen Dienst – siehe Demand.qml. Meldet sich beim
// Zerstoeren (Monitor weg, Loader aus) selbst wieder ab.
QtObject {
    id: root

    required property Demand demand
    property bool active: false

    property string key: ""

    onActiveChanged: if (root.key !== "") root.demand.set(root.key, root.active)

    Component.onCompleted: {
        root.key = root.demand.newKey();
        root.demand.set(root.key, root.active);
    }
    Component.onDestruction: if (root.key !== "") root.demand.set(root.key, false)
}
