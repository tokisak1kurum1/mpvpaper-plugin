import QtCore
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import qs.Modals.FileBrowser

PluginComponent {
    id: root
    pluginId: "mpvpaper"

    Component.onCompleted: {
        MpvPaperI18n.language = pluginData.language || "en"
    }

    property var monitors: Quickshell.screens.map(screen => screen.name)
    property string selectedMonitor: {
        if (parentScreen && parentScreen.name) return parentScreen.name
        return monitors.length > 0 ? monitors[0] : ""
    }
    property int currentPage: 0
    property int itemsPerPage: 8  // 2x4 grid
    property int totalPages: Math.max(1, Math.ceil(getPlaylist().length / itemsPerPage))
    property int refreshTrigger: 0
    property int gridIndex: 0
    property bool enableAnimation: false
    property var fileBrowserParentPopout: null
    readonly property bool coreAvailable: {
        PluginService.loadedPlugins
        return PluginService.isPluginLoaded("mpvpaper")
    }

    Connections {
        target: pluginService
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === "mpvpaper") root.refreshTrigger++
        }
    }

    onPluginDataChanged: {
        MpvPaperI18n.language = pluginData.language || "en"
        refreshTrigger++
    }

    onRefreshTriggerChanged: {
        const currentPath = getCurrentVideoPath()
        const playlist = getPlaylist()
        const startIndex = currentPage * itemsPerPage
        const pagePlaylist = playlist.slice(startIndex, Math.min(startIndex + itemsPerPage, playlist.length))
        const idx = pagePlaylist.indexOf(currentPath)
        if (idx !== -1) gridIndex = idx
    }

    function getPlaylist() {
        if (!pluginService) return []
        const playlists = pluginService.loadPluginData("mpvpaper", "monitorPlaylists", {})
        var list = playlists[selectedMonitor]
        return Array.isArray(list) ? list : []
    }

    function getCurrentVideoPath() {
        if (!pluginService) return ""
        const monitorVideos = pluginService.loadPluginData("mpvpaper", "monitorVideos", {})
        return monitorVideos[selectedMonitor] || ""
    }

    function setCurrentVideo(videoPath) {
        if (!pluginService || !coreAvailable) return
        
        const playlists = pluginService.loadPluginData("mpvpaper", "monitorPlaylists", {})
        var playlist = playlists[selectedMonitor]
        
        if (playlist && Array.isArray(playlist)) {
            var videoIndex = playlist.indexOf(videoPath)
            if (videoIndex !== -1) {
                // 保存全局索引
                const indices = pluginService.loadPluginData("mpvpaper", "playlistIndices", {})
                indices[selectedMonitor] = videoIndex
                pluginService.savePluginData("mpvpaper", "playlistIndices", indices)
                
                // 计算当前页面的相对索引并同步 GridView
                const startIndex = root.currentPage * root.itemsPerPage
                const relativeIndex = videoIndex - startIndex
                if (relativeIndex >= 0 && relativeIndex < root.itemsPerPage) {
                    root.gridIndex = relativeIndex
                }
            }
        }
        
        const monitorVideos = pluginService.loadPluginData("mpvpaper", "monitorVideos", {})
        monitorVideos[selectedMonitor] = videoPath
        pluginService.savePluginData("mpvpaper", "monitorVideos", monitorVideos)
        
        root.refreshTrigger++
    }

    function openSystemFilePicker() {
        systemFilePickerProcess.selectedFile = ""
        systemFilePickerProcess.running = true
    }

    function addToPlaylist(videoPath) {
        if (!pluginService || !coreAvailable) return
        const playlists = pluginService.loadPluginData("mpvpaper", "monitorPlaylists", {})
        if (!playlists[selectedMonitor]) playlists[selectedMonitor] = []
        if (playlists[selectedMonitor].indexOf(videoPath) !== -1) return
        playlists[selectedMonitor].push(videoPath)
        pluginService.savePluginData("mpvpaper", "monitorPlaylists", playlists)
        const indices = pluginService.loadPluginData("mpvpaper", "playlistIndices", {})
        indices[selectedMonitor] = playlists[selectedMonitor].indexOf(videoPath)
        pluginService.savePluginData("mpvpaper", "playlistIndices", indices)
        const monitorVideos = pluginService.loadPluginData("mpvpaper", "monitorVideos", {})
        monitorVideos[selectedMonitor] = videoPath
        pluginService.savePluginData("mpvpaper", "monitorVideos", monitorVideos)
        refreshTrigger++
    }

    Process {
        id: systemFilePickerProcess
        property string selectedFile: ""
        command: ["bash", "-c", `
            if command -v zenity >/dev/null 2>&1; then
                zenity --file-selection --multiple --separator=$'\n' --title="${MpvPaperI18n.tr("Select Video Files", "mpvpaper")}" --file-filter="${MpvPaperI18n.tr("Video Files", "mpvpaper")} | *.mp4 *.mkv *.webm *.avi *.mov *.flv *.wmv *.m4v" --file-filter="${MpvPaperI18n.tr("All Files", "mpvpaper")} | *"
            elif command -v kdialog >/dev/null 2>&1; then
                kdialog --getopenfilename ~ "*.mp4 *.mkv *.webm *.avi *.mov *.flv *.wmv *.m4v|${MpvPaperI18n.tr("Video Files", "mpvpaper")}" --multiple --separate-output
            else
                echo "ERROR: No file picker available"
                exit 1
            fi
        `]
        stdout: SplitParser { onRead: (data) => { systemFilePickerProcess.selectedFile += data + "\n" } }
        onExited: (code) => {
            const trimmed = selectedFile.trim()
            if (code === 0 && trimmed !== "") {
                const files = trimmed.split('\n').map(f => f.trim()).filter(f => f !== "")
                files.forEach(f => addToPlaylist(f))
            } else if (trimmed.includes("ERROR")) {
                console.log("MpvPaper Widget: System file picker not available, using DMS file browser")
                videoFileBrowser.open()
            }
            selectedFile = ""
        }
    }

    FileBrowserSurfaceModal {
        id: videoFileBrowser
        parentPopout: root.fileBrowserParentPopout
        browserTitle: MpvPaperI18n.tr("Select Video Files", "mpvpaper")
        browserIcon: "movie"
        browserType: "mpvpaper-video"
        showHiddenFiles: true
        fileExtensions: ["*.mp4", "*.mkv", "*.webm", "*.avi", "*.mov", "*.flv", "*.wmv", "*.m4v"]

        onFileSelected: (videoPath) => {
            root.addToPlaylist(videoPath)
            close()
        }
    }

    horizontalBarPill: Component { DankIcon { name: "movie"; size: root.iconSize; color: Theme.primary } }
    verticalBarPill: Component { DankIcon { name: "movie"; size: root.iconSize; color: Theme.primary } }

    popoutContent: Component {
        PopoutComponent {
            id: popout
            Component.onCompleted: root.fileBrowserParentPopout = popout
            Component.onDestruction: {
                if (root.fileBrowserParentPopout === popout)
                    root.fileBrowserParentPopout = null
            }
            headerText: MpvPaperI18n.tr("Video Wallpaper", "mpvpaper")
            detailsText: {
                if (!root.coreAvailable) return MpvPaperI18n.tr("MpvPaper Plugin is not loaded", "mpvpaper")
                root.refreshTrigger
                const playlist = root.getPlaylist()
                if (playlist.length === 0) return MpvPaperI18n.tr("No Wallpapers", "mpvpaper")
                return MpvPaperI18n.tr("%1 Wallpapers • Page %2/%3", "mpvpaper").arg(playlist.length).arg(root.currentPage + 1).arg(root.totalPages)
            }
            showCloseButton: true

            Item {
                width: parent.width
                implicitHeight: root.popoutHeight - popout.headerHeight - popout.detailsHeight - Theme.spacingXL

                Column {
                    anchors.fill: parent
                    spacing: Theme.spacingM
                    visible: root.coreAvailable

                    // Monitor selector
                    Item {
                        width: parent.width
                        height: root.monitors.length > 1 ? 40 : 0
                        visible: root.monitors.length > 1
                        Row {
                            anchors.fill: parent; anchors.margins: Theme.spacingM
                            spacing: Theme.spacingM
                            StyledText { text: MpvPaperI18n.tr("Monitor", "mpvpaper"); font.pixelSize: Theme.fontSizeSmall; width: 60; anchors.verticalCenter: parent.verticalCenter }
                            DankDropdown {
                                width: parent.width - 60 - Theme.spacingM * 2; height: 32; anchors.verticalCenter: parent.verticalCenter
                                options: root.monitors; currentValue: root.selectedMonitor || MpvPaperI18n.tr("No Monitors", "mpvpaper"); compactMode: true
                                onValueChanged: (value) => { root.selectedMonitor = value; root.currentPage = 0; root.gridIndex = 0 }
                            }
                        }
                    }

                    // Video grid
                    Item {
                        id: gridContainer
                        width: parent.width
                        height: gridContainer.cellHeight * 2
                        property real cellWidth: Math.floor(width / 4)
                        property real cellHeight: cellWidth * 9 / 16

                        GridView {
                            id: videoGrid
                            width: cellWidth * 4
                            height: cellHeight * 2
                            anchors.centerIn: parent
                            cellWidth: gridContainer.cellWidth
                            cellHeight: gridContainer.cellHeight
                            clip: true
                            interactive: false
                            highlightFollowsCurrentItem: true
                            highlightMoveDuration: root.enableAnimation ? Theme.shortDuration : 0
                            currentIndex: root.gridIndex
                            highlight: Item { z: 1000; Rectangle { anchors.fill: parent; anchors.margins: Theme.spacingXS; color: "transparent"; border.width: 3; border.color: Theme.primary; radius: Theme.cornerRadius } }

                            model: {
                                root.refreshTrigger
                                const playlist = root.getPlaylist()
                                const startIndex = root.currentPage * root.itemsPerPage
                                return playlist.slice(startIndex, startIndex + root.itemsPerPage)
                            }

                            onCountChanged: if (count > 0) currentIndex = Math.min(root.gridIndex, count - 1)
                            onCurrentIndexChanged: root.gridIndex = currentIndex

                            delegate: Item {
                                width: videoGrid.cellWidth
                                height: videoGrid.cellHeight
                                property bool isSelected: { root.refreshTrigger; return root.getCurrentVideoPath() === modelData }

                                Rectangle {
                                    anchors.fill: parent; anchors.margins: Theme.spacingXS
                                    color: Theme.withAlpha(Theme.surfaceContainerHighest, Theme.popupTransparency)
                                    radius: Theme.cornerRadius; clip: true

                                    Rectangle {
                                        anchors.fill: parent; radius: parent.radius; color: isSelected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : "transparent"
                                        Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                                    }

                                    Rectangle {
                                        anchors.fill: parent; radius: parent.radius; color: "transparent"; border.width: isSelected ? 3 : 0; border.color: Theme.primary
                                        Behavior on border.width { NumberAnimation { duration: Theme.shortDuration } }
                                    }

                                    Rectangle { id: maskRect; width: thumbnailImage.width; height: thumbnailImage.height; radius: Theme.cornerRadius; visible: false; layer.enabled: true }

                                    Image {
                                        id: thumbnailImage
                                        anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: true
                                        layer.enabled: true; layer.effect: MultiEffect { maskEnabled: true; maskSource: maskRect }
                                        property string videoPath: modelData
                                        Component.onCompleted: generateThumbnail()
                                        function generateThumbnail() {
                                            const cacheDir = StandardPaths.writableLocation(StandardPaths.GenericCacheLocation).toString().replace("file://", "") + "/DankMaterialShell/mpvpaper_thumbnails"
                                            const hash = videoPath.split('').reduce((a, b) => { a = ((a << 5) - a) + b.charCodeAt(0); return a & a }, 0)
                                            const thumbPath = cacheDir + "/" + Math.abs(hash) + "_thumb.jpg"
                                            thumbCheck.command = ["test", "-f", thumbPath]; thumbCheck.thumbPath = thumbPath; thumbCheck.running = true
                                        }
                                        Process { id: thumbCheck; property string thumbPath: ""; onExited: (code) => { if (code === 0) thumbnailImage.source = "file://" + thumbPath; else thumbGen.running = true } }
                                        Process {
                                            id: thumbGen
                                            command: [
                                                "bash", "-c",
                                                'mkdir -p -- "$1" && ffmpeg -loglevel error -i "$2" -ss 00:00:01 -vframes 1 -vf "scale=320:180:force_original_aspect_ratio=increase,crop=320:180" -q:v 3 "$3" -y',
                                                "mpvpaper-thumbnail", StandardPaths.writableLocation(StandardPaths.GenericCacheLocation).toString().replace("file://", "") + "/DankMaterialShell/mpvpaper_thumbnails", modelData, thumbCheck.thumbPath
                                            ]
                                            onExited: (code) => { if (code === 0) thumbnailImage.source = "file://" + thumbCheck.thumbPath }
                                        }
                                    }
                                    DankIcon { anchors.centerIn: parent; name: "movie"; size: 24; color: Theme.primary; visible: thumbnailImage.status !== Image.Ready }
                                    MouseArea {
                                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            videoGrid.currentIndex = index
                                            if (modelData) root.setCurrentVideo(modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Bottom Navigation
                    RowLayout {
                        width: parent.width; height: 40; spacing: Theme.spacingM
                        Item { width: Theme.spacingS; height: 1 }
                        DankActionButton { iconName: "skip_previous"; iconSize: 18; buttonSize: 32; enabled: root.currentPage > 0; opacity: enabled ? 0.8 : 0.2; onClicked: { root.currentPage--; root.gridIndex = 0 } }
                        StyledText { text: MpvPaperI18n.tr("Page %1/%2", "mpvpaper").arg(root.currentPage + 1).arg(root.totalPages); font.pixelSize: 12; color: Theme.surfaceText; opacity: 0.7; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        DankActionButton { iconName: "skip_next"; iconSize: 18; buttonSize: 32; enabled: root.currentPage < root.totalPages - 1; opacity: enabled ? 0.8 : 0.2; onClicked: { root.currentPage++; root.gridIndex = 0 } }
                        DankActionButton { iconName: "folder_open"; iconSize: 18; buttonSize: 32; opacity: 0.7; onClicked: root.openSystemFilePicker() }
                        Item { width: Theme.spacingS; height: 1 }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - Theme.spacingXL * 2, 420)
                    spacing: Theme.spacingM
                    visible: !root.coreAvailable

                    DankIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: "warning"
                        size: 40
                        color: Theme.warning
                    }
                    StyledText {
                        width: parent.width
                        text: MpvPaperI18n.tr("Install and enable MpvPaper Plugin before using this widget.", "mpvpaper")
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        color: Theme.surfaceText
                    }
                }
            }
        }
    }

    popoutWidth: 600
    popoutHeight: 360
}
