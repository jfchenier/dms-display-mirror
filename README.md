# Display Mirror

A DankMaterialShell plugin that provides an easy interface to mirror niri displays using wl-mirror from the control center and bar.

![Display Mirror Screenshot](https://github.com/jfchenier/dms-display-mirror/blob/main/assets/screenshot.png)

## Features

- **Easy Display Selection** - Browse available displays directly from the Control Center
- **Auto-refresh** - Automatically detects monitor changes and updates the display list
- **One-Click Mirroring** - Start screen mirroring with a single click
- **Quick Stop** - Stop active mirror sessions instantly
- **Bar Widget** - Show mirroring status and control from the DankBar

## Installation

### Using DMS CLI

```bash
dms plugins install displayMirror
```

### Using DMS Settings

1. Open Settings → Plugins
2. Click "Browse"
3. Enable third party plugins
4. Install and enable Display Mirror
5. Add "Display Mirror" to your control center widgets

### Manual

```bash
git clone https://github.com/jfchenier/dms-display-mirror ~/.config/DankMaterialShell/plugins/dms-display-mirror
```

Then:
1. Open Settings → Plugins
2. Click "Scan"
3. Enable "Display Mirror"
4. Add to your DankBar or Control Center

## Requirements

- **DankMaterialShell** >= 0.1.0
- **wl-mirror** - Wayland screen mirroring utility
- **niri** compositor

### Installing wl-mirror

**Arch Linux:**
```bash
sudo pacman -S wl-mirror
```

**Fedora:**
```bash
sudo dnf install wl-mirror
```

**Ubuntu/Debian:**
```bash
sudo apt install wl-mirror
```

**From source:**
```bash
git clone https://github.com/Ferdi265/wl-mirror.git
cd wl-mirror
make
sudo make install
```

## Usage

### From Control Center

1. Open Control Center (default: Mod + I)
2. Navigate to the Display Mirror section
3. View list of available displays
4. Click "Mirror" next to the display you want to mirror
5. The mirrored window appears on your current display
6. Click "Stop Mirror" to end the session

### From DankBar Widget

1. Add Display Mirror widget to your bar
2. Click the widget icon to toggle the mirror list
3. Select display to mirror or stop active mirrors

### Tips

- Only one mirror session can be active at a time
- The display list refreshes automatically when monitors are added or removed
- Mirror windows can be moved, resized, and tiled like normal windows

## Examples

**Mirror your laptop display to an external monitor:**
1. Connect external monitor
2. Open Control Center → Display Mirror
3. Select your laptop's eDP-1 display
4. View the mirrored content on your external monitor

**Quick presentation setup:**
1. Connect projector
2. Use Display Mirror widget in bar
3. Click to see available displays
4. Mirror your main display to projector

## Files

- `plugin.json` - Plugin manifest
- `DankDisplayMirrorWidget.qml` - Main widget component for the bar
- `DanDisplayMirrorSettings.qml` - Settings UI
- `MirrorState.qml` - State management for mirror sessions
- `qmldir` - QML module definition
- `README.md` - This file

## Troubleshooting

**Display list is empty:**
- Ensure niri compositor is running
- Check that `niri msg outputs` works in terminal
- Verify you have multiple displays connected

**Mirror doesn't start:**
- Ensure wl-mirror is installed: `which wl-mirror`
- Check terminal for error messages
- Verify display names are correct

**Mirror window disappears:**
- This is normal when the target display is disconnected
- The plugin will automatically clean up the session

## Compatibility

- **Compositors**: Niri only
- **Distros**: Universal - works on any Linux distribution
- **Dependencies**: wl-mirror, niri

## Technical Details

- **Type**: Control Center plugin with optional bar widget
- **Language**: QML (Qt Modeling Language)
- **Backend**: Uses `wl-mirror` and `niri msg` commands

## Contributing

Found a bug or want to add features? Open an issue or submit a pull request on [GitHub](https://github.com/jfchenier/dms-display-mirror)!

## License

MIT License - See LICENSE file for details

## Author

Created by jfchenier for the DankMaterialShell community

## Links

- [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell)
- [Plugin Registry](https://plugins.danklinux.com/)
- [wl-mirror](https://github.com/Ferdi265/wl-mirror)

