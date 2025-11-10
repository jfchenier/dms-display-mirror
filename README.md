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
2. Click the pen (edit) button to customize widgets
3. Add the Display Mirror widget to the Control Center
4. Navigate to the Display Mirror section
5. View list of available displays
6. Click "Mirror" next to the display you want to mirror
7. The mirrored window appears on your current display
8. Click "Stop Mirror" to end the session

### From DankBar Widget

1. Add Display Mirror widget to your bar
2. Click the widget icon to toggle the mirror list
3. Select display to mirror or stop active mirrors

## Compatibility

- **Compositors**: Niri only
- **Distros**: Universal - works on any Linux distribution
- **Dependencies**: wl-mirror, niri

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

