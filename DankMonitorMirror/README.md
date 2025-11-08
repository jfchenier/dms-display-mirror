# Dank Display Mirror

A DankMaterialShell Control Center plugin that provides an easy interface to mirror displays using wl-mirror. This plugin replaces the need for command-line tools like fuzzel by integrating display selection directly into the Control Center.

## Features

- 🖥️ **Easy Display Selection** - Browse available displays from the Control Center
- 🔄 **Auto-refresh** - Automatically detects monitor changes
- 🎯 **One-Click Mirroring** - Start mirroring with a single click
- 🛑 **Quick Stop** - Stop active mirrors instantly
- ⚙️ **Configurable** - Adjust refresh intervals and auto-detection settings

## Requirements

- **DankMaterialShell** - The desktop environment this plugin is designed for
- **wl-mirror** - The Wayland screen mirroring utility
- **niri** - The compositor (must be running)
- **Wayland** - Session type

### Installing wl-mirror

**Arch Linux:**
```bash
sudo pacman -S wl-mirror
```

**Fedora:**
```bash
sudo dnf install wl-mirror
```

**From source:**
```bash
git clone https://github.com/Ferdi265/wl-mirror.git
cd wl-mirror
make
sudo make install
```

## Installation

1. Clone or copy this plugin to your DankMaterialShell plugins directory:
   ```bash
   mkdir -p ~/.config/DankMaterialShell/plugins
   cp -r DankMonitorMirror ~/.config/DankMaterialShell/plugins/
   ```

2. Restart DankMaterialShell:
   ```bash
   dms restart
   ```

3. Enable the plugin:
   - Open Settings → Plugins
   - Click "Scan for Plugins"
   - Toggle "Dank Display Mirror" on

4. The plugin will now appear in your Control Center

## Usage

### Starting a Mirror

1. Open the Control Center (typically by clicking the system tray or using a keyboard shortcut)
2. Find the "Display Mirror" tile
3. Click on it to open the monitor selection panel
4. Click on any monitor from the list to start mirroring it
5. A new window will open displaying the mirrored content

### Stopping a Mirror

1. Open the Control Center
2. Click on the "Display Mirror" tile
3. Click the "Stop Mirror" button

### Settings

Access plugin settings from Settings → Plugins → Dank Display Mirror:

- **Auto-refresh Display List** - Automatically detect display changes
- **Refresh Interval** - How often to check for new monitors (in seconds)

## How It Works

This plugin replaces the manual command:
```bash
wl-mirror $(niri msg outputs | grep '^Output' | cut -d'(' -f 2 | cut -d')' -f 1 | fuzzel --dmenu --prompt 'src? ')
```

With a visual interface that:
1. Queries `niri msg outputs` to get the list of available displays
2. Displays them in a user-friendly list in the Control Center
3. Executes `wl-mirror <output-name>` when you select a monitor
4. Tracks the mirror process for easy stopping

## Troubleshooting

### No displays appear
- Ensure niri is running: `niri msg outputs`
- Check that you're in a Wayland session
- Verify niri is properly configured

### Mirror won't start
- Ensure wl-mirror is installed: `which wl-mirror`
- Check wl-mirror works manually: `wl-mirror <output-name>`
- Check the logs: `dms kill && dms run`

### Mirror doesn't stop
- You can manually stop all mirrors: `killall wl-mirror`
- Or find and kill specific processes: `ps aux | grep wl-mirror`

## Manual Commands

For reference, here are the equivalent manual commands:

**List outputs:**
```bash
niri msg outputs
```

**Start mirroring:**
```bash
wl-mirror <output-name>
```

**Stop all mirrors:**
```bash
killall wl-mirror
```

## Development

This plugin is built using the DankMaterialShell plugin framework with:
- QML for the UI components
- Quickshell.Io.Process for command execution
- Control Center widget integration

### File Structure
```
DankMonitorMirror/
├── plugin.json                      # Plugin manifest
├── DankMonitorMirrorWidget.qml      # Main widget component
├── DankMonitorMirrorSettings.qml    # Settings interface
└── README.md                        # This file
```

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

This plugin follows the same license as DankMaterialShell.

## Author

Avenge Media

## Version

1.0.0
