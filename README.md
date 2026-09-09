# MpvPaper Plugin

![MpvPaper settings](screenshot.png)

A DMS 1.5 composite plugin for video wallpapers. One installation provides both the background daemon and a DankBar widget.

## Features

- One shared, deduplicated video library with independent wallpaper selection per monitor
- Smooth wallpaper switching through persistent mpv IPC with a guarded fade transition
- Included DankBar widget for browsing and switching wallpapers
- Hardware decoding with `auto`, `nvdec`, `vaapi`, and `vdpau` modes
- Configurable playback-process restart interval
- Configurable lock-screen behavior: stop the player or pause playback in place
- Dynamic palette extraction using runtime-only temporary frames
- English and Simplified Chinese settings

## Requirements

- DMS 1.5.0 or later
- [`mpvpaper`](https://github.com/GhostNaN/mpvpaper)
- `ffmpeg` for video thumbnails and dynamic palette extraction

On Arch Linux:

```bash
sudo pacman -S ffmpeg
yay -S mpvpaper
```

## Usage

1. Install and enable **MpvPaper Plugin** in DMS.
2. Open the plugin settings to add videos, select a monitor, and configure playback.
3. In the DankBar layout settings, add **MpvPaper Plugin** to use the included widget.

The settings page and DankBar widget share one global video library. Each monitor stores only its current wallpaper selection; **All** applies the next selection to every connected monitor.

## License

MIT
