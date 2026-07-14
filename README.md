# MpvPaper Plugin

![MpvPaper settings](screenshot.png)

A DMS 1.5 composite plugin for video wallpapers. One installation provides both the background daemon and a DankBar widget.

## Features

- Independent video playlists for multiple monitors
- Included DankBar widget for browsing and switching wallpapers
- Hardware decoding with `auto`, `nvdec`, `vaapi`, and `vdpau` modes
- Automatic playback-process restart with a configurable interval
- Automatic playback pause while the DMS lock screen is active
- English and Simplified Chinese settings

## Requirements

- DMS 1.5.0 or later
- [`mpvpaper`](https://github.com/GhostNaN/mpvpaper)
- `ffmpeg` for video thumbnails

On Arch Linux:

```bash
sudo pacman -S ffmpeg
yay -S mpvpaper
```

## Usage

1. Install and enable **MpvPaper Plugin** in DMS.
2. Open the plugin settings to add videos, select a monitor, and configure playback.
3. In the DankBar layout settings, add **MpvPaper Plugin** to use the included widget.

The daemon and DankBar widget share the same playlists and settings.

## License

MIT
