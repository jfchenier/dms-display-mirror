import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property bool autoRefresh: pluginData.autoRefresh ?? false
    property int refreshInterval: pluginData.refreshInterval || 30

    property var monitors: []
    property bool isLoading: false
    property bool justStartedMirror: false  // Track if we just started a mirror vs checking status
    property string lastStartedSource: ""   // Track which source we just started mirroring
    
    // Use shared singleton state so all widget instances see the same values
    // activeMirrors structure: {pid: {source: "outputName", target: "outputName"}}
    readonly property var activeMirrors: MirrorState.activeMirrors
    readonly property bool hasActiveMirrors: MirrorState.hasActiveMirrors
    readonly property int activeMirrorCount: MirrorState.activeMirrorCount
    property string lastMirrorOutput: ""
    property string lastMirrorError: ""
    property string currentFocusedOutput: ""
    // Incremented whenever mirror state changes to force dependent bindings to reevaluate
    property int mirrorVersion: 0

    // Helper functions to manage mirrors
    function addMirror(pid, source, target) {
        console.log("MonitorMirror: Adding mirror PID", pid, "source:", source, "target:", target)
        var mirrors = Object.assign({}, MirrorState.activeMirrors)
        mirrors[pid] = {source: source, target: target}
        MirrorState.activeMirrors = mirrors
    }
    
    function removeMirror(pid) {
        console.log("MonitorMirror: Removing mirror PID", pid)
        var mirrors = Object.assign({}, MirrorState.activeMirrors)
        delete mirrors[pid]
        MirrorState.activeMirrors = mirrors
    }
    
    function getMirrorsBySource(sourceName) {
        var result = []
        var mirrors = Object.keys(MirrorState.activeMirrors)
        for (let i = 0; i < mirrors.length; i++) {
            const pid = mirrors[i]
            const mirror = MirrorState.activeMirrors[pid]
            if (mirror.source === sourceName) {
                result.push({pid: pid, target: mirror.target})
            }
        }
        return result
    }

    // Return monitors excluding the current focused/active display and any display currently being used as a mirror target
    function filteredMonitors() {
        if (!currentFocusedOutput) return monitors
        
        // Check if current display is already being used as a source
        const pids = Object.keys(MirrorState.activeMirrors)
        for (let i = 0; i < pids.length; i++) {
            const mirror = MirrorState.activeMirrors[pids[i]]
            if (mirror && mirror.source === currentFocusedOutput) {
                // Current display is already mirroring, hide all available displays
                return []
            }
        }
        
        // Get all displays currently being used as mirror targets
        const targetDisplays = new Set()
        for (let i = 0; i < pids.length; i++) {
            const mirror = MirrorState.activeMirrors[pids[i]]
            if (mirror && mirror.target) {
                targetDisplays.add(mirror.target)
            }
        }
        
        // Filter out current focused output and target displays
        return monitors.filter(m => m !== currentFocusedOutput && !targetDisplays.has(m))
    }

    // Control Center tile properties
    ccWidgetIcon: "screen_share"
    ccWidgetPrimaryText: "Display Mirror"
    // Secondary text: show count of active mirrors or a clear no-active state
    // mirrorVersion included indirectly via hasActiveMirrors / activeMirrorCount updates, and explicit bump for reliability
    ccWidgetSecondaryText: hasActiveMirrors
        ? (activeMirrorCount + " active mirror" + (activeMirrorCount > 1 ? "s" : ""))
        : "No active mirror"
    ccWidgetIsActive: hasActiveMirrors

    onCcWidgetToggled: {
        if (hasActiveMirrors) {
            stopAllMirrors()
        }
    }

    // Listen to singleton changes to ensure tile text & info areas update immediately
    Connections {
        target: MirrorState
        function onMirrorsChanged() {
            // Force a reevaluation by bumping version counter
            mirrorVersion++
            console.log("MonitorMirror: mirrorsChanged received; version=" + mirrorVersion + ", count=" + MirrorState.activeMirrorCount)
        }
    }

    Component.onCompleted: {
        console.log("MonitorMirror: Widget completed. activeMirrorCount:", activeMirrorCount, "hasActiveMirrors:", hasActiveMirrors)
        refreshMonitors()
        detectFocusedOutput()
        checkMirrorStatus()
    }

    // Removed redundant reassignment Connections; bindings are direct now

    Timer {
        id: refreshTimer
        interval: root.refreshInterval * 1000
        repeat: true
        running: root.autoRefresh
        onTriggered: {
            if (!root.isLoading) {
                root.refreshMonitors()
                root.detectFocusedOutput()
            }
        }
    }

    function refreshMonitors() {
        isLoading = true
        monitorProcess.running = true
    }

    function detectFocusedOutput() {
        focusedOutputProcess.running = true
    }

    function startMirror(outputName) {
        if (!outputName || isLoading) return

        // Detect current focused output first
        detectFocusedOutput()
        
        // Wait a moment for focus detection, then start mirror
        Qt.callLater(() => {
            const targetOutput = root.currentFocusedOutput
            if (!targetOutput) {
                console.warn("MonitorMirror: Could not detect target output")
                lastMirrorError = "Could not detect current display"
                return
            }
            
            if (targetOutput === outputName) {
                console.log("MonitorMirror: Cannot mirror display to itself")
                lastMirrorError = "Cannot mirror a display to itself"
                return
            }

            isLoading = true
            justStartedMirror = true
            lastStartedSource = outputName
            lastMirrorError = ""
            lastMirrorOutput = ""
            
            // Launch wl-mirror in background, echo its PID
            const safeOutput = outputName.replace(/"/g, '\\"')
            mirrorProcess.command = ["sh", "-c", "wl-mirror --fullscreen \"" + safeOutput + "\" >/dev/null 2>&1 & echo $!"]
            mirrorProcess.running = true
        })
    }

    function stopMirror(pid) {
        if (pid && MirrorState.activeMirrors[pid]) {
            const mirror = MirrorState.activeMirrors[pid]
            console.log("MonitorMirror: Stopping mirror PID", pid, "source:", mirror.source, "target:", mirror.target)
            Quickshell.execDetached(["sh", "-c", "kill " + pid + " 2>/dev/null"])
            removeMirror(pid)
            Quickshell.execDetached(["sh", "-c", "notify-send 'Display Mirror' 'Stopped mirroring " + mirror.source + " → " + mirror.target + "' -u low"])
        }
    }
    
    function stopAllMirrors() {
        console.log("MonitorMirror: Stopping all mirrors")
        // Always reference MirrorState directly to avoid breaking binding
        const pids = Object.keys(MirrorState.activeMirrors)
        for (let i = 0; i < pids.length; i++) {
            const pid = pids[i]
            Quickshell.execDetached(["sh", "-c", "kill " + pid + " 2>/dev/null"])
        }
        // Clear via singleton; do not assign root.activeMirrors which would sever binding
        MirrorState.activeMirrors = {}
        Quickshell.execDetached(["sh", "-c", "notify-send 'Display Mirror' 'All mirrors stopped' -u low"])
    }

    function checkMirrorStatus() {
        console.log("MonitorMirror: Checking status of", activeMirrorCount, "mirrors")
    const pids = Object.keys(MirrorState.activeMirrors)
        for (let i = 0; i < pids.length; i++) {
            const pid = pids[i]
            verifyMirrorProcess.command = ["sh", "-c", "ps -p " + pid + " -o pid= || true"]
            verifyMirrorProcess.tag = pid  // Store which PID we're checking
            verifyMirrorProcess.running = true
        }
    }

    Process {
        id: monitorProcess
        command: ["sh", "-c", "niri msg outputs | grep '^Output' | cut -d'(' -f 2 | cut -d')' -f 1"]
        running: false

        property var monitorList: []

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                // Each read is now a single line thanks to splitMarker
                const line = data.trim()
                if (line.length > 0) {
                    monitorProcess.monitorList.push(line)
                    console.log("MonitorMirror: Added monitor:", line, "- total now:", monitorProcess.monitorList.length)
                }
            }
        }

        onRunningChanged: {
            if (running) {
                monitorList = []
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.isLoading = false
            if (exitCode === 0) {
                console.log("MonitorMirror: Process exited, collected", monitorProcess.monitorList.length, "monitors")
                // Force QML to recognize array change by creating new array reference
                root.monitors = []
                root.monitors = monitorProcess.monitorList.slice()
                console.log("MonitorMirror: Set root.monitors to", root.monitors.length, "items:", JSON.stringify(root.monitors))
            } else {
                console.warn("MonitorMirror: Failed to get monitors, exit code:", exitCode)
                root.monitors = []
            }
        }
    }

    Process {
        id: focusedOutputProcess
        command: ["sh", "-c", "niri msg focused-output 2>/dev/null | grep -oP '(?<=\\().*(?=\\))' | head -1"]
        running: false

        stdout: SplitParser {
            onRead: data => {
                const output = data.trim()
                if (output.length > 0) {
                    root.currentFocusedOutput = output
                    console.log("MonitorMirror: Detected focused output:", output)
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn("MonitorMirror: Failed to detect focused output, exit code:", exitCode)
            }
        }
    }

    Process {
        id: mirrorProcess
        command: ["sh", "-c", ""]
        running: false

        stdout: SplitParser {
            onRead: data => {
                const pid = data.trim()
                lastMirrorOutput = pid
                // Add mirror with source and target we just started
                if (lastStartedSource && pid && currentFocusedOutput) {
                    root.addMirror(pid, lastStartedSource, currentFocusedOutput)
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.isLoading = false
            const pid = lastMirrorOutput
            if (pid && lastStartedSource) {
                // Verify the process actually exists
                verifyMirrorProcess.command = ["sh", "-c", "ps -p " + pid + " -o pid= || true"]
                verifyMirrorProcess.tag = pid
                verifyMirrorProcess.running = true
            } else if (exitCode !== 0) {
                console.warn("MonitorMirror: Failed to start mirror, exit code:", exitCode)
                lastMirrorError = "Failed to start wl-mirror (exit " + exitCode + ")"
                Quickshell.execDetached(["sh", "-c", "notify-send 'Display Mirror' 'Failed to start mirror' -u critical"])
                justStartedMirror = false
                lastStartedSource = ""
            }
        }
    }

    Process {
        id: verifyMirrorProcess
        command: ["sh", "-c", ""]
        running: false
        property string tag: ""  // Store which PID we're verifying
        
        stdout: SplitParser {
            onRead: data => {
                const exists = data.trim().length > 0
                const pid = verifyMirrorProcess.tag
                console.log("MonitorMirror: Verify result for PID", pid, "- exists:", exists)
                
                if (exists && root.justStartedMirror && pid === root.lastMirrorOutput) {
                    // Only send notification when we actually started a mirror
                    const mirror = MirrorState.activeMirrors[pid]
                    if (mirror) {
                        Quickshell.execDetached(["sh", "-c", "notify-send 'Display Mirror' 'Now mirroring " + mirror.source + " → " + mirror.target + "' -u low"])
                    }
                    root.justStartedMirror = false
                    root.lastStartedSource = ""
                } else if (!exists) {
                    if (root.justStartedMirror && pid === root.lastMirrorOutput) {
                        lastMirrorError = "wl-mirror process vanished immediately"
                        Quickshell.execDetached(["sh", "-c", "notify-send 'Display Mirror' 'Mirror failed (no process)' -u critical"])
                        root.justStartedMirror = false
                        root.lastStartedSource = ""
                    } else {
                        lastMirrorError = "wl-mirror process vanished"
                    }
                    // Remove the dead mirror
                    if (pid) {
                        root.removeMirror(pid)
                    }
                }
            }
        }
    }

    // Provide bar pills so widget is visible if added to DankBar (even though capability is control-center)
    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            DankIcon {
                name: root.hasActiveMirrors ? "screen_share" : "monitor"
                size: Theme.iconSize - 6
                color: root.hasActiveMirrors ? Theme.primary : Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: root.hasActiveMirrors ? (root.activeMirrorCount + " active") : (filteredMonitors().length + " mon")
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS
            DankIcon {
                name: root.hasActiveMirrors ? "screen_share" : "monitor"
                size: Theme.iconSize - 6
                color: root.hasActiveMirrors ? Theme.primary : Theme.surfaceVariantText
                anchors.horizontalCenter: parent.horizontalCenter
            }
            StyledText {
                text: root.hasActiveMirrors ? root.activeMirrorCount : (filteredMonitors().length + "m")
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.surfaceVariantText
                anchors.horizontalCenter: parent.horizontalCenter
                rotation: 90
            }
        }
    }

    // Popout used when user clicks pill (bar)
    popoutContent: Component {
        PopoutComponent {
            id: detailPopout

            headerText: "Display Mirror"
            detailsText: filteredMonitors().length + " monitors available"
            showCloseButton: true

            Column {
                id: popoutColumn
                width: parent.width
                spacing: Theme.spacingM

                // Refresh button
                Row {
                    width: parent.width
                    spacing: Theme.spacingS

                    DankButton {
                        text: "Refresh Monitors"
                        iconName: "refresh"
                        onClicked: root.refreshMonitors()
                        enabled: !root.isLoading
                    }

                    DankButton {
                        text: "Stop All Mirrors"
                        iconName: "stop"
                        onClicked: root.stopAllMirrors()
                        enabled: root.hasActiveMirrors
                        visible: root.hasActiveMirrors
                    }
                }

                // Loading indicator
                StyledRect {
                    width: parent.width
                    height: 40
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    visible: root.isLoading

                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.spacingS

                        DankIcon {
                            name: "sync"
                            size: Theme.iconSize
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter

                            RotationAnimation on rotation {
                                from: 0
                                to: 360
                                duration: 1000
                                loops: Animation.Infinite
                                running: root.isLoading
                            }
                        }

                        StyledText {
                            text: "Loading displays..."
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                // Active mirrors - one box per mirror (shown above available displays)
                Column {
                    width: parent.width
                    spacing: Theme.spacingS
                    visible: root.hasActiveMirrors

                    Repeater {
                        model: Object.keys(MirrorState.activeMirrors)

                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            
                            width: parent.width
                            height: mirrorStatusRow.implicitHeight + Theme.spacingM * 2
                            radius: Theme.cornerRadius
                            color: Theme.primaryPressed
                            border.width: 2
                            border.color: Theme.primary

                            RowLayout {
                                id: mirrorStatusRow
                                anchors.fill: parent
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingM

                                DankIcon {
                                    name: "screen_share"
                                    size: Theme.iconSize
                                    color: Theme.primary
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Column {
                                    spacing: 2
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.fillWidth: true
                                    
                                    StyledText {
                                        text: {
                                            const mirror = root.activeMirrors[modelData]
                                            return mirror ? (mirror.source + " → " + mirror.target) : "Unknown"
                                        }
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Medium
                                        color: Theme.primary
                                        elide: Text.ElideRight
                                        wrapMode: Text.NoWrap
                                        width: parent.width
                                    }
                                    
                                    StyledText {
                                        text: "PID: " + modelData
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceTextMedium
                                    }
                                }

                                DankButton {
                                    id: stopButton
                                    text: "Stop"
                                    iconName: "stop"
                                    onClicked: root.stopMirror(modelData)
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }
                        }
                    }
                }

                // Error display (if any)
                StyledRect {
                    width: parent.width
                    height: errorColumnPopout.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    visible: root.lastMirrorError !== ""

                    Column {
                        id: errorColumnPopout
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        Row {
                            spacing: Theme.spacingM

                            DankIcon {
                                name: "error"
                                size: Theme.iconSize
                                color: Theme.warning || Theme.error
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: "Mirror Error"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                            }
                        }

                        StyledText {
                            text: root.lastMirrorError
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            wrapMode: Text.WordWrap
                            leftPadding: Theme.iconSize + Theme.spacingM
                            width: parent.width - Theme.spacingM * 2
                        }
                    }
                }

                // Monitor list (available displays)
                Column {
                    width: parent.width
                    spacing: Theme.spacingS
                    visible: filteredMonitors().length > 0 && !root.isLoading

                    StyledText {
                        text: "Available Monitors (" + filteredMonitors().length + " total)"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    Repeater {
                        model: filteredMonitors()

                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: parent.width
                            height: 60
                            radius: Theme.cornerRadius
                            color: monitorArea.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08) : Theme.withAlpha(Theme.surfaceContainerHighest, Theme.popupTransparency)
                            border.color: Theme.primary
                            border.width: 0

                            Row {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingM

                                DankIcon {
                                    name: "monitor"
                                    size: Theme.iconSize + 8
                                    color: Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.spacingXS

                                    StyledText {
                                        text: modelData
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Medium
                                        color: Theme.surfaceText
                                    }

                                    StyledText {
                                        text: "Click to mirror this output"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                DankIcon {
                                    name: "arrow_forward"
                                    size: Theme.iconSize
                                    color: Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: monitorArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.startMirror(modelData)
                                }
                            }
                        }
                    }
                }

                // Empty state (popout)
                StyledRect {
                    width: parent.width
                    height: 100
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    visible: filteredMonitors().length === 0 && !root.isLoading

                    Column {
                        anchors.centerIn: parent
                        spacing: Theme.spacingS

                        DankIcon {
                            name: root.monitors.length === 0 ? "monitor_off" : "check_circle"
                            size: Theme.iconSize + 16
                            color: Theme.surfaceVariantText
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        StyledText {
                            text: root.monitors.length === 0 ? "No displays found" : "No displays available"
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        StyledText {
                            text: "Make sure niri is running"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: root.monitors.length === 0
                        }
                    }
                }

                // Active mirrors - one box per mirror
                Column {
                    width: parent.width
                    spacing: Theme.spacingS
                    visible: root.hasActiveMirrors

                    Repeater {
                        model: Object.keys(MirrorState.activeMirrors)

                        delegate: StyledRect {
                            required property var modelData
                            required property int index
                            
                            width: parent.width
                            height: mirrorStatusRow.implicitHeight + Theme.spacingM * 2
                            radius: Theme.cornerRadius
                            color: Theme.primaryContainer

                            Row {
                                id: mirrorStatusRow
                                anchors.fill: parent
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingM

                                DankIcon {
                                    name: "screen_share"
                                    size: Theme.iconSize
                                    color: Theme.onPrimaryContainer || Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - Theme.iconSize - stopButton.width - Theme.spacingM * 3
                                    spacing: Theme.spacingXS
                                    
                                    StyledText {
                                        text: {
                                            const mirror = root.activeMirrors[modelData]
                                            return mirror ? (mirror.source + " → " + mirror.target) : "Unknown"
                                        }
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Medium
                                        color: Theme.onPrimaryContainer || Theme.surfaceText
                                    }
                                    
                                    StyledText {
                                        text: "PID: " + modelData
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.onPrimaryContainer || Theme.surfaceVariantText
                                        opacity: 0.7
                                    }
                                }

                                Item {
                                    width: 1
                                    height: 1
                                }

                                DankButton {
                                    id: stopButton
                                    text: "Stop"
                                    iconName: "stop"
                                    onClicked: root.stopMirror(modelData)
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }
                }

                // Error display (if any)
                StyledRect {
                    width: parent.width
                    height: errorColumn.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    visible: root.lastMirrorError !== ""

                    Column {
                        id: errorColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        Row {
                            spacing: Theme.spacingM

                            DankIcon {
                                name: "error"
                                size: Theme.iconSize
                                color: Theme.warning || Theme.error
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: "Mirror Error"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                            }
                        }

                        StyledText {
                            text: root.lastMirrorError
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            wrapMode: Text.WordWrap
                            leftPadding: Theme.iconSize + Theme.spacingM
                            width: parent.width - Theme.spacingM * 2
                        }
                    }
                }
            }
        }
    }

    // Control Center detail panel (when clicking the CC tile arrow/chevron)
    ccDetailContent: Component {
        Rectangle {
            implicitHeight: Math.min(headerRow.height + contentFlickable.contentHeight + Theme.spacingM * 2, 400 + headerRow.height)
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
            border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.08)
            border.width: 0
            visible: true

            onVisibleChanged: {
                if (visible) {
                    console.log("MonitorMirror: CC Detail became visible, checking mirror status")
                    root.checkMirrorStatus()
                }
            }

            Component.onCompleted: {
                console.log("MonitorMirror: CC Detail opened, checking mirror status")
                root.checkMirrorStatus()
            }

            Row {
                id: headerRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: Theme.spacingM
                anchors.rightMargin: Theme.spacingM
                anchors.topMargin: Theme.spacingS
                height: 40

                StyledText {
                    id: headerText
                    text: "Display Mirror"
                    font.pixelSize: Theme.fontSizeLarge
                    color: Theme.surfaceText
                    font.weight: Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                }

                Item {
                    width: Math.max(0, parent.width - headerText.implicitWidth - refreshButton.width - Theme.spacingM)
                    height: parent.height
                }

                DankButton {
                    id: refreshButton
                    text: "Refresh"
                    iconName: "refresh"
                    onClicked: {
                        root.refreshMonitors()
                        root.detectFocusedOutput()
                    }
                    enabled: !root.isLoading
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            DankFlickable {
                id: contentFlickable
                anchors.top: headerRow.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.topMargin: Theme.spacingM
                anchors.leftMargin: Theme.spacingM
                anchors.rightMargin: Theme.spacingM
                anchors.bottomMargin: Theme.spacingM
                contentHeight: ccContentColumn.implicitHeight
                clip: true

                Column {
                    id: ccContentColumn
                    width: parent.width
                    spacing: Theme.spacingM

                // Loading indicator
                StyledRect {
                    width: parent.width
                    height: 40
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    visible: root.isLoading

                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.spacingS

                        DankIcon {
                            name: "sync"
                            size: Theme.iconSize
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter

                            RotationAnimation on rotation {
                                from: 0
                                to: 360
                                duration: 1000
                                loops: Animation.Infinite
                                running: root.isLoading
                            }
                        }

                        StyledText {
                            text: "Loading displays..."
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                // Info text (CC detail)
                StyledText {
                    width: parent.width - Theme.spacingM * 2
                    text: hasActiveMirrors ? (activeMirrorCount + " display" + (activeMirrorCount > 1 ? "s" : "") + " currently being mirrored.") : (currentFocusedOutput ? "Choose an output to start mirroring on the current display" : "Select a display to mirror")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                    visible: filteredMonitors().length > 0 && !root.isLoading
                    bottomPadding: Theme.spacingS
                }

                // Active mirror status boxes (one per mirror) - shown above available displays
                Column {
                    width: parent.width
                    spacing: Theme.spacingS
                    
                    Repeater {
                        model: Object.keys(MirrorState.activeMirrors)
                        
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            
                            width: parent.width
                            height: mirrorRowCCDetail.implicitHeight + Theme.spacingM * 2
                            radius: Theme.cornerRadius
                            color: Theme.primaryPressed
                            border.width: 2
                            border.color: Theme.primary
                            
                            RowLayout {
                                id: mirrorRowCCDetail
                                anchors.fill: parent
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingM
                                
                                DankIcon {
                                    name: "screen_share"
                                    size: Theme.iconSize
                                    color: Theme.primary
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                
                                Column {
                                    spacing: 2
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.fillWidth: true
                                    
                                    StyledText {
                                        text: {
                                            const mirror = root.activeMirrors[modelData]
                                            return mirror ? (mirror.source + " → " + mirror.target) : "Unknown"
                                        }
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Medium
                                        color: Theme.primary
                                        elide: Text.ElideRight
                                        wrapMode: Text.NoWrap
                                        width: parent.width
                                    }
                                    
                                    StyledText {
                                        text: "PID: " + modelData
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceTextMedium
                                    }
                                }
                                
                                DankButton {
                                    id: stopButtonCCDetail
                                    text: "Stop"
                                    iconName: "stop"
                                    onClicked: root.stopMirror(modelData)
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }
                        }
                    }
                    
                    // Error display
                    StyledRect {
                        width: parent.width
                        height: errorColumnCCDetail.implicitHeight + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh
                        visible: root.lastMirrorError !== ""
                        
                        Column {
                            id: errorColumnCCDetail
                            anchors.fill: parent
                            anchors.margins: Theme.spacingM
                            spacing: Theme.spacingS
                            
                            Row {
                                width: parent.width
                                spacing: Theme.spacingM
                                
                                DankIcon {
                                    name: "error"
                                    size: Theme.iconSize
                                    color: Theme.warning || Theme.error
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                
                                StyledText {
                                    text: "Mirror Error"
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Medium
                                    color: Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            
                            StyledText {
                                text: "Attempted to start mirror. " + (root.lastMirrorError || "Unknown issue.")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                wrapMode: Text.WordWrap
                                leftPadding: Theme.iconSize + Theme.spacingM
                                width: parent.width - Theme.spacingM * 2
                            }
                        }
                    }
                }

                // Monitor list (available displays)
                Column {
                    width: parent.width
                    spacing: Theme.spacingS
                    visible: filteredMonitors().length > 0 && !root.isLoading

                    Repeater {
                        model: filteredMonitors()

                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            
                            width: parent.width
                            height: 60
                            radius: Theme.cornerRadius
                            color: monitorArea.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08) : Theme.withAlpha(Theme.surfaceContainerHighest, Theme.popupTransparency)
                            border.color: Theme.outline
                            border.width: 0

                            Row {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingM

                                DankIcon {
                                    name: "monitor"
                                    size: Theme.iconSize + 8
                                    color: Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.spacingXS
                                    width: parent.width - Theme.iconSize - Theme.spacingM * 2

                                    StyledText {
                                        text: modelData
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Medium
                                        color: Theme.surfaceText
                                    }

                                    StyledText {
                                        text: "Click to start mirroring"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                    }
                                }

                                Item {
                                    width: 1
                                    height: 1
                                }
                            }

                            MouseArea {
                                id: monitorArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.startMirror(modelData)
                                }
                            }
                        }
                    }
                }

                // Empty state (CC detail)
                StyledRect {
                    width: parent.width
                    height: 100
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    visible: filteredMonitors().length === 0 && !root.isLoading

                    Column {
                        anchors.centerIn: parent
                        spacing: Theme.spacingS

                        DankIcon {
                            name: root.monitors.length === 0 ? "monitor_off" : "check_circle"
                            size: Theme.iconSize + 16
                            color: Theme.surfaceVariantText
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        StyledText {
                            text: root.monitors.length === 0 ? "No displays found" : "No displays available"
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        StyledText {
                            text: "Make sure niri is running"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: root.monitors.length === 0
                        }
                    }
                }
            }
        }
        }
    }

    popoutWidth: 400
}
