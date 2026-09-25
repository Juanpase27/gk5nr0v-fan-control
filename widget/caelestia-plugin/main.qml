pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// GK5NR0V fan monitor: compact top-right overlay showing CPU/GPU fan RPMs
// (from the gk5nr0v-fans hwmon module) plus k10temp CPU temp and dGPU core
// temp. Self-contained on purpose: only QtQuick + Quickshell imports, no
// Caelestia internals, so shell updates cannot break it.

Item {
    id: root

    property real cpuTemp: 0
    property int cpuRpm: -1
    property int gpuRpm: -1
    property real gpuTemp: 0

    readonly property string scriptPath: {
        // Qt.resolvedUrl returns a QUrl, not a string: coerce before slicing.
        const url = Qt.resolvedUrl("read-sensors.sh").toString();
        return url.startsWith("file://") ? url.substring(7) : url;
    }

    function tempColor(t: real): color {
        if (t <= 0) return "#8a8f98";
        if (t < 60) return "#7ec8ff";
        if (t < 72) return "#9fe8a0";
        if (t < 82) return "#ffcc66";
        return "#ff7a7a";
    }

    function parse(text: string): void {
        const lines = text.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            const eq = line.indexOf("=");
            if (eq <= 0) continue;
            const key = line.slice(0, eq);
            const val = line.slice(eq + 1).trim();
            if (key === "cpu_rpm") root.cpuRpm = parseInt(val) || 0;
            else if (key === "gpu_rpm") root.gpuRpm = parseInt(val) || 0;
            else if (key === "cpu_t") root.cpuTemp = parseFloat(val) || 0;
        }
    }

    function parseGpu(text: string): void {
        const lines = text.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            const eq = line.indexOf("=");
            if (eq <= 0) continue;
            if (line.slice(0, eq) === "gpu_t")
                root.gpuTemp = parseFloat(line.slice(eq + 1)) || 0;
        }
    }

    Process {
        id: sensorsProc

        command: ["/usr/bin/bash", root.scriptPath]
        stdout: StdioCollector {
            id: sensorsOut
        }
        onExited: (code, status) => root.parse(sensorsOut.text)
    }

    Process {
        id: gpuTempProc

        command: ["/usr/bin/bash", root.scriptPath, "gpu"]
        stdout: StdioCollector {
            id: gpuOut
        }
        onExited: (code, status) => root.parseGpu(gpuOut.text)
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: sensorsProc.running = true
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: gpuTempProc.running = true
    }

    PanelWindow {
        // Quickshell 0.3 has no primaryScreen: index the screens list
        // (single-panel laptop; revisit if a docked monitor appears).
        screen: Quickshell.screens[0]
        visible: true
        exclusiveZone: 0

        anchors {
            top: true
            right: true
        }

        margins.top: 48
        margins.right: 12

        implicitWidth: card.width
        implicitHeight: card.height

        Rectangle {
            id: card

            width: 218
            height: 72
            radius: 14
            color: Qt.rgba(0.06, 0.07, 0.11, 0.78)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            Column {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6

                SensorRow {
                    width: parent.width
                    label: "CPU"
                    temp: root.cpuTemp
                    rpm: root.cpuRpm
                }

                SensorRow {
                    width: parent.width
                    label: "GPU"
                    temp: root.gpuTemp
                    rpm: root.gpuRpm
                }
            }
        }

        component SensorRow: Row {
            id: row

            property string label: ""
            property real temp: 0
            property int rpm: -1

            spacing: 8

            Rectangle {
                width: 34
                height: 18
                radius: 5
                anchors.verticalCenter: parent.verticalCenter
                color: Qt.rgba(1, 1, 1, 0.07)

                Text {
                    anchors.centerIn: parent
                    text: row.label
                    color: "#c8cdd6"
                    font.pixelSize: 10
                    font.bold: true
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 52
                text: row.temp > 0 ? row.temp.toFixed(0) + "°" : "--"
                color: root.tempColor(row.temp)
                font.pixelSize: 15
                font.bold: true
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 96
                horizontalAlignment: Text.AlignRight
                text: row.rpm < 0 ? "--" : (row.rpm === 0 ? "fan-stop" : row.rpm + " rpm")
                color: row.rpm === 0 ? "#6b7280" : "#e6e9ef"
                opacity: row.rpm === 0 ? 0.7 : 1
                font.pixelSize: 13
                font.family: "monospace"
            }
        }
    }

    IpcHandler {
        target: "fans"

        function readings(): string {
            return `cpu_t=${root.cpuTemp} cpu_rpm=${root.cpuRpm} gpu_t=${root.gpuTemp} gpu_rpm=${root.gpuRpm}`;
        }
    }
}
