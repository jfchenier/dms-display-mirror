import QtQuick

// Singleton to share mirror state across all widget instances
pragma Singleton

QtObject {
    property string activeMirrorPid: ""
    property bool mirrorRunning: false
}
