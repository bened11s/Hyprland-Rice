pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import qs.modules.services.core

// Pegel fuer den Visualiser – kommt von cava, das PipeWire abhoert und die
// Frequenzbaender fertig ausgerechnet ausgibt.
//
// cava ist ein eigener Prozess, der laeuft also NICHT dauerhaft: `enabled`
// wird vom Verbraucher gesetzt (am besten per `Binding`, dann geht es beim
// Zerstoeren automatisch wieder aus). Die Medien-Pille schaltet ihn nur an,
// solange wirklich etwas spielt.
//
// Die Config kommt ueber stdin statt aus einer Datei – so gibt es keine
// zweite Stelle, die zur Balkenzahl passen muss.
//
// Mono: values[0] = Bass, aufsteigend zu den Hoehen. Im cava-Standard
// (Stereo) laege der linke Kanal gespiegelt vorn (Hoehen zuerst, Bass in der
// Mitte) – alle Visualiser hier rechnen aber mit "Bass zuerst".
Singleton {
    id: root

    // Anzahl der Baender. Aenderung startet cava neu (die Zahl steht in der
    // Config), deshalb bewusst EIN Wert fuer alle Verbraucher: der Ring im
    // Popout braucht viele, die Pille nur vier – die rechnet sie sich per
    // `bucket()` aus denselben Daten zusammen.
    property int bars: 36
    // Bildrate von cava. Hoeher = fluessiger und teurer.
    property int framerate: 30
    // Verbraucher schalten den Prozess an und aus – per DemandRequest, damit
    // sich die Leisten mehrerer Monitore nicht gegenseitig ueberschreiben
    readonly property Demand demand: Demand {}
    readonly property bool enabled: root.demand.active

    // Ein Wert je Balken, 0..1. Solange nichts laeuft: alles auf 0, damit die
    // UI nicht auf dem letzten Ausschlag stehen bleibt.
    property var values: Array(root.bars).fill(0)

    // Letzte Rohzeile von cava – identische Frames (Stille, Pausen) werden
    // gar nicht erst zugewiesen, sonst rechnet jeder Verbraucher umsonst neu.
    property string lastFrame: ""

    onEnabledChanged: {
        root.lastFrame = "";
        if (!root.enabled) {
            root.values = Array(root.bars).fill(0);
            linger.restart();
        }
    }

    // Nachlauf: cava bleibt nach dem Abschalten noch kurz am Leben. Kurze
    // Pausen (YouTube-Shorts melden bei jedem Loop Paused/Playing, Titel-
    // wechsel) starteten sonst jedes Mal Prozess UND PipeWire-Stream neu –
    // ein sterbender Stream-Knoten war am 2026-10-15 der Crash-Ausloeser.
    Timer {
        id: linger

        interval: 5000
    }

    // Mittelwert der i-ten von n Gruppen – damit eine Anzeige mit weniger
    // Balken dieselbe Quelle nutzen kann, statt cava ein zweites Mal zu starten.
    function bucket(i: int, n: int): real {
        const vals = root.values;
        if (!vals.length || n <= 0)
            return 0;

        const size = vals.length / n;
        const from = Math.floor(i * size);
        const to = Math.max(from + 1, Math.floor((i + 1) * size));

        let sum = 0;
        for (let k = from; k < to && k < vals.length; k++)
            sum += vals[k];
        return sum / (to - from);
    }

    Process {
        id: proc

        running: root.enabled || linger.running
        command: ["sh", "-c",
            `printf '%s' "[general]
framerate=${root.framerate}
bars=${root.bars}
[output]
channels=mono
mono_option=average
method=raw
raw_target=/dev/stdout
data_format=ascii
ascii_max_range=100
[smoothing]
noise_reduction=30
" | cava -p /dev/stdin`]

        stdout: SplitParser {
            // cava schreibt eine Zeile pro Frame: "12;40;33;7;"
            onRead: data => {
                if (!root.enabled || data === root.lastFrame)
                    return;
                root.lastFrame = data;
                const parts = data.split(";").filter(v => v !== "");
                if (parts.length !== root.bars)
                    return;
                root.values = parts.map(v => Math.max(0, Math.min(1, Number(v) / 100)));
            }
        }
    }
}
