import QtQuick

// Singleton to share mirror state across all widget instances
pragma Singleton

QtObject {
    id: root
    
    // Store active mirrors as { outputName: pid }
    property var activeMirrors: ({})
    
    // Helper to check if any mirrors are running
    property bool hasActiveMirrors: Object.keys(activeMirrors).length > 0
    
    // Helper to get count of active mirrors
    property int activeMirrorCount: Object.keys(activeMirrors).length
    
    // Signal when mirrors change
    signal mirrorsChanged()
    
    onActiveMirrorsChanged: {
        console.log("MirrorState: activeMirrors changed, count:", Object.keys(activeMirrors).length)
        mirrorsChanged()
    }
}
