import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "displayMirror"

    StyledText {
        width: parent.width
    text: "Display Mirror Settings"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
    text: "Configure display mirroring behavior"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledRect {
        width: parent.width
        height: refreshColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: refreshColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "Monitor Detection"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            ToggleSetting {
                settingKey: "autoRefresh"
                label: "Auto-refresh Monitor List"
                description: "Automatically update the list of available monitors (disabled by default to avoid visual glitches)"
                defaultValue: false
            }

            StringSetting {
                settingKey: "refreshInterval"
                label: "Refresh Interval (seconds)"
                description: "How often to check for monitor changes"
                placeholder: "30"
                defaultValue: "30"
            }
        }
    }

    StyledRect {
        width: parent.width
        height: infoColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surface

        Column {
            id: infoColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            Row {
                spacing: Theme.spacingM

                DankIcon {
                    name: "info"
                    size: Theme.iconSize
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: "About Display Mirror"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            StyledText {
                text: "This plugin allows you to mirror displays using wl-mirror. It's particularly useful for screen sharing or duplicating your screen.\n\nRequirements:\n• wl-mirror (install via package manager)\n• niri compositor\n• Wayland session\n\nUsage:\n1. Open Control Center\n2. Click the Display Mirror tile\n3. Select the display you want to mirror\n4. A new window will open showing the mirrored content\n5. Click 'Stop Mirror' to end the session"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
                width: parent.width
                lineHeight: 1.4
            }
        }
    }

    StyledRect {
        width: parent.width
        height: commandsColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: commandsColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            Row {
                spacing: Theme.spacingM

                DankIcon {
                    name: "terminal"
                    size: Theme.iconSize
                    color: Theme.warning
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: "Manual Commands"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            StyledText {
                text: "To manually control wl-mirror:\n\nList outputs:\n  niri msg outputs\n\nStart mirroring:\n  wl-mirror <output-name>\n\nStop all mirrors:\n  killall wl-mirror"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
                width: parent.width
                lineHeight: 1.4
                font.family: "monospace"
            }
        }
    }
}
