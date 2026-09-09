# MpvPaper Plugin

![MpvPaper settings](screenshot.png)

Video wallpaper plugin for [Dank Material Shell](https://github.com/AvengeMedia/DankMaterialShell). It uses `mpvpaper` for playback and includes both a settings interface and a DankBar wallpaper switcher.

## Features

- Smooth wallpaper switching without restarting `mpvpaper` for every video change
- Shared video library with independent wallpaper selection per monitor, or one wallpaper across all monitors
- DankBar widget for browsing and switching wallpapers
- Hardware decoding with `auto`, `nvdec`, `vaapi`, and `vdpau`, plus fill mode and volume controls
- Configurable lock-screen behavior: stop the player or pause and resume from the current position
- Configurable periodic `mpvpaper` restart for long-running sessions
- Dynamic DMS colors generated from the active video wallpaper
- English and Simplified Chinese settings

## Installation

MpvPaper Plugin is available in the DMS Plugin Directory.

1. Open **DMS Settings → Plugins → Browse**.
2. Search for **MpvPaper Plugin**.
3. Install and enable the plugin.

Install the required system packages first. On Arch Linux:

```bash
sudo pacman -S ffmpeg
yay -S mpvpaper
```

## Usage

1. Open the plugin settings and add video files or a folder.
2. Select a monitor and choose its wallpaper, or enable the same wallpaper for all monitors.
3. Configure playback, lock-screen behavior, and optional advanced MPV settings as needed.
4. Add **MpvPaper Plugin** to the DankBar layout if you want quick wallpaper switching from the bar.

The settings page and DankBar widget use the same video library. Changing a wallpaper only changes the current selection; adding videos does not automatically replace the active wallpaper.

## Requirements

- DMS 1.5.0 or later
- [`mpvpaper`](https://github.com/GhostNaN/mpvpaper)
- `ffmpeg` for thumbnails and dynamic color extraction

## License

MIT
