pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

import qs

// Zentrale PipeWire-Quelle fuer Lautstaerke und Geraeteauswahl.
Singleton {
    id: root

    property list<PwNode> sinks: []
    property list<PwNode> sources: []
    // Wiedergabe-Streams der Apps (Browser, Spotify, Spiele ...) – fuer die
    // Lautstaerke je App im Audio-Menue
    property list<PwNode> streams: []

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    // Eingang (Mikrofon) – das Gegenstueck zu volume/muted
    readonly property real sourceVolume: source?.audio?.volume ?? 0
    readonly property bool sourceMuted: source?.audio?.muted ?? false

    function setVolume(value: real): void {
        if (sink?.audio)
            sink.audio.volume = Math.max(0, Math.min(1, value));
    }

    function toggleMute(): void {
        if (sink?.audio)
            sink.audio.muted = !sink.audio.muted;
    }

    function setSourceVolume(value: real): void {
        root.setNodeVolume(root.source, value);
    }

    function toggleSourceMute(): void {
        root.toggleNodeMute(root.source);
    }

    // Pegel und Stummschalten fuer beliebige Knoten (Geraete und App-Streams)
    function setNodeVolume(node: PwNode, value: real): void {
        if (node?.audio)
            node.audio.volume = Math.max(0, Math.min(1, value));
    }

    function toggleNodeMute(node: PwNode): void {
        if (node?.audio)
            node.audio.muted = !node.audio.muted;
    }

    // Name einer App hinter einem Stream
    function streamLabel(node: PwNode): string {
        if (!node)
            return "";
        return node.properties["application.name"]
            || node.properties["application.process.binary"]
            || node.properties["node.description"]
            || node.name
            || "App";
    }

    function setSink(node: PwNode): void {
        Pipewire.preferredDefaultAudioSink = node;
    }

    function setSource(node: PwNode): void {
        Pipewire.preferredDefaultAudioSource = node;
    }

    function nodeName(node: PwNode): string {
        if (!node)
            return "";
        return node.properties["node.name"] || node.name || "";
    }

    function deviceLabel(node: PwNode): string {
        if (!node)
            return I18n.tr("Unbekanntes Gerät");
        return node.properties["node.description"]
            || node.properties["device.description"]
            || node.properties["node.nick"]
            || node.description
            || node.nickname
            || node.name
            || I18n.tr("Unbekanntes Gerät");
    }

    function isSinkSelected(node: PwNode): bool {
        return node === root.sink || node?.id === root.sink?.id || (root.nodeName(node) !== ""
            && root.nodeName(node) === root.nodeName(root.sink));
    }

    function isSourceSelected(node: PwNode): bool {
        return node === root.source || node?.id === root.source?.id || (root.nodeName(node) !== ""
            && root.nodeName(node) === root.nodeName(root.source));
    }

    function refreshNodes(): void {
        const nextSinks = [];
        const nextSources = [];
        const nextStreams = [];
        for (const node of Pipewire.nodes.values) {
            if (!node.audio)
                continue;
            if (node.isStream) {
                // Nur Wiedergabe (Stream/Output/Audio), keine Aufnahme-Streams
                if (!node.isSink && (node.properties["media.class"] ?? "Stream/Output/Audio") === "Stream/Output/Audio")
                    nextStreams.push(node);
                continue;
            }
            if (node.isSink)
                nextSinks.push(node);
            else
                nextSources.push(node);
        }
        const byName = (a, b) => root.deviceLabel(a).localeCompare(root.deviceLabel(b));
        root.sinks = nextSinks.sort(byName);
        root.sources = nextSources.sort(byName);
        root.streams = nextStreams.sort((a, b) => root.streamLabel(a).localeCompare(root.streamLabel(b)));
        root.refreshTracked();
    }

    // Beobachtete Knoten fuer den PwObjectTracker. Bewusst KEIN Binding:
    // valuesChanged/defaultAudioSinkChanged feuern auch aus ~QObject eines
    // sterbenden PwNode heraus. Ein synchrones Neusetzen von objects laesst
    // den Tracker den halb zerstoerten Knoten anfassen -> SIGSEGV
    // (Crash 2026-10-15, Firefox-Stream beim Shorts-Wechsel).
    property list<PwNode> tracked: []

    function refreshTracked(): void {
        root.tracked = [root.sink, root.source, ...root.sinks, ...root.sources, ...root.streams].filter(n => n);
    }

    // Erst nach der laufenden Zerstoerung neu aufbauen; callLater fasst
    // mehrere Signale einer Runde (z. B. PipeWire-Neustart) zusammen.
    function scheduleRefresh(): void {
        Qt.callLater(root.refreshNodes);
    }

    onSinkChanged: Qt.callLater(root.refreshTracked)
    onSourceChanged: Qt.callLater(root.refreshTracked)

    Component.onCompleted: root.refreshNodes()

    Connections {
        target: Pipewire.nodes
        function onValuesChanged(): void { root.scheduleRefresh(); }
    }

    // Macht die PipeWire-Objekt-Properties live beobachtbar
    PwObjectTracker {
        objects: root.tracked
    }
}
