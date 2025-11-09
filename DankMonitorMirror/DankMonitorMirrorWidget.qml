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
    
    // Use shared singleton state so all widget instances see the same values
    property string activeMirrorPid: MirrorState.activeMirrorPid
    property bool mirrorRunning: MirrorState.mirrorRunning
    property string lastMirrorOutput: ""
    property string lastMirrorError: ""
    property string currentFocusedOutput: ""

    // Update singleton when local properties would change
    function setActiveMirrorPid(pid) {
        console.log("MonitorMirror: Setting activeMirrorPid to:", pid)
        MirrorState.activeMirrorPid = pid
    }
    
    function setMirrorRunning(running) {
        console.log("MonitorMirror: Setting mirrorRunning to:", running)
        MirrorState.mirrorRunning = running
    }

    // Return monitors excluding the current focused/active display
    function filteredMonitors() {
        if (!currentFocusedOutput) return monitors
        return monitors.filter(m => m !== currentFocusedOutput)
    }

    // Control Center tile properties
    ccWidgetIcon: "screen_share"
    ccWidgetPrimaryText: "Display Mirror"
    ccWidgetSecondaryText: activeMirrorPid ? "Mirror active" : (monitors.length + " outputs")
    ccWidgetIsActive: mirrorRunning

    onCcWidgetToggled: {
        if (activeMirrorPid) {
            stopMirror()
        }
    }

    Component.onCompleted: {
        console.log("MonitorMirror: Widget completed. activeMirrorPid:", activeMirrorPid, "mirrorRunning:", mirrorRunning, "env PID:", Quickshell.env.DANK_MIRROR_PID, "env RUNNING:", Quickshell.env.DANK_MIRROR_RUNNING)
        refreshMonitors()
        detectFocusedOutput()
    }

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

        // Stop any existing mirror first
        stopMirror()

        isLoading = true
        justStartedMirror = true  // Mark that we're starting a new mirror
        lastMirrorError = ""
        lastMirrorOutput = ""
        // Launch wl-mirror in background, echo its PID; keep stderr separate for diagnostics
        const safeOutput = outputName.replace(/"/g, '\\"')
        // Start in fullscreen so the mirror occupies the entire target output immediately
        mirrorProcess.command = ["sh", "-c", "wl-mirror --fullscreen \"" + safeOutput + "\" >/dev/null 2>&1 & echo $!" ]
        mirrorProcess.running = true
    }

    function stopMirror() {
        if (activeMirrorPid) {
            Quickshell.execDetached(["sh", "-c", "kill " + activeMirrorPid + " 2>/dev/null" ])
            setActiveMirrorPid("")
            setMirrorRunning(false)
            Quickshell.execDetached(["sh", "-c", "notify-send 'Display Mirror' 'Mirror stopped' -u low"])
        }
    }

    function checkMirrorStatus() {
        console.log("MonitorMirror: Checking mirror status, activeMirrorPid:", activeMirrorPid)
        if (activeMirrorPid) {
            verifyMirrorProcess.command = ["sh", "-c", "ps -p " + activeMirrorPid + " -o pid= || true"]
            verifyMirrorProcess.running = true
        } else {
            console.log("MonitorMirror: No active PID to check")
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
                root.setActiveMirrorPid(data.trim())
                lastMirrorOutput = data.trim()
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.isLoading = false
            if (root.activeMirrorPid) {
                // Verify the process actually exists
                verifyMirrorProcess.command = ["sh", "-c", "ps -p " + root.activeMirrorPid + " -o pid= || true" ]
                verifyMirrorProcess.running = true
            } else if (exitCode !== 0) {
                console.warn("MonitorMirror: Failed to start mirror, exit code:", exitCode)
                lastMirrorError = "Failed to start wl-mirror (exit " + exitCode + ")"
                Quickshell.execDetached(["sh", "-c", "notify-send 'Display Mirror' 'Failed to start mirror' -u critical"])
            }
        }
    }

    Process {
        id: verifyMirrorProcess
        command: ["sh", "-c", ""]
        running: false
        stdout: SplitParser {
            onRead: data => {
                const exists = data.trim().length > 0
                console.log("MonitorMirror: Verify result - PID exists:", exists, "data:", data.trim())
                root.setMirrorRunning(exists)
                if (exists && root.justStartedMirror) {
                    // Only send notification when we actually started a mirror, not when checking status
                    Quickshell.execDetached(["sh", "-c", "notify-send 'Display Mirror' 'Mirror started (PID " + root.activeMirrorPid + ")' -u low"])
                    root.justStartedMirror = false
                } else if (!exists) {
                    if (root.justStartedMirror) {
                        lastMirrorError = "wl-mirror process vanished immediately"
                        Quickshell.execDetached(["sh", "-c", "notify-send 'Display Mirror' 'Mirror failed (no process)' -u critical"])
                        root.justStartedMirror = false
                    } else {
                        lastMirrorError = "wl-mirror process vanished"
                    }
                    root.setActiveMirrorPid("")
                }
            }
        }
    }

    // Provide bar pills so widget is visible if added to DankBar (even though capability is control-center)
    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            DankIcon {
                name: root.activeMirrorPid ? "screen_share" : "monitor"
                size: Theme.iconSize - 6
                color: root.activeMirrorPid ? Theme.primary : Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: root.activeMirrorPid ? "Mirroring" : (filteredMonitors().length + " mon")
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
                name: root.activeMirrorPid ? "screen_share" : "monitor"
                size: Theme.iconSize - 6
                color: root.activeMirrorPid ? Theme.primary : Theme.surfaceVariantText
                anchors.horizontalCenter: parent.horizontalCenter
            }
            StyledText {
                text: root.activeMirrorPid ? "On" : (filteredMonitors().length + "m")
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
                        text: "Stop Mirror"
                        iconName: "stop"
                        onClicked: root.stopMirror()
                        enabled: root.activeMirrorPid !== ""
                        visible: root.activeMirrorPid !== ""
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

                // Monitor list
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
                            name: "monitor_off"
                            size: Theme.iconSize + 16
                            color: Theme.surfaceVariantText
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        StyledText {
                            text: "No displays found"
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        StyledText {
                            text: "Make sure niri is running"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }

                // Active mirror status / diagnostics
                StyledRect {
                    width: parent.width
                    height: statusColumnPopout.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: root.mirrorRunning ? Theme.primaryContainer : Theme.surfaceContainerHigh
                    visible: root.activeMirrorPid !== "" || root.lastMirrorError !== ""

                    Column {
                        id: statusColumnPopout
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        Row {
                            width: parent.width
                            spacing: Theme.spacingM

                            DankIcon {
                                name: root.mirrorRunning ? "screen_share" : "error"
                                size: Theme.iconSize
                                color: root.mirrorRunning ? (Theme.onPrimaryContainer || Theme.surfaceText) : (Theme.warning || Theme.error)
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - Theme.iconSize - stopMirrorButton.width - Theme.spacingM * 3
                                
                                StyledText {
                                    text: root.mirrorRunning ? "Mirror Active (PID " + root.activeMirrorPid + ")" : (root.lastMirrorError || "Mirror Not Running")
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Medium
                                    color: root.mirrorRunning ? (Theme.onPrimaryContainer || Theme.surfaceText) : Theme.surfaceText
                                }
                            }

                            Item {
                                width: 1
                                height: 1
                            }

                            DankButton {
                                id: stopMirrorButton
                                text: "Stop"
                                iconName: "stop"
                                onClicked: root.stopMirror()
                                visible: root.mirrorRunning
                                anchors.verticalCenter: parent.verticalCenter
                                
                                Component.onCompleted: {
                                    console.log("MonitorMirror: Popout Stop button created. mirrorRunning:", root.mirrorRunning, "visible:", visible)
                                }
                            }
                        }

                        StyledText {
                            text: root.mirrorRunning ? "A display is currently being mirrored." : "Attempted to start mirror. " + (root.lastMirrorError || "Unknown issue.")
                            font.pixelSize: Theme.fontSizeSmall
                            color: root.mirrorRunning ? (Theme.onPrimaryContainer || Theme.surfaceText) : Theme.surfaceVariantText
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
                    text: root.mirrorRunning ? "A mirror is already active. Stop it before starting a new one." : (currentFocusedOutput ? "Current display (" + currentFocusedOutput + ") is hidden. Select another display to mirror:" : "Select a display to mirror:")
                    font.pixelSize: Theme.fontSizeSmall
                    color: root.mirrorRunning ? Theme.warning : Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                    visible: filteredMonitors().length > 0 && !root.isLoading
                    bottomPadding: Theme.spacingS
                }

                // Monitor list
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
                            opacity: root.mirrorRunning ? 0.5 : 1.0
                            color: monitorArea.containsMouse && !root.mirrorRunning ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08) : Theme.withAlpha(Theme.surfaceContainerHighest, Theme.popupTransparency)
                            border.color: Theme.primary
                            border.width: 0

                            Row {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingM

                                DankIcon {
                                    name: "monitor"
                                    size: Theme.iconSize + 8
                                    color: root.mirrorRunning ? Theme.surfaceVariantText : Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.spacingXS

                                    StyledText {
                                        text: modelData
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Medium
                                        color: root.mirrorRunning ? Theme.surfaceVariantText : Theme.surfaceText
                                    }

                                    StyledText {
                                        text: root.mirrorRunning ? "Stop current mirror first" : "Click to mirror this output"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                DankIcon {
                                    name: root.mirrorRunning ? "block" : "arrow_forward"
                                    size: Theme.iconSize
                                    color: Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: monitorArea
                                anchors.fill: parent
                                enabled: !root.mirrorRunning
                                hoverEnabled: !root.mirrorRunning
                                cursorShape: root.mirrorRunning ? Qt.ForbiddenCursor : Qt.PointingHandCursor
                                onClicked: {
                                    if (!root.mirrorRunning) {
                                        root.startMirror(modelData)
                                    }
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
                            name: "monitor_off"
                            size: Theme.iconSize + 16
                            color: Theme.surfaceVariantText
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        StyledText {
                            text: "No displays found"
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        StyledText {
                            text: "Make sure niri is running"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }

                // Active mirror status / diagnostics
                StyledRect {
                    width: parent.width
                    height: statusColumnCCDetail.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: root.mirrorRunning ? Theme.primaryContainer : Theme.surfaceContainerHigh
                    visible: root.activeMirrorPid !== "" || root.lastMirrorError !== ""

                    Column {
                        id: statusColumnCCDetail
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        Row {
                            width: parent.width
                            spacing: Theme.spacingM

                            DankIcon {
                                name: root.mirrorRunning ? "screen_share" : "error"
                                size: Theme.iconSize
                                color: root.mirrorRunning ? (Theme.onPrimaryContainer || Theme.surfaceText) : (Theme.warning || Theme.error)
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - Theme.iconSize - stopMirrorButtonCC.width - Theme.spacingM * 3
                                
                                StyledText {
                                    text: root.mirrorRunning ? "Mirror Active (PID " + root.activeMirrorPid + ")" : (root.lastMirrorError || "Mirror Not Running")
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Medium
                                    color: root.mirrorRunning ? (Theme.onPrimaryContainer || Theme.surfaceText) : Theme.surfaceText
                                }
                            }

                            Item {
                                width: 1
                                height: 1
                            }

                            DankButton {
                                id: stopMirrorButtonCC
                                text: "Stop"
                                iconName: "stop"
                                onClicked: root.stopMirror()
                                visible: root.mirrorRunning
                                anchors.verticalCenter: parent.verticalCenter
                                
                                Component.onCompleted: {
                                    console.log("MonitorMirror: CC Detail Stop button created. mirrorRunning:", root.mirrorRunning, "visible:", visible)
                                }
                            }
                        }

                        StyledText {
                            text: root.mirrorRunning ? "A display is currently being mirrored." : "Attempted to start mirror. " + (root.lastMirrorError || "Unknown issue.")
                            font.pixelSize: Theme.fontSizeSmall
                            color: root.mirrorRunning ? (Theme.onPrimaryContainer || Theme.surfaceText) : Theme.surfaceVariantText
                            wrapMode: Text.WordWrap
                            leftPadding: Theme.iconSize + Theme.spacingM
                            width: parent.width - Theme.spacingM * 2
                        }
                    }
                }
            }
        }
        }
    }

    popoutWidth: 400
}
