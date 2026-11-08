import QtQuick
import QtQuick.Shapes

// Kontur der ISO-Enter-Taste: oben breit, unten schmal, runde Ecken.
// Alle Masse in Pixeln relativ zur Taste; ox/oy verschieben (Oberseite).
ShapePath {
    id: path

    property real ox: 0
    property real oy: 0
    property real w: 10
    property real h: 20
    // Hoehe des oberen, breiten Teils
    property real topH: 10
    // Linke Kante und Breite des unteren Teils (relativ zu ox)
    property real lowerX: 2
    property real lowerW: 8
    property real r: 4

    strokeWidth: 0
    strokeColor: "transparent"
    startX: path.ox + path.r
    startY: path.oy

    PathLine { x: path.ox + path.w - path.r; y: path.oy }
    PathArc { x: path.ox + path.w; y: path.oy + path.r; radiusX: path.r; radiusY: path.r }
    PathLine { x: path.ox + path.w; y: path.oy + path.h - path.r }
    PathArc { x: path.ox + path.w - path.r; y: path.oy + path.h; radiusX: path.r; radiusY: path.r }
    PathLine { x: path.ox + path.lowerX + path.r; y: path.oy + path.h }
    PathArc { x: path.ox + path.lowerX; y: path.oy + path.h - path.r; radiusX: path.r; radiusY: path.r }
    PathLine { x: path.ox + path.lowerX; y: path.oy + path.topH + path.r }
    PathArc { x: path.ox + path.lowerX - path.r; y: path.oy + path.topH; radiusX: path.r; radiusY: path.r; direction: PathArc.Counterclockwise }
    PathLine { x: path.ox + path.r; y: path.oy + path.topH }
    PathArc { x: path.ox; y: path.oy + path.topH - path.r; radiusX: path.r; radiusY: path.r }
    PathLine { x: path.ox; y: path.oy + path.r }
    PathArc { x: path.ox + path.r; y: path.oy; radiusX: path.r; radiusY: path.r }
}
