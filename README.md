# MpvPaper Plugin

This is a desktop video wallpaper plugin built for DMS, based on mpvpaper.

## Core Features
* Multi-monitor support: Independent video playlists can be set for different screens.
* GPU hardware acceleration: Built-in support for multiple hardware decoding modes such as nvdec, vaapi, and vdpau, significantly reducing CPU usage.
* Memory leak protection: Supports customizable scheduled auto-restarts for the playback process to ensure the system remains smooth over long periods of operation.
* Idle resource recovery: The plugin hooks into the DMS lock screen state. When the system is locked, the plugin automatically stops rendering to save power.

## System Dependencies
**Required**: This plugin requires `mpvpaper` to be installed on your system.
* Arch Linux: `sudo pacman -S mpvpaper`

## Usage
After installation, go directly to "System Settings -> MpvPaper Plugin" to manage the video library, adjust volume, and set the tiling mode.

## License
MIT