import QtQuick
import Quickshell
import Quickshell.Io

import qs

// Das Logo der Shell (assets/logo.svg), in `tint` eingefaerbt. Die Farbe wird
// im SVG-Text ersetzt statt per Shader gelegt – das bleibt scharf und geht
// auch ohne GPU.
Image {
    id: logo

    property color tint: Colors.primary

    width: 96
    height: width
    sourceSize: Qt.size(width * 2, height * 2)
    source: "data:image/svg+xml;utf8," + encodeURIComponent(file.text().replace(/#ffffff/g, logo.tint.toString()))

    FileView {
        id: file

        path: Quickshell.shellPath("assets/logo.svg")
        blockLoading: true
    }
}
