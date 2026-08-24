import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Services
import qs.Modules.Plugins
import qs.Modals.FileBrowser

PluginSettings {
    id: root
    pluginId: "mpvpaper"

    property string language: "en"

    function syncLanguage() {
        language = loadValue("language", "en")
        MpvPaperI18n.language = language
    }

    Component.onCompleted: syncLanguage()
    onPluginServiceChanged: syncLanguage()

    property var monitors: Quickshell.screens.map(screen => screen.name)
    property string selectedMonitor: monitors.length > 0 ? monitors[0] : ""
    property int playlistVersion: 0
    property int currentVideoRefresh: 0
    property bool sameOnAllMonitors: pluginData.sameOnAllMonitors || false

    Connections {
        target: pluginService
        enabled: pluginService !== null
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === pluginId) {
                root.syncLanguage()
                currentVideoRefresh++
            }
        }
    }

    onSelectedMonitorChanged: {
        playlistVersion++
    }

    StyledText {
        text: MpvPaperI18n.tr("MpvPaper Plugin", "mpvpaper")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
    }

    StyledText {
        text: MpvPaperI18n.tr("Video wallpaper using mpvpaper", "mpvpaper")
        font.pixelSize: Theme.fontSizeMedium
        opacity: 0.7
        wrapMode: Text.Wrap
    }

    Row {
        width: parent.width
        spacing: Theme.spacingM

        StyledText {
            text: MpvPaperI18n.tr("Language", "mpvpaper")
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            width: 180
            anchors.verticalCenter: parent.verticalCenter
        }

        DankDropdown {
            width: parent.width - 180 - Theme.spacingM
            options: [MpvPaperI18n.tr("English", "mpvpaper"), MpvPaperI18n.tr("Simplified Chinese", "mpvpaper")]
            currentValue: root.language === "zh_CN" ? MpvPaperI18n.tr("Simplified Chinese", "mpvpaper") : MpvPaperI18n.tr("English", "mpvpaper")
            compactMode: true
            onValueChanged: (value) => {
                const nextLanguage = value === MpvPaperI18n.tr("Simplified Chinese", "mpvpaper") ? "zh_CN" : "en"
                if (nextLanguage === root.language) return
                root.language = nextLanguage
                MpvPaperI18n.language = nextLanguage
                root.saveValue("language", nextLanguage)
            }
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outlineStrong
    }

    Row {
        width: parent.width
        spacing: Theme.spacingM
        visible: root.monitors.length > 1

        StyledText {
            text: MpvPaperI18n.tr("Same on all monitors", "mpvpaper")
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            width: 180
            anchors.verticalCenter: parent.verticalCenter
        }
        
        Switch {
            id: sameOnAllMonitorsSwitch
            anchors.verticalCenter: parent.verticalCenter
            checked: root.sameOnAllMonitors
            
            onCheckedChanged: {
                if (checked === root.sameOnAllMonitors) return
                root.sameOnAllMonitors = checked
                if (pluginService) {
                    pluginService.savePluginData("mpvpaper", "sameOnAllMonitors", checked)
                }
            }
        }
    }
    
    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outlineStrong
        visible: root.monitors.length > 1
    }

    Row {
        width: parent.width
        spacing: Theme.spacingM
        visible: root.monitors.length > 1

        StyledText {
            text: MpvPaperI18n.tr("Monitor", "mpvpaper")
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            width: 180
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.sameOnAllMonitors ? 0.4 : 1.0
            Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
        }

        DankDropdown {
            width: parent.width - 180 - Theme.spacingM
            visible: !root.sameOnAllMonitors
            options: root.monitors
            currentValue: root.selectedMonitor || MpvPaperI18n.tr("No Monitors", "mpvpaper")
            enabled: root.monitors.length > 1
            compactMode: true

            onValueChanged: (value) => {
                root.selectedMonitor = value
            }
        }

        Rectangle {
            width: parent.width - 180 - Theme.spacingM
            height: 36 // standard compact dropdown height
            visible: root.sameOnAllMonitors
            color: Theme.withAlpha(Theme.surfaceContainer, Theme.popupTransparency)
            border.width: 1
            border.color: Theme.outlineHeavy
            radius: Theme.cornerRadius
            opacity: 0.4
            
            StyledText {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingM
                anchors.rightMargin: Theme.spacingM
                text: MpvPaperI18n.tr("All Monitors", "mpvpaper")
                font.pixelSize: Theme.fontSizeMedium
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }
    }

    Item {
        width: parent.width
        height: Theme.spacingM
    }

    // Grid layout for video thumbnails (Moved back above buttons)
    GridView {
        id: videoGridView
        width: parent.width
        cellWidth: width / 3  // 3 columns
        cellHeight: cellWidth * 9 / 16  // 16:9 ratio
        height: Math.max(cellHeight, Math.ceil(getPlaylist().length / 3) * cellHeight)
        clip: true
        interactive: false
        highlightFollowsCurrentItem: true
        highlightMoveDuration: Theme.shortDuration

        highlight: Item {
            z: 1000
            Rectangle {
                anchors.fill: parent
                anchors.margins: Theme.spacingXS
                color: "transparent"
                border.width: 3
                border.color: Theme.primary
                radius: Theme.cornerRadius
            }
        }

        model: {
            var v = playlistVersion
            return getPlaylist()
        }

        onModelChanged: {
            // Update currentIndex when model changes
            const currentPath = getCurrentVideoPath()
            const playlist = getPlaylist()
            const idx = playlist.indexOf(currentPath)
            if (idx !== -1) {
                currentIndex = idx
            }
        }

        delegate: Item {
            width: videoGridView.cellWidth
            height: videoGridView.cellHeight

            required property string modelData
            required property int index
            
            property bool isSelected: videoGridView.currentIndex === index

            Rectangle {
                id: videoCard
                anchors.fill: parent
                anchors.margins: Theme.spacingXS
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.surfaceContainerHighest, Theme.popupTransparency)
                clip: true

                Rectangle {
                    id: maskRect
                    width: thumbnailImage.width
                    height: thumbnailImage.height
                    radius: Theme.cornerRadius
                    visible: false
                    layer.enabled: true
                }

                Rectangle {
                    anchors.fill: parent
                    color: isSelected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : "transparent"
                    radius: parent.radius

                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.shortDuration
                            easing.type: Theme.standardEasing
                        }
                    }
                }

                // Blue border for selected video
                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    border.width: isSelected ? 3 : 0
                    border.color: Theme.primary
                    radius: parent.radius

                    Behavior on border.width {
                        NumberAnimation {
                            duration: Theme.shortDuration
                            easing.type: Theme.standardEasing
                        }
                    }
                }

                Image {
                    id: thumbnailImage
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                        maskSource: maskRect
                    }

                    property string videoPath: modelData
                    property string thumbnailPath: ""

                    Component.onCompleted: {
                        generateThumbnail()
                    }

                    function generateThumbnail() {
                        const cacheHome = StandardPaths.writableLocation(StandardPaths.GenericCacheLocation).toString().replace("file://", "")
                        const cacheDir = cacheHome + "/DankMaterialShell/mpvpaper_thumbnails"
                        
                        const hash = videoPath.split('').reduce((a, b) => {
                            a = ((a << 5) - a) + b.charCodeAt(0)
                            return a & a
                        }, 0)
                        
                        thumbnailPath = cacheDir + "/" + Math.abs(hash) + "_thumb.jpg"
                        
                        playlistThumbCheckProcess.thumbnailPath = thumbnailPath
                        playlistThumbCheckProcess.videoPath = videoPath
                        playlistThumbCheckProcess.cacheDir = cacheDir
                        playlistThumbCheckProcess.command = ["test", "-f", thumbnailPath]
                        playlistThumbCheckProcess.running = true
                    }

                    Process {
                        id: playlistThumbCheckProcess
                        property string thumbnailPath: ""
                        property string videoPath: ""
                        property string cacheDir: ""

                        onExited: (code) => {
                            if (code === 0) {
                                thumbnailImage.source = "file://" + thumbnailPath
                            } else {
                                playlistThumbGenProcess.thumbnailPath = thumbnailPath
                                playlistThumbGenProcess.videoPath = videoPath
                                playlistThumbGenProcess.cacheDir = cacheDir
                                // Pass paths as positional parameters so quotes and shell
                                // metacharacters in valid filenames are never evaluated.
                                playlistThumbGenProcess.command = ["bash", "-c",
                                    'mkdir -p -- "$1" && ffmpeg -loglevel error -i "$2" -ss 00:00:01 -vframes 1 -vf "scale=320:180:force_original_aspect_ratio=increase,crop=320:180" -q:v 3 "$3" -y',
                                    "mpvpaper-thumbnail", cacheDir, videoPath, thumbnailPath
                                ]
                                playlistThumbGenProcess.running = true
                            }
                        }
                    }

                    Process {
                        id: playlistThumbGenProcess
                        property string thumbnailPath: ""
                        property string videoPath: ""
                        property string cacheDir: ""

                        onExited: (code) => {
                            if (code === 0) {
                                thumbnailImage.source = "file://" + thumbnailPath
                            } else {
                                console.warn("MpvPaper Settings: Failed to generate thumbnail for", videoPath, "exit code:", code)
                            }
                        }
                    }
                }

                // Fallback icon (only show when no source or error)
                DankIcon {
                    anchors.centerIn: parent
                    name: "movie"
                    size: 32
                    color: Theme.primary
                    visible: thumbnailImage.status === Image.Null || thumbnailImage.status === Image.Error
                }

                StateLayer {
                    anchors.fill: parent
                    cornerRadius: parent.radius
                    stateColor: Theme.primary
                }
                
                // Click area for video selection
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        videoGridView.currentIndex = index
                        setCurrentVideo(modelData)
                    }
                }

                // Remove button overlay (top-right corner)
                Rectangle {
                    id: removeButton
                    width: 24
                    height: 24
                    radius: 12
                    color: "#D32F2F"
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 8
                    visible: removeMouseArea.containsMouse
                    z: 100

                    DankIcon {
                        anchors.centerIn: parent
                        name: "close"
                        size: 16
                        color: "white"
                    }

                    MouseArea {
                        id: removeMouseArea
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            removeFromPlaylist(index)
                        }
                    }
                }
            }
        }
    }

    StyledText {
        text: {
            currentVideoRefresh
            const playlist = getPlaylist()
            if (playlist.length > 0) {
                return MpvPaperI18n.tr("Video List (%1 videos)", "mpvpaper").arg(playlist.length)
            }
            return MpvPaperI18n.tr("Video List (Empty)", "mpvpaper")
        }
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
        wrapMode: Text.Wrap
    }

    StyledText {
        text: MpvPaperI18n.tr("Add videos to the list and select a playback mode", "mpvpaper")
        font.pixelSize: Theme.fontSizeSmall
        opacity: 0.7
        wrapMode: Text.Wrap
    }

    Row {
        width: parent.width
        spacing: Theme.spacingM

        DankButton {
            text: MpvPaperI18n.tr("Add Video", "mpvpaper")
            width: (parent.width - Theme.spacingM * 2) / 3
            onClicked: {
                openSystemFilePicker()
            }
        }

        DankButton {
            text: MpvPaperI18n.tr("Add Folder", "mpvpaper")
            width: (parent.width - Theme.spacingM * 2) / 3
            onClicked: {
                openSystemDirectoryPicker()
            }
        }

        DankButton {
            text: MpvPaperI18n.tr("Clear List", "mpvpaper")
            width: (parent.width - Theme.spacingM * 2) / 3
            enabled: getPlaylist().length > 0
            onClicked: {
                clearPlaylist()
            }
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outlineStrong
    }

    StyledText {
        text: MpvPaperI18n.tr("Video Settings", "mpvpaper")
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
    }

    Column {
        width: parent.width
        spacing: 2

        Row {
            id: hwdecRow
            width: parent.width
            spacing: Theme.spacingM

            StyledText {
                text: MpvPaperI18n.tr("Hardware Decoding", "mpvpaper")
                font.pixelSize: Theme.fontSizeSmall
                width: 180
                anchors.verticalCenter: parent.verticalCenter
            }

            DankDropdown {
                id: hwdecDropdown
                width: parent.width - 180 - Theme.spacingM
                options: ["auto", "no", "vaapi", "vdpau", "nvdec"]
                compactMode: true

                Binding {
                    target: hwdecDropdown
                    property: "currentValue"
                    value: getVideoSetting("hwdec", "auto")
                }

                onValueChanged: (value) => {
                    saveVideoSetting("hwdec", value)
                }
            }
        }
        StyledText {
            text: MpvPaperI18n.tr("Hardware acceleration method for video decoding", "mpvpaper")
            font.pixelSize: Theme.fontSizeSmall * 0.9
            opacity: 0.5
            width: parent.width
            wrapMode: Text.Wrap
        }
    }

    Column {
        width: parent.width
        spacing: 2

        Row {
            width: parent.width
            spacing: Theme.spacingM
            StyledText {
                text: MpvPaperI18n.tr("Tiling Mode", "mpvpaper")
                font.pixelSize: Theme.fontSizeSmall
                width: 180
                anchors.verticalCenter: parent.verticalCenter
            }
            DankDropdown {
                id: panscanDropdown
                width: parent.width - 180 - Theme.spacingM
                options: [MpvPaperI18n.tr("Fill Screen (Crop)", "mpvpaper"), MpvPaperI18n.tr("Fit Screen (Letterbox)", "mpvpaper"), MpvPaperI18n.tr("Stretch Fill", "mpvpaper")]
                compactMode: true

                Binding {
                    target: panscanDropdown
                    property: "currentValue"
                    value: {
                        const panscan = getVideoSetting("panscan", 1.0)
                        if (panscan === 1.0) return MpvPaperI18n.tr("Fill Screen (Crop)", "mpvpaper")
                        if (panscan === 0.0) return MpvPaperI18n.tr("Fit Screen (Letterbox)", "mpvpaper")
                        return MpvPaperI18n.tr("Stretch Fill", "mpvpaper")
                    }
                }

                onValueChanged: (value) => {
                    if (value === MpvPaperI18n.tr("Fill Screen (Crop)", "mpvpaper")) {
                        saveVideoSetting("panscan", 1.0)
                    } else if (value === MpvPaperI18n.tr("Fit Screen (Letterbox)", "mpvpaper")) {
                        saveVideoSetting("panscan", 0.0)
                    } else {
                        saveVideoSetting("panscan", 0.5)
                    }
                }
            }
        }
        StyledText {
            text: MpvPaperI18n.tr("Choose how the video fits the screen size", "mpvpaper")
            font.pixelSize: Theme.fontSizeSmall * 0.9
            opacity: 0.5
            width: parent.width
            wrapMode: Text.Wrap
        }
    }

    Timer {
        id: volumeDebounceTimer
        interval: 500
        repeat: false
        onTriggered: {
            saveVideoSetting("volume", Math.round(volumeSlider.value))
        }
    }

    Column {
        width: parent.width
        spacing: 2

        Row {
            id: volumeRow
            width: parent.width
            height: 24
            spacing: Theme.spacingM

            StyledText {
                text: MpvPaperI18n.tr("Volume", "mpvpaper")
                font.pixelSize: Theme.fontSizeSmall
                width: 180
                anchors.verticalCenter: parent.verticalCenter
            }

            DankSlider {
                id: volumeSlider
                width: parent.width - 180 - Theme.spacingM - volumeValueText.width - Theme.spacingM
                minimum: 0
                maximum: 100
                showValue: false
                anchors.verticalCenter: parent.verticalCenter

                Binding {
                    target: volumeSlider
                    property: "value"
                    value: getVideoSetting("volume", 0)
                }

                onSliderValueChanged: (newValue) => {
                    volumeDebounceTimer.restart()
                }
            }

            StyledText {
                id: volumeValueText
                text: Math.round(volumeSlider.value)
                font.pixelSize: Theme.fontSizeSmall
                width: 40
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        StyledText {
            text: MpvPaperI18n.tr("Audio volume (0 = Mute)", "mpvpaper")
            font.pixelSize: Theme.fontSizeSmall * 0.9
            opacity: 0.5
            width: parent.width
            wrapMode: Text.Wrap
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outlineStrong
    }

    Column {
        width: parent.width
        spacing: 2

        Row {
            width: parent.width
            spacing: Theme.spacingM
            StyledText {
                text: MpvPaperI18n.tr("Scheduled Restart Interval", "mpvpaper")
                font.pixelSize: Theme.fontSizeSmall
                width: 180
                anchors.verticalCenter: parent.verticalCenter
            }
            DankDropdown {
                id: restartIntervalDropdown
                width: parent.width - 180 - Theme.spacingM
                options: [MpvPaperI18n.tr("Disabled", "mpvpaper"), MpvPaperI18n.tr("10 Minutes", "mpvpaper"), MpvPaperI18n.tr("30 Minutes", "mpvpaper"), MpvPaperI18n.tr("1 Hour", "mpvpaper"), MpvPaperI18n.tr("2 Hours", "mpvpaper")]
                compactMode: true

                Binding {
                    target: restartIntervalDropdown
                    property: "currentValue"
                    value: {
                        const interval = loadValue("restartInterval", 60)
                        if (interval === 0) return MpvPaperI18n.tr("Disabled", "mpvpaper")
                        if (interval === 10) return MpvPaperI18n.tr("10 Minutes", "mpvpaper")
                        if (interval === 30) return MpvPaperI18n.tr("30 Minutes", "mpvpaper")
                        if (interval === 60) return MpvPaperI18n.tr("1 Hour", "mpvpaper")
                        if (interval === 120) return MpvPaperI18n.tr("2 Hours", "mpvpaper")
                        return MpvPaperI18n.tr("1 Hour", "mpvpaper")
                    }
                }

                onValueChanged: (value) => {
                    let interval = 60
                    if (value === MpvPaperI18n.tr("Disabled", "mpvpaper")) interval = 0
                    else if (value === MpvPaperI18n.tr("10 Minutes", "mpvpaper")) interval = 10
                    else if (value === MpvPaperI18n.tr("30 Minutes", "mpvpaper")) interval = 30
                    else if (value === MpvPaperI18n.tr("1 Hour", "mpvpaper")) interval = 60
                    else if (value === MpvPaperI18n.tr("2 Hours", "mpvpaper")) interval = 120
                    saveValue("restartInterval", interval)
                }
            }
        }
        StyledText {
            text: MpvPaperI18n.tr("Periodically restart mpv process to prevent potential memory leaks", "mpvpaper")
            font.pixelSize: Theme.fontSizeSmall * 0.9
            opacity: 0.5
            width: parent.width
            wrapMode: Text.Wrap
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outlineStrong
    }

    function openSystemFilePicker() {
        systemFilePickerProcess.selectedFile = ""
        systemFilePickerProcess.running = true
    }

    Process {
        id: systemFilePickerProcess
        property string selectedFile: ""

        // Try zenity first (GNOME), fallback to kdialog (KDE)
        command: ["bash", "-c",
            `if command -v zenity >/dev/null 2>&1; then
                zenity --file-selection --multiple --separator=$'\n' --title="${MpvPaperI18n.tr("Select Video Files", "mpvpaper")}" --file-filter="${MpvPaperI18n.tr("Video Files", "mpvpaper")} | *.mp4 *.mkv *.webm *.avi *.mov *.flv *.wmv *.m4v" --file-filter="${MpvPaperI18n.tr("All Files", "mpvpaper")} | *"
            elif command -v kdialog >/dev/null 2>&1; then
                kdialog --getopenfilename ~ "*.mp4 *.mkv *.webm *.avi *.mov *.flv *.wmv *.m4v|${MpvPaperI18n.tr("Video Files", "mpvpaper")}" --multiple --separate-output
            else
                echo "ERROR: No file picker available"
                exit 1
            fi`
        ]

        stdout: SplitParser {
            onRead: (data) => {
                systemFilePickerProcess.selectedFile += data + "\n"
            }
        }

        onExited: (code) => {
            const trimmedOutput = selectedFile.trim()
            if (code === 0 && trimmedOutput !== "") {
                const files = trimmedOutput.split('\n').map(f => f.trim()).filter(f => f !== "")
                if (files.length > 0) {
                    addMultipleToPlaylist(files)
                    if (files.length === 1) {
                        ToastService.showInfo(MpvPaperI18n.tr("Video Added", "mpvpaper"), files[0].substring(files[0].lastIndexOf('/') + 1))
                    } else {
                        ToastService.showInfo(MpvPaperI18n.tr("Video Added", "mpvpaper"), MpvPaperI18n.tr("Successfully added %1 videos", "mpvpaper").arg(files.length))
                    }
                }
            } else if (trimmedOutput.includes("ERROR")) {
                console.log("MpvPaper: System file picker not available, using DMS file browser")
                videoFileBrowser.open()
            }
            selectedFile = ""
        }
    }

    function openSystemDirectoryPicker() {
        systemDirectoryPickerProcess.selectedDir = ""
        systemDirectoryPickerProcess.running = true
    }

    Process {
        id: systemDirectoryPickerProcess
        property string selectedDir: ""

        command: ["bash", "-c",
            `if command -v zenity >/dev/null 2>&1; then
                zenity --file-selection --directory --title="${MpvPaperI18n.tr("Select Video Folder", "mpvpaper")}"
            elif command -v kdialog >/dev/null 2>&1; then
                kdialog --getexistingdirectory ~
            else
                echo "ERROR: No file picker available"
                exit 1
            fi`
        ]

        stdout: SplitParser {
            onRead: (data) => {
                systemDirectoryPickerProcess.selectedDir += data
            }
        }

        onExited: (code) => {
            const trimmedDir = selectedDir.trim()
            if (code === 0 && trimmedDir !== "") {
                scanAndAddFolder(trimmedDir)
            }
            selectedDir = ""
        }
    }

    function scanAndAddFolder(dirPath) {
        folderScanProcess.scanOutput = ""
        folderScanProcess.command = [
            "find", dirPath, "-type", "f", "-regextype", "posix-extended",
            "-iregex", ".*\\.(mp4|mkv|webm|avi|mov|flv|wmv|m4v)"
        ]
        folderScanProcess.running = true
    }

    Process {
        id: folderScanProcess
        property string scanOutput: ""
        stdout: SplitParser {
            onRead: (data) => {
                folderScanProcess.scanOutput += data + "\n"
            }
        }
        onExited: (code) => {
            if (code === 0 && scanOutput.trim() !== "") {
                const files = scanOutput.trim().split('\n').filter(f => f.trim() !== "")
                if (files.length > 0) {
                    addMultipleToPlaylist(files)
                    ToastService.showInfo(MpvPaperI18n.tr("Folder Added", "mpvpaper"), MpvPaperI18n.tr("Added %1 videos from directory", "mpvpaper").arg(files.length))
                } else {
                    ToastService.showWarning(MpvPaperI18n.tr("No Videos Found", "mpvpaper"), MpvPaperI18n.tr("No supported video files found in selected folder", "mpvpaper"))
                }
            }
            scanOutput = ""
        }
    }

    function addMultipleToPlaylist(videoPaths) {
        if (!videoPaths || videoPaths.length === 0) return
        
        var playlists = loadValue("monitorPlaylists", {})
        if (!playlists[selectedMonitor]) {
            playlists[selectedMonitor] = []
        }
        
        let addedCount = 0
        let lastAdded = ""
        
        for (const path of videoPaths) {
            const trimmedPath = path.trim()
            if (trimmedPath && playlists[selectedMonitor].indexOf(trimmedPath) === -1) {
                playlists[selectedMonitor].push(trimmedPath)
                addedCount++
                lastAdded = trimmedPath
            }
        }
        
        if (addedCount > 0) {
            saveValue("monitorPlaylists", playlists)

            var indices = loadValue("playlistIndices", {})
            indices[selectedMonitor] = playlists[selectedMonitor].indexOf(lastAdded)
            saveValue("playlistIndices", indices)
            
            // Set the last added video as current
            var monitorVideos = loadValue("monitorVideos", {})
            monitorVideos[selectedMonitor] = lastAdded
            saveValue("monitorVideos", monitorVideos)
            
            playlistVersion++
            // Trigger UI refresh
            var currentMonitor = selectedMonitor
            selectedMonitor = ""
            selectedMonitor = currentMonitor
        }
    }

    function addToPlaylist(videoPath) {
        addMultipleToPlaylist([videoPath])
    }

    function setCurrentVideo(videoPath) {
        // Find the index of this video in the playlist
        var playlists = loadValue("monitorPlaylists", {})
        var playlist = playlists[selectedMonitor]
        
        if (playlist && Array.isArray(playlist)) {
            var videoIndex = playlist.indexOf(videoPath)
            if (videoIndex !== -1) {
                // Save the index so the plugin backend uses it
                var indices = loadValue("playlistIndices", {})
                indices[selectedMonitor] = videoIndex
                saveValue("playlistIndices", indices)
                
                // Update GridView currentIndex
                videoGridView.currentIndex = videoIndex
            }
        }
        
        // Set as current video
        var monitorVideos = loadValue("monitorVideos", {})
        monitorVideos[selectedMonitor] = videoPath
        saveValue("monitorVideos", monitorVideos)
        
        // Trigger refresh using the same method as addToPlaylist
        playlistVersion++
        var currentMonitor = selectedMonitor
        selectedMonitor = ""
        selectedMonitor = currentMonitor
    }

    function removeFromPlaylist(index) {
        var playlists = loadValue("monitorPlaylists", {})
        var list = playlists[selectedMonitor]
        if (!Array.isArray(list) || index < 0 || index >= list.length) return
        
        // Get the video path before removing
        var videoPath = list[index]
        
        // Delete thumbnail cache for this video
        deleteThumbnailCache(videoPath)
        
        // Remove from list
        list.splice(index, 1)
        
        if (list.length === 0) {
            // No videos left, clear everything
            delete playlists[selectedMonitor]
            saveValue("monitorPlaylists", playlists)
            
            var monitorVideos = loadValue("monitorVideos", {})
            delete monitorVideos[selectedMonitor]
            saveValue("monitorVideos", monitorVideos)
            
            // Clear playlist index
            var indices = loadValue("playlistIndices", {})
            delete indices[selectedMonitor]
            saveValue("playlistIndices", indices)
        } else {
            // Update playlist
            playlists[selectedMonitor] = list
            saveValue("monitorPlaylists", playlists)
            
            // Update current video and index
            var currentVideoPath = getCurrentVideoPath()
            var currentIndex = list.indexOf(currentVideoPath)
            
            if (currentIndex === -1) {
                // Current video was removed, switch to first video
                currentIndex = 0
                var monitorVideos = loadValue("monitorVideos", {})
                monitorVideos[selectedMonitor] = list[0]
                saveValue("monitorVideos", monitorVideos)
            } else if (index < currentIndex) {
                // A video before current was removed, adjust index
                currentIndex = currentIndex - 1
            }
            
            // Update playlist index
            var indices = loadValue("playlistIndices", {})
            indices[selectedMonitor] = currentIndex
            saveValue("playlistIndices", indices)
            
            // Update GridView currentIndex
            videoGridView.currentIndex = currentIndex
        }
        
        // Trigger refresh
        playlistVersion++
        var currentMonitor = selectedMonitor
        selectedMonitor = ""
        selectedMonitor = currentMonitor
    }
    
    function deleteThumbnailCache(videoPath) {
        const cacheHome = StandardPaths.writableLocation(StandardPaths.GenericCacheLocation).toString().replace("file://", "")
        const cacheDir = cacheHome + "/DankMaterialShell/mpvpaper_thumbnails"
        
        // Create hash from video path
        const hash = videoPath.split('').reduce((a, b) => {
            a = ((a << 5) - a) + b.charCodeAt(0)
            return a & a
        }, 0)
        
        const thumbPath = cacheDir + "/" + Math.abs(hash) + "_thumb.jpg"
        const previewPath = cacheDir + "/" + Math.abs(hash) + "_preview.jpg"
        
        // Delete both thumbnail files
        thumbnailDeleteProcess.command = ["rm", "-f", "--", thumbPath, previewPath]
        thumbnailDeleteProcess.running = true
    }
    
    Process {
        id: thumbnailDeleteProcess
        command: []
    }

    function clearPlaylist() {
        var playlists = loadValue("monitorPlaylists", {})
        delete playlists[selectedMonitor]
        saveValue("monitorPlaylists", playlists)
        
        var monitorVideos = loadValue("monitorVideos", {})
        delete monitorVideos[selectedMonitor]
        saveValue("monitorVideos", monitorVideos)

        var indices = loadValue("playlistIndices", {})
        delete indices[selectedMonitor]
        saveValue("playlistIndices", indices)
        
        playlistVersion++
        var currentMonitor = selectedMonitor
        selectedMonitor = ""
        selectedMonitor = currentMonitor
    }

    function getVideoSettings() {
        var videoPath = getCurrentVideoPath()
        if (!videoPath) return {}

        var allSettings = loadValue("videoSettings", {})
        return allSettings[videoPath] || {}
    }

    function getVideoSetting(key, defaultValue) {
        var settings = getVideoSettings()
        return settings[key] !== undefined ? settings[key] : defaultValue
    }

    function saveVideoSetting(key, value) {
        var videoPath = getCurrentVideoPath()
        if (!videoPath) return

        var allSettings = loadValue("videoSettings", {})
        if (!allSettings[videoPath]) {
            allSettings[videoPath] = {}
        }
        allSettings[videoPath][key] = value
        saveValue("videoSettings", allSettings)
    }

    function getCurrentVideoPath() {
        var monitorVideos = loadValue("monitorVideos", {})
        return monitorVideos[selectedMonitor] || ""
    }

    function getPlaylist() {
        var playlists = loadValue("monitorPlaylists", {})
        var list = playlists[selectedMonitor]
        return Array.isArray(list) ? list : []
    }

    FileBrowserSurfaceModal {
        id: videoFileBrowser
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
}
