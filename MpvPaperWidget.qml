import QtCore
import Qt.labs.folderlistmodel
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtMultimedia
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import qs.Modals.FileBrowser
import qs.Modals.Common
import qs.Services

PluginComponent {
    id: root
    pluginId: "mpvpaper"

    Component.onCompleted: {
        MpvPaperI18n.language = pluginData.language || "en"
        Qt.callLater(() => {
            normalizeGammaImageData()
            loadImageFolder()
            ensureAllMonitorsDefault()
        })
    }

    property var monitors: Quickshell.screens.map(screen => screen.name)
    property string selectedMonitor: {
        if (parentScreen && parentScreen.name) return parentScreen.name
        return monitors.length > 0 ? monitors[0] : ""
    }
    property string imageFolder: ""
    property int currentPage: 0
    property int itemsPerPage: 4 * chooserRows
    readonly property real popoutPadding: Theme.spacingM
    readonly property real chooserWidth: Math.min(1400, Math.max(720, (parentScreen ? parentScreen.width : 1920) * 0.86))
    readonly property real chooserHeight: Math.min(980, Math.max(520, (parentScreen ? parentScreen.height : 1080) * 0.92))
    readonly property real chooserViewportHeight: Math.min(chooserHeight, (parentScreen ? parentScreen.height : 1080) - Theme.spacingXL * 2)
    readonly property real popoutContentWidth: chooserWidth - popoutPadding * 2
    readonly property real popoutGridCellHeight: Math.floor(popoutContentWidth / 4) * 9 / 16
    readonly property real chooserFixedHeight: popoutPadding * 2 + 32
        + 48 + 40 + Theme.spacingM * 3
    readonly property int chooserRows: Math.max(1, Math.min(4, Math.floor((chooserViewportHeight - chooserFixedHeight) / Math.max(1, popoutGridCellHeight))))
    property int totalPages: Math.max(1, Math.ceil(mediaItems.length / itemsPerPage))
    property int refreshTrigger: 0
    property int gridIndex: 0
    property var fileBrowserParentPopout: null
    property bool sameOnAllMonitors: pluginData.allMonitorsDefault !== undefined ? pluginData.allMonitorsDefault : true
    readonly property bool activeSameOnAllMonitors: pluginData.sameOnAllMonitors || false
    property var colorSortOrder: []
    property bool colorSortSucceeded: false
    property string colorSortReadySignature: ""
    property string colorSortPendingSignature: ""
    property var colorSortCommand: []
    property bool colorSortRunning: false
    property var trashCommand: []
    property var pendingTrashItem: null
    property bool trashRunning: false
    property real gammaSliderValue: 1.0
    property bool gammaSliderSyncing: false
    property bool gammaProcessing: false
    property string gammaPendingImagePath: ""
    property real gammaPendingValue: 1.0
    property var gammaPendingKeepPaths: []
    property string gammaImageOutput: ""
    property var queuedGammaTarget: null
    property real queuedGammaValue: 1.0
    property string previewedVideoPath: ""
    readonly property string colorSortScriptPath: Qt.resolvedUrl("color_sort.py").toString().replace(/^file:\/\//, "")
    readonly property string colorSortCachePath: StandardPaths.writableLocation(StandardPaths.GenericCacheLocation).toString().replace("file://", "") + "/DankMaterialShell/mpvpaper_color_sort.json"
    readonly property string gammaScriptPath: Qt.resolvedUrl("gamma_cache.py").toString().replace(/^file:\/\//, "")
    readonly property string gammaCachePath: StandardPaths.writableLocation(StandardPaths.GenericCacheLocation).toString().replace("file://", "") + "/DankMaterialShell/mpvpaper_gamma"
    readonly property var gammaTargetItem: {
        const index = currentPage * itemsPerPage + gridIndex
        return mediaItems[index] || null
    }

    readonly property var mediaItems: {
        root.refreshTrigger
        const items = root.collectMediaItems()
        const signature = root.mediaSignature(items)
        if (signature !== root.colorSortReadySignature || !root.colorSortSucceeded)
            return items

        const order = ({})
        for (let i = 0; i < root.colorSortOrder.length; i++)
            order[root.colorSortOrder[i]] = i
        const availableItems = items.filter(item => order[item.path] !== undefined)
        return availableItems.sort((a, b) => {
            if (a.kind !== b.kind) return a.kind === "image" ? -1 : 1
            return (order[a.path] ?? Number.MAX_SAFE_INTEGER) - (order[b.path] ?? Number.MAX_SAFE_INTEGER)
        })
    }

    function collectMediaItems() {
        const videos = []
        const seenVideos = ({})
        for (const path of root.getPlaylist()) {
            if (path && !seenVideos[path]) {
                videos.push({ kind: "video", path })
                seenVideos[path] = true
            }
        }
        if (videoFolderModel.status === FolderListModel.Ready) {
            for (let i = 0; i < videoFolderModel.count; i++) {
                const rawPath = videoFolderModel.get(i, "filePath")
                const path = rawPath ? rawPath.toString().replace(/^file:\/\//, "") : ""
                if (path && !seenVideos[path]) {
                    videos.push({ kind: "video", path })
                    seenVideos[path] = true
                }
            }
        }
        const images = []
        const seenImages = ({})
        if (imageFolderModel.status === FolderListModel.Ready) {
            for (let i = 0; i < imageFolderModel.count; i++) {
                const rawPath = imageFolderModel.get(i, "filePath")
                const path = rawPath ? rawPath.toString().replace(/^file:\/\//, "") : ""
                if (path && !isGammaCachePath(path) && !seenImages[path]) {
                    images.push({ kind: "image", path })
                    seenImages[path] = true
                }
            }
        }
        return images.concat(videos)
    }

    function mediaSignature(items) {
        return JSON.stringify(items.map(item => [item.kind, item.path]))
    }

    function startColorSort() {
        if (colorSortRunning) return
        const items = collectMediaItems()
        if (items.length === 0) return

        const signature = mediaSignature(items)
        if (signature === colorSortReadySignature) return

        colorSortPendingSignature = signature
        colorSortProcess.output = ""
        colorSortCommand = ["python3", colorSortScriptPath, "--cache", colorSortCachePath, "--"].concat(items.map(item => item.path))
        colorSortRunning = true
        colorSortProcess.running = true
    }

    readonly property string sessionWallpaperPath: SessionData.wallpaperPath
    readonly property var sessionMonitorWallpapers: SessionData.monitorWallpapers
    readonly property bool sessionPerMonitorWallpaper: SessionData.perMonitorWallpaper

    Connections {
        target: pluginService
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === "mpvpaper") root.refreshTrigger++
        }
    }

    onPluginDataChanged: {
        MpvPaperI18n.language = pluginData.language || "en"
        sameOnAllMonitors = pluginData.allMonitorsDefault !== undefined ? pluginData.allMonitorsDefault : true
        refreshTrigger++
    }

    onRefreshTriggerChanged: {
        if (!chooserModal.shouldBeVisible) selectionSyncTimer.restart()
        colorSortDebounce.restart()
        Qt.callLater(syncGammaSlider)
    }

    onCurrentPageChanged: {
        gammaApplyDebounce.stop()
        queuedGammaTarget = null
        previewedVideoPath = ""
        Qt.callLater(syncGammaSlider)
    }
    onGridIndexChanged: {
        if (queuedGammaTarget
                && (queuedGammaTarget.path !== gammaTargetItem?.path
                    || queuedGammaTarget.kind !== gammaTargetItem?.kind)) {
            gammaApplyDebounce.stop()
            queuedGammaTarget = null
        }
        Qt.callLater(syncGammaSlider)
    }

    onSelectedMonitorChanged: {
        loadImageFolder()
        selectionSyncTimer.restart()
    }

    onSessionWallpaperPathChanged: loadImageFolder()
    onSessionMonitorWallpapersChanged: loadImageFolder()
    onSessionPerMonitorWallpaperChanged: loadImageFolder()
    onPluginServiceChanged: {
        Qt.callLater(ensureAllMonitorsDefault)
        Qt.callLater(normalizeGammaImageData)
    }

    function ensureAllMonitorsDefault() {
        if (!pluginService) return
        const savedDefault = pluginService.loadPluginData("mpvpaper", "allMonitorsDefault", null)
        if (savedDefault === null || savedDefault === undefined) {
            sameOnAllMonitors = true
            pluginService.savePluginData("mpvpaper", "allMonitorsDefault", true)
        }
    }

    Timer {
        id: selectionSyncTimer
        interval: 0
        repeat: false
        onTriggered: root.syncSelectionToPlayback()
    }

    Timer {
        id: colorSortDebounce
        interval: 250
        repeat: false
        onTriggered: root.startColorSort()
    }

    Process {
        id: colorSortProcess
        property string output: ""
        command: root.colorSortCommand
        stdout: SplitParser {
            onRead: data => colorSortProcess.output += data
        }
        stderr: SplitParser {
            onRead: data => console.warn("MpvPaper color sort:", data)
        }
        onExited: code => {
            root.colorSortRunning = false
            if (code === 0) {
                try {
                    const result = JSON.parse(colorSortProcess.output.trim())
                    if (Array.isArray(result)) {
                        root.colorSortOrder = result
                        root.colorSortSucceeded = true
                    } else {
                        root.colorSortOrder = []
                        root.colorSortSucceeded = false
                    }
                } catch (error) {
                    root.colorSortOrder = []
                    root.colorSortSucceeded = false
                    console.warn("MpvPaper: Could not read color sort result:", error)
                }
            } else {
                root.colorSortOrder = []
                root.colorSortSucceeded = false
                console.warn("MpvPaper: Automatic color sorting failed; keeping the default order")
            }
            root.colorSortReadySignature = root.colorSortPendingSignature
            colorSortProcess.output = ""
            root.refreshTrigger++
        }
    }

    Process {
        id: trashProcess
        command: root.trashCommand
        onExited: code => {
            const item = root.pendingTrashItem
            root.pendingTrashItem = null
            root.trashRunning = false
            if (code === 0)
                root.finishMoveToTrash(item)
            else
                ToastService.showError("Wallpapers", "Could not move the file to Trash.")
        }
    }

    Process {
        id: gammaImageProcess
        command: ["python3", root.gammaScriptPath, root.gammaCachePath,
            root.gammaPendingImagePath, root.gammaPendingValue.toFixed(2)].concat(root.gammaPendingKeepPaths)
        stdout: SplitParser {
            onRead: data => root.gammaImageOutput += data
        }
        stderr: SplitParser {
            onRead: data => console.warn("MpvPaper gamma:", data)
        }
        onExited: code => {
            const sourcePath = root.gammaPendingImagePath
            const value = root.gammaPendingValue
            const outputPath = root.gammaImageOutput.trim()
            const keepPaths = root.gammaPendingKeepPaths.slice()
            const hasNewerValueForSource = root.queuedGammaTarget
                && root.queuedGammaTarget.kind === "image"
                && root.originalImagePath(root.queuedGammaTarget.path) === sourcePath
            root.gammaProcessing = false
            root.gammaPendingImagePath = ""
            root.gammaPendingKeepPaths = []
            root.gammaImageOutput = ""
            if (hasNewerValueForSource) {
                gammaApplyDebounce.restart()
                return
            }
            if (code !== 0 || !outputPath) {
                root.gammaSliderSyncing = true
                root.gammaSliderValue = root.gammaForItem({ kind: "image", path: sourcePath })
                Qt.callLater(() => root.gammaSliderSyncing = false)
                ToastService.showError("Gamma", "Could not generate the gamma-corrected image.")
                if (root.queuedGammaTarget) gammaApplyDebounce.restart()
                return
            }

            const imageGammas = Object.assign({}, pluginService.loadPluginData("mpvpaper", "imageGammas", {}))
            imageGammas[sourcePath] = value
            pluginService.savePluginData("mpvpaper", "imageGammas", imageGammas)

            const imageSources = Object.assign({}, pluginService.loadPluginData("mpvpaper", "gammaImageSources", {}))
            for (const cachedPath of Object.keys(imageSources)) {
                if (imageSources[cachedPath] === sourcePath
                        && cachedPath !== outputPath && !keepPaths.includes(cachedPath))
                    delete imageSources[cachedPath]
            }
            imageSources[outputPath] = sourcePath
            pluginService.savePluginData("mpvpaper", "gammaImageSources", imageSources)

            root.applyImageWallpaper(sourcePath, outputPath)
            ToastService.showInfo("Gamma", `Image: ${value.toFixed(2)}`)
            if (root.queuedGammaTarget) gammaApplyDebounce.restart()
        }
    }

    Timer {
        id: gammaApplyDebounce
        interval: 180
        repeat: false
        onTriggered: root.applyQueuedGamma()
    }


    function syncSelectionToPlayback() {
        const videoPath = getCurrentVideoPath()
        const imagePath = getCurrentWallpaperPath()
        let index = videoPath
            ? mediaItems.findIndex(item => item.kind === "video" && item.path === videoPath)
            : -1
        if (index < 0)
            index = mediaItems.findIndex(item => item.kind === "image" && item.path === imagePath)
        if (index < 0) return
        currentPage = Math.floor(index / itemsPerPage)
        gridIndex = index % itemsPerPage
    }

    function isGammaCachePath(path) {
        const cachePath = gammaCachePath.replace(/\/+$/, "")
        return !!path && (path === cachePath || path.startsWith(cachePath + "/"))
    }

    function resolveOriginalImage(path, imageSources) {
        let current = path || ""
        let depth = 0
        const visited = ({})
        while (current && imageSources[current] && !visited[current]) {
            visited[current] = true
            current = imageSources[current]
            depth++
        }
        return { path: current, depth }
    }

    function originalImagePath(path) {
        if (!path || !pluginService) return path || ""
        const imageSources = pluginService.loadPluginData("mpvpaper", "gammaImageSources", {})
        return resolveOriginalImage(path, imageSources).path
    }

    function normalizeGammaImageData() {
        if (!pluginService) return

        const storedSources = Object.assign({}, pluginService.loadPluginData("mpvpaper", "gammaImageSources", {}))
        const storedGammas = Object.assign({}, pluginService.loadPluginData("mpvpaper", "imageGammas", {}))
        const flattenedSources = Object.assign({}, storedSources)
        const migratedGammas = Object.assign({}, storedGammas)
        const bestDepthBySource = ({})

        for (const outputPath of Object.keys(storedSources)) {
            if (!isGammaCachePath(outputPath)) continue
            const resolved = resolveOriginalImage(outputPath, storedSources)
            if (resolved.path && resolved.path !== outputPath)
                flattenedSources[outputPath] = resolved.path
        }

        for (const cachedPath of Object.keys(storedGammas)) {
            if (!isGammaCachePath(cachedPath)) continue
            const resolved = resolveOriginalImage(cachedPath, storedSources)
            if (resolved.path && resolved.path !== cachedPath
                    && (bestDepthBySource[resolved.path] === undefined
                        || resolved.depth > bestDepthBySource[resolved.path])) {
                migratedGammas[resolved.path] = Number(storedGammas[cachedPath])
                bestDepthBySource[resolved.path] = resolved.depth
            }
            delete migratedGammas[cachedPath]
        }

        if (JSON.stringify(flattenedSources) !== JSON.stringify(storedSources))
            pluginService.savePluginData("mpvpaper", "gammaImageSources", flattenedSources)
        if (JSON.stringify(migratedGammas) !== JSON.stringify(storedGammas))
            pluginService.savePluginData("mpvpaper", "imageGammas", migratedGammas)
    }

    function getCurrentWallpaperSourceForMonitor(monitor) {
        return originalImagePath(SessionData.getMonitorWallpaper(monitor) || "")
    }

    function getCurrentWallpaperPath() {
        let path
        if (SessionData.perMonitorWallpaper && selectedMonitor)
            path = SessionData.getMonitorWallpaper(selectedMonitor) || ""
        else
            path = SessionData.wallpaperPath || ""
        return originalImagePath(path)
    }

    function loadImageFolder() {
        let path = getCurrentWallpaperPath()
        if (!path || path.startsWith("#"))
            path = StandardPaths.writableLocation(StandardPaths.PicturesLocation).toString().replace(/^file:\/\//, "")
        else
            path = path.substring(0, path.lastIndexOf("/"))
        if (path && path !== imageFolder) imageFolder = path
    }

    function imageFolderUrl(path) {
        return path ? "file://" + path.split("/").map(part => encodeURIComponent(part)).join("/") : ""
    }

    function gammaForItem(item) {
        if (!item || !pluginService) return 1.0
        if (item.kind === "video") {
            const videoSettings = pluginService.loadPluginData("mpvpaper", "videoSettings", {})
            const settings = videoSettings[item.path] || {}
            return settings.gamma === undefined ? 1.0 : Number(settings.gamma)
        }
        const imageGammas = pluginService.loadPluginData("mpvpaper", "imageGammas", {})
        const sourcePath = originalImagePath(item.path)
        const gamma = imageGammas[sourcePath] === undefined ? imageGammas[item.path] : imageGammas[sourcePath]
        return gamma === undefined ? 1.0 : Number(gamma)
    }

    function syncGammaSlider() {
        gammaSliderSyncing = true
        gammaSliderValue = gammaForItem(gammaTargetItem)
        Qt.callLater(() => gammaSliderSyncing = false)
    }

    function sliderPositionForGamma(gamma) {
        const value = Math.max(0.25, Math.min(2.0, Math.round(Number(gamma) * 20) / 20))
        return value <= 1.0
            ? Math.round((value - 0.25) * 80)
            : 60 + Math.round((value - 1.0) * 60)
    }

    function gammaForSliderPosition(position) {
        const sliderPosition = Math.max(0, Math.min(120, Math.round(position)))
        const value = sliderPosition <= 60
            ? 0.25 + (sliderPosition / 60) * 0.75
            : 1.0 + ((sliderPosition - 60) / 60)
        return Math.max(0.25, Math.min(2.0, Math.round(value * 20) / 20))
    }

    function updateGammaFromSlider(position, shouldApply) {
        if (gammaSliderSyncing) return
        const gamma = gammaForSliderPosition(position)
        const snappedPosition = sliderPositionForGamma(gamma)
        if (snappedPosition !== Math.round(position)) {
            gammaSliderSyncing = true
            gammaSliderValue = gamma
            Qt.callLater(() => gammaSliderSyncing = false)
        } else {
            gammaSliderValue = gamma
        }
        if (shouldApply) queueGammaApply(gammaTargetItem, gamma)
    }

    function queueGammaApply(item, gamma) {
        if (!item) return
        queuedGammaTarget = { kind: item.kind, path: item.path }
        queuedGammaValue = gamma
        gammaApplyDebounce.restart()
    }

    function applyQueuedGamma() {
        const item = queuedGammaTarget
        const gamma = queuedGammaValue
        if (!item || !pluginService) {
            queuedGammaTarget = null
            return
        }
        if (gammaProcessing) return
        queuedGammaTarget = null

        if (item.kind === "video") {
            const allSettings = Object.assign({}, pluginService.loadPluginData("mpvpaper", "videoSettings", {}))
            const settings = Object.assign({}, allSettings[item.path] || {})
            if (Math.abs(Number(settings.gamma === undefined ? 1.0 : settings.gamma) - gamma) < 0.001) return
            settings.gamma = gamma
            allSettings[item.path] = settings
            pluginService.savePluginData("mpvpaper", "videoSettings", allSettings)
            refreshTrigger++
            return
        }

        const sourcePath = originalImagePath(item.path)
        if (gamma === 1.0) {
            const imageGammas = Object.assign({}, pluginService.loadPluginData("mpvpaper", "imageGammas", {}))
            imageGammas[sourcePath] = gamma
            pluginService.savePluginData("mpvpaper", "imageGammas", imageGammas)
            applyImageWallpaper(sourcePath, sourcePath)
            return
        }

        startGammaImageProcessing(sourcePath, gamma)
    }

    function startGammaImageProcessing(imagePath, gamma) {
        imagePath = originalImagePath(imagePath)
        if (!imagePath || gammaProcessing) return
        gammaPendingImagePath = imagePath
        gammaPendingValue = gamma
        gammaPendingKeepPaths = currentWallpaperOutputPaths()
        gammaImageOutput = ""
        gammaProcessing = true
        gammaImageProcess.running = true
    }

    function currentWallpaperOutputPaths() {
        const paths = []
        if (SessionData.perMonitorWallpaper) {
            for (const monitor of monitors) {
                const path = SessionData.getMonitorWallpaper(monitor) || ""
                if (path) paths.push(path)
            }
        } else {
            if (SessionData.wallpaperPath) paths.push(SessionData.wallpaperPath)
            if (SessionData.perModeWallpaper) {
                if (SessionData.wallpaperPathLight) paths.push(SessionData.wallpaperPathLight)
                if (SessionData.wallpaperPathDark) paths.push(SessionData.wallpaperPathDark)
            }
        }
        return Array.from(new Set(paths))
    }

    function applyImageWallpaper(sourcePath, wallpaperPath) {
        if (!sourcePath || !wallpaperPath) return
        sourcePath = originalImagePath(sourcePath)
        stopVideoForImage()
        if (SessionData.perMonitorWallpaper && selectedMonitor) {
            SessionData.setMonitorWallpaper(selectedMonitor, wallpaperPath)
            SessionData.setMonitorCyclingFolderPath(selectedMonitor, "")
        } else {
            SessionData.setWallpaper(wallpaperPath)
            SessionData.wallpaperCyclingFolderPath = ""
        }
        imageFolder = sourcePath.substring(0, sourcePath.lastIndexOf("/"))
        const imageIndex = mediaItems.findIndex(item => item.kind === "image" && item.path === sourcePath)
        if (imageIndex >= 0) {
            currentPage = Math.floor(imageIndex / itemsPerPage)
            gridIndex = imageIndex % itemsPerPage
        }
        root.refreshTrigger++
    }

    function scrollChooserPages(delta) {
        if (totalPages <= 1 || delta === 0) return
        const nextPage = Math.max(0, Math.min(totalPages - 1, currentPage + delta))
        if (nextPage === currentPage) return
        previewedVideoPath = ""
        currentPage = nextPage
        gridIndex = 0
    }

    function qualityLabelFor(kind, probeOutput) {
        const fields = (probeOutput || "").trim().split("x")
        const width = Number(fields[0])
        const height = Number(fields[1])
        if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0)
            return ""

        const longEdge = Math.max(width, height)
        const shortEdge = Math.min(width, height)
        let resolution = `${width}×${height}`
        if (longEdge >= 7680 && shortEdge >= 4320) resolution = "8K"
        else if (longEdge >= 5120 && shortEdge >= 2880) resolution = "5K"
        else if (longEdge >= 3840 && shortEdge >= 2160) resolution = "4K"
        else if (longEdge >= 2560 && shortEdge >= 1440) resolution = "1440p"
        else if (longEdge >= 1920 && shortEdge >= 1080) resolution = "1080p"
        else if (longEdge >= 1280 && shortEdge >= 720) resolution = "720p"

        if (kind !== "video" || fields.length < 3)
            return resolution

        const rate = fields[2].split("/")
        const numerator = Number(rate[0])
        const denominator = rate.length > 1 ? Number(rate[1]) : 1
        const fps = denominator > 0 ? numerator / denominator : 0
        if (!Number.isFinite(fps) || fps <= 0)
            return resolution

        const fpsLabel = Math.abs(fps - Math.round(fps)) < 0.05 ? String(Math.round(fps)) : fps.toFixed(1)
        return `${resolution} · ${fpsLabel} fps`
    }

    function getPlaylist() {
        if (!pluginService) return []
        const library = pluginService.loadPluginData("mpvpaper", "videoLibrary", [])
        return Array.isArray(library) ? library : []
    }

    function cycleMonitor(offset) {
        if (monitors.length < 2) return
        let index = monitors.indexOf(selectedMonitor)
        if (index < 0) index = 0
        selectedMonitor = monitors[(index + offset + monitors.length) % monitors.length]
        selectionSyncTimer.restart()
    }

    function getCurrentVideoPath() {
        if (!pluginService) return ""
        const monitorVideos = pluginService.loadPluginData("mpvpaper", "monitorVideos", {})

        if (activeSameOnAllMonitors) {
            return pluginService.loadPluginData("mpvpaper", "allMonitorsVideo", "")
        }

        return monitorVideos[selectedMonitor] || ""
    }

    function setCurrentVideo(videoPath) {
        if (!pluginService || !videoPath) return
        if (getPlaylist().indexOf(videoPath) === -1)
            addToPlaylist(videoPath)

        if (sameOnAllMonitors) {
            pluginService.savePluginData("mpvpaper", "sameOnAllMonitors", true)
            pluginService.savePluginData("mpvpaper", "allMonitorsVideo", videoPath)
        } else {
            pluginService.savePluginData("mpvpaper", "sameOnAllMonitors", false)
            const monitorVideos = pluginService.loadPluginData("mpvpaper", "monitorVideos", {})
            if (selectedMonitor) monitorVideos[selectedMonitor] = videoPath
            pluginService.savePluginData("mpvpaper", "monitorVideos", monitorVideos)
        }

        const videoIndex = mediaItems.findIndex(item => item.kind === "video" && item.path === videoPath)
        if (videoIndex >= 0) {
            currentPage = Math.floor(videoIndex / itemsPerPage)
            gridIndex = videoIndex % itemsPerPage
        }
        root.refreshTrigger++
    }

    function stopVideoForImage() {
        if (!pluginService) return

        const perMonitorImages = SessionData.perMonitorWallpaper
        const videos = Object.assign({}, pluginService.loadPluginData("mpvpaper", "monitorVideos", {}))
        const sharedVideo = pluginService.loadPluginData("mpvpaper", "allMonitorsVideo", "")

        if (root.activeSameOnAllMonitors) {
            for (const monitor of root.monitors) {
                videos[monitor] = perMonitorImages && monitor !== root.selectedMonitor ? sharedVideo : ""
            }
            pluginService.savePluginData("mpvpaper", "sameOnAllMonitors", false)
            pluginService.savePluginData("mpvpaper", "allMonitorsVideo", "")
        } else if (perMonitorImages) {
            videos[root.selectedMonitor] = ""
        } else {
            for (const monitor of root.monitors) videos[monitor] = ""
            for (const monitor of Object.keys(videos)) videos[monitor] = ""
        }

        pluginService.savePluginData("mpvpaper", "monitorVideos", videos)
    }

    function setCurrentImage(imagePath) {
        if (!imagePath) return
        imagePath = originalImagePath(imagePath)
        const gamma = gammaForItem({ kind: "image", path: imagePath })
        if (gamma > 1.001 || gamma < 0.999) {
            startGammaImageProcessing(imagePath, gamma)
            return
        }
        applyImageWallpaper(imagePath, imagePath)
    }

    function moveMediaToTrash(item) {
        if (!item || !item.path || trashRunning) return
        pendingTrashItem = { kind: item.kind, path: item.path }
        trashCommand = ["dms", "trash", "put", item.path]
        trashRunning = true
        trashProcess.running = true
    }

    function finishMoveToTrash(item) {
        if (!item || !item.path) return

        if (item.kind === "video" && pluginService) {
            const library = getPlaylist().filter(path => path !== item.path)
            pluginService.savePluginData("mpvpaper", "videoLibrary", library)

            const monitorVideos = Object.assign({}, pluginService.loadPluginData("mpvpaper", "monitorVideos", {}))
            for (const monitor of Object.keys(monitorVideos)) {
                if (monitorVideos[monitor] === item.path) monitorVideos[monitor] = ""
            }
            pluginService.savePluginData("mpvpaper", "monitorVideos", monitorVideos)

            const sharedVideo = pluginService.loadPluginData("mpvpaper", "allMonitorsVideo", "")
            if (sharedVideo === item.path)
                pluginService.savePluginData("mpvpaper", "allMonitorsVideo", "")

            const videoSettings = Object.assign({}, pluginService.loadPluginData("mpvpaper", "videoSettings", {}))
            if (videoSettings[item.path] !== undefined) {
                delete videoSettings[item.path]
                pluginService.savePluginData("mpvpaper", "videoSettings", videoSettings)
            }
        } else if (item.kind === "image") {
            const replacement = collectMediaItems().find(entry => entry.kind === "image" && entry.path !== item.path)
            const replacementPath = replacement ? replacement.path : ""

            if (SessionData.perMonitorWallpaper) {
                for (const monitor of monitors) {
                    if (root.getCurrentWallpaperSourceForMonitor(monitor) === item.path) {
                        SessionData.setMonitorWallpaper(monitor, replacementPath)
                        SessionData.setMonitorCyclingFolderPath(monitor, "")
                    }
                }
            } else {
                if (root.originalImagePath(SessionData.wallpaperPath || "") === item.path) {
                    SessionData.setWallpaper(replacementPath)
                    SessionData.wallpaperCyclingFolderPath = ""
                }
                if (SessionData.perModeWallpaper) {
                    if (root.originalImagePath(SessionData.wallpaperPathLight || "") === item.path)
                        SessionData.setWallpaperForMode(replacementPath, true)
                    if (root.originalImagePath(SessionData.wallpaperPathDark || "") === item.path)
                        SessionData.setWallpaperForMode(replacementPath, false)
                }
            }

            if (pluginService) {
                const imageGammas = Object.assign({}, pluginService.loadPluginData("mpvpaper", "imageGammas", {}))
                delete imageGammas[item.path]
                pluginService.savePluginData("mpvpaper", "imageGammas", imageGammas)

                const imageSources = Object.assign({}, pluginService.loadPluginData("mpvpaper", "gammaImageSources", {}))
                for (const outputPath of Object.keys(imageSources)) {
                    if (imageSources[outputPath] === item.path) delete imageSources[outputPath]
                }
                pluginService.savePluginData("mpvpaper", "gammaImageSources", imageSources)
            }
        }

        currentPage = 0
        gridIndex = 0
        refreshTrigger++
        ToastService.showInfo("Wallpapers", "Moved to Trash: " + item.path.split("/").pop())
    }

    function openSystemFilePicker() {
        systemFilePickerProcess.selectedFile = ""
        systemFilePickerProcess.running = true
    }

    function addToPlaylist(videoPath) {
        if (!pluginService || !videoPath) return false

        const trimmedPath = videoPath.trim()
        if (!trimmedPath) return false

        const library = getPlaylist().slice()
        if (library.indexOf(trimmedPath) !== -1) return false

        library.push(trimmedPath)
        pluginService.savePluginData("mpvpaper", "videoLibrary", library)
        refreshTrigger++
        return true
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

    FileBrowserSurfaceModal {
        id: imageFileBrowser
        parentPopout: root.fileBrowserParentPopout
        browserTitle: "Select an image wallpaper"
        browserIcon: "image"
        browserType: "wallpaper"
        showHiddenFiles: true
        fileExtensions: ["*.jpg", "*.jpeg", "*.png", "*.bmp", "*.gif", "*.webp", "*.jxl", "*.avif", "*.heif", "*.exr", "*.svg"]

        onFileSelected: imagePath => root.setCurrentImage(imagePath)
    }

    FolderListModel {
        id: imageFolderModel
        showDirsFirst: false
        showDotAndDotDot: false
        showHidden: false
        caseSensitive: false
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.bmp", "*.gif", "*.webp", "*.jxl", "*.avif", "*.heif", "*.exr", "*.svg"]
        showFiles: true
        showDirs: false
        folder: root.imageFolderUrl(root.imageFolder)
        onCountChanged: root.refreshTrigger++
        onStatusChanged: root.refreshTrigger++
    }

    FolderListModel {
        id: videoFolderModel
        showDirsFirst: false
        showDotAndDotDot: false
        showHidden: false
        caseSensitive: false
        nameFilters: ["*.mp4", "*.mkv", "*.webm", "*.avi", "*.mov", "*.flv", "*.wmv", "*.m4v"]
        showFiles: true
        showDirs: false
        folder: root.imageFolderUrl(root.imageFolder)
        onCountChanged: root.refreshTrigger++
        onStatusChanged: root.refreshTrigger++
    }

    horizontalBarPill: Component { DankIcon { name: "movie"; size: root.iconSize; color: Theme.primary } }
    verticalBarPill: Component { DankIcon { name: "movie"; size: root.iconSize; color: Theme.primary } }

    Component {
        id: popoutBody

        FocusScope {
            anchors.fill: parent
            focus: true

            WheelHandler {
                id: chooserWheelHandler
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                property real accumulatedDelta: 0

                onWheel: event => {
                    const delta = event.angleDelta.y || event.pixelDelta.y
                    if (delta === 0) return
                    accumulatedDelta += delta
                    const steps = Math.trunc(accumulatedDelta / 120)
                    if (steps !== 0) {
                        root.scrollChooserPages(-steps)
                        accumulatedDelta -= steps * 120
                    }
                    event.accepted = true
                }
            }

            Column {
                anchors.fill: parent
                anchors.margins: root.popoutPadding
                spacing: Theme.spacingM

                    // Compact single-line header.  Title, controls, grid and footer
                    // all start/end on the same content bounds.
                    Item {
                        width: parent.width
                        height: 32

                        RowLayout {
                            anchors.fill: parent
                            spacing: Theme.spacingS

                            StyledText {
                                text: "Wallpapers"
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.Bold
                                verticalAlignment: Text.AlignVCenter
                            }

                            StyledText {
                                text: {
                                    const images = root.mediaItems.filter(item => item.kind === "image").length
                                    const videos = root.mediaItems.length - images
                                    return `${images} images · ${videos} videos`
                                }
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                                opacity: 0.6
                                verticalAlignment: Text.AlignVCenter
                            }

                            Item { Layout.fillWidth: true }

                            DankActionButton {
                                iconName: "close"
                                iconSize: 18
                                buttonSize: 32
                                opacity: 0.8
                                onClicked: chooserModal.close()
                            }
                        }
                    }

                    // Compact monitor controls share the top row with live gamma.
                    Rectangle {
                        width: parent.width
                        height: 48
                        radius: 0
                        color: "transparent"
                        border.width: 0

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingS
                            anchors.rightMargin: Theme.spacingS
                            spacing: Theme.spacingS

                            Rectangle {
                                visible: root.monitors.length > 1
                                Layout.preferredWidth: visible ? 58 : 0
                                Layout.maximumWidth: visible ? 58 : 0
                                Layout.preferredHeight: 38
                                radius: Theme.cornerRadius
                                color: root.sameOnAllMonitors ? Theme.withAlpha(Theme.primary, 0.15) : Theme.withAlpha(Theme.surfaceContainerHighest, Theme.popupTransparency)
                                border.width: 1
                                border.color: root.sameOnAllMonitors ? Theme.primary : Theme.outlineHeavy

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 2
                                    DankIcon { name: "linked_services"; size: 15; color: root.sameOnAllMonitors ? Theme.primary : Theme.surfaceText; anchors.verticalCenter: parent.verticalCenter }
                                    StyledText {
                                        text: MpvPaperI18n.tr("All", "mpvpaper")
                                        font.pixelSize: Theme.fontSizeSmall * 0.9
                                        color: root.sameOnAllMonitors ? Theme.primary : Theme.surfaceText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const enabling = !root.sameOnAllMonitors
                                        if (pluginService && enabling) {
                                            const existingAllVideo = pluginService.loadPluginData("mpvpaper", "allMonitorsVideo", "")
                                            const sourceVideo = root.getCurrentVideoPath()
                                            if (!existingAllVideo && sourceVideo)
                                                pluginService.savePluginData("mpvpaper", "allMonitorsVideo", sourceVideo)
                                        }
                                        if (pluginService && !enabling && root.activeSameOnAllMonitors) {
                                            const sharedVideo = pluginService.loadPluginData("mpvpaper", "allMonitorsVideo", "")
                                            const monitorVideos = Object.assign({}, pluginService.loadPluginData("mpvpaper", "monitorVideos", {}))
                                            if (sharedVideo) {
                                                for (const monitor of root.monitors) {
                                                    if (!monitorVideos[monitor]) monitorVideos[monitor] = sharedVideo
                                                }
                                                pluginService.savePluginData("mpvpaper", "monitorVideos", monitorVideos)
                                            }
                                        }
                                        root.sameOnAllMonitors = enabling
                                        if (pluginService) {
                                            pluginService.savePluginData("mpvpaper", "allMonitorsDefault", enabling)
                                            pluginService.savePluginData("mpvpaper", "sameOnAllMonitors", root.sameOnAllMonitors)
                                        }
                                        root.refreshTrigger++
                                    }
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: root.monitors.length > 1 ? 190 : 170
                                Layout.maximumWidth: root.monitors.length > 1 ? 190 : 170
                                Layout.preferredHeight: 38
                                radius: Theme.cornerRadius
                                color: Theme.withAlpha(Theme.surfaceContainerHighest, Theme.popupTransparency)
                                border.width: 1
                                border.color: Theme.outlineHeavy
                                opacity: root.activeSameOnAllMonitors ? 0.72 : 1.0

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.spacingXS
                                    anchors.rightMargin: Theme.spacingXS
                                    spacing: 0

                                    DankActionButton {
                                        visible: root.monitors.length > 1
                                        iconName: "chevron_left"
                                        iconSize: 16
                                        buttonSize: 28
                                        enabled: !root.activeSameOnAllMonitors
                                        onClicked: root.cycleMonitor(-1)
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root.activeSameOnAllMonitors
                                            ? MpvPaperI18n.tr("All Monitors", "mpvpaper")
                                            : (root.selectedMonitor || MpvPaperI18n.tr("No Monitors", "mpvpaper"))
                                        font.pixelSize: Theme.fontSizeSmall
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        wrapMode: Text.NoWrap
                                    }
                                    DankActionButton {
                                        visible: root.monitors.length > 1
                                        iconName: "chevron_right"
                                        iconSize: 16
                                        buttonSize: 28
                                        enabled: !root.activeSameOnAllMonitors
                                        onClicked: root.cycleMonitor(1)
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                radius: height / 2
                                color: Theme.withAlpha(Theme.surfaceContainerHighest, 0.78)
                                border.width: 1
                                border.color: Theme.outlineVariant

                                Item {
                                    id: gammaPillContent
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.spacingS
                                    anchors.rightMargin: Theme.spacingS

                                    RowLayout {
                                        id: gammaPillRow
                                        anchors.fill: parent
                                        spacing: Theme.spacingXS

                                        DankIcon {
                                            name: "dark_mode"
                                            size: 16
                                            color: Theme.primary
                                        }

                                        DankSlider {
                                            id: gammaSlider
                                            Layout.fillWidth: true
                                            minimum: 0
                                            maximum: 120
                                            step: 1
                                            decimals: 2
                                            showValue: false
                                            showStops: false
                                            size: "s"
                                            trackHeight: 4
                                            // Match the slider's mouse area to the enlarged visible thumb.
                                            handleHeight: 26
                                            fillColor: Theme.primary
                                            fillTextColor: Theme.surface
                                            trackColor: Theme.withAlpha(Theme.primary, 0.34)
                                            wheelEnabled: false
                                            enabled: !!root.gammaTargetItem

                                            Binding {
                                                target: gammaSlider
                                                property: "value"
                                                value: root.sliderPositionForGamma(root.gammaSliderValue)
                                            }

                                            onSliderValueChanged: newValue => {
                                                root.updateGammaFromSlider(newValue, !isDragging)
                                            }

                                            onSliderDragFinished: finalValue => {
                                                root.updateGammaFromSlider(finalValue, true)
                                            }
                                        }

                                        DankIcon {
                                            name: "light_mode"
                                            size: 16
                                            color: Theme.primary
                                        }
                                    }

                                    Repeater {
                                        model: 36
                                        delegate: Rectangle {
                                            required property int index
                                            readonly property real gamma: 0.25 + index * 0.05
                                            readonly property real ratio: root.sliderPositionForGamma(gamma) / 120
                                            width: 2
                                            height: 2
                                            radius: 1
                                            x: gammaPillRow.x + gammaSlider.x + gammaSlider.handleWidth / 2
                                                + (gammaSlider.width - gammaSlider.handleWidth) * ratio - width / 2
                                            y: (parent.height - height) / 2
                                            z: 1
                                            color: ratio <= gammaSlider.visualRatio ? Theme.surface : Theme.primary
                                            opacity: 0.7
                                            enabled: false
                                        }
                                    }

                                    Rectangle {
                                        id: gammaThumbRing
                                        z: 2
                                        width: 26
                                        height: width
                                        radius: width / 2
                                        color: Theme.primary
                                        border.width: 3
                                        border.color: Theme.surface
                                        x: gammaPillRow.x + gammaSlider.x + gammaSlider.handleWidth / 2
                                            + (gammaSlider.width - gammaSlider.handleWidth) * gammaSlider.visualRatio - width / 2
                                        y: (parent.height - height) / 2
                                        enabled: false
                                        visible: gammaSlider.enabled
                                    }
                                }
                            }

                            StyledText {
                                text: root.gammaProcessing
                                    ? "…"
                                    : (Math.abs(root.gammaSliderValue - 1.0) < 0.001
                                        ? "1.00 · original"
                                        : `${root.gammaSliderValue.toFixed(2)} · ${root.gammaSliderValue < 1.0 ? "darker" : "lighter"}`)
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                                horizontalAlignment: Text.AlignRight
                                Layout.preferredWidth: 106
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }

                    // Video grid
                    Item {
                        id: gridContainer
                        width: parent.width
                        height: gridContainer.cellHeight * root.chooserRows
                        property real cellWidth: Math.floor(width / 4)
                        property real cellHeight: cellWidth * 9 / 16

                        GridView {
                            id: videoGrid
                            width: cellWidth * 4
                            height: cellHeight * root.chooserRows
                            anchors.centerIn: parent
                            cellWidth: gridContainer.cellWidth
                            cellHeight: gridContainer.cellHeight
                            clip: true
                            interactive: false
                            currentIndex: root.gridIndex

                            model: {
                                root.refreshTrigger
                                const media = root.mediaItems
                                const startIndex = root.currentPage * root.itemsPerPage
                                return media.slice(startIndex, startIndex + root.itemsPerPage)
                            }

                            onCountChanged: if (count > 0) currentIndex = Math.min(root.gridIndex, count - 1)
                            onCurrentIndexChanged: root.gridIndex = currentIndex

                            delegate: Item {
                                id: mediaDelegate
                                width: videoGrid.cellWidth
                                height: videoGrid.cellHeight
                                property var mediaEntry: modelData
                                property string qualityLabel: ""
                                property bool isSelected: {
                                    root.refreshTrigger
                                    return mediaEntry.kind === "video"
                                        ? root.getCurrentVideoPath() === mediaEntry.path
                                        : !root.getCurrentVideoPath() && root.getCurrentWallpaperPath() === mediaEntry.path
                                }

                                Component.onCompleted: metadataProbe.running = true

                                Process {
                                    id: metadataProbe
                                    property string probeOutput: ""
                                    command: [
                                        "ffprobe", "-v", "error", "-select_streams", "v:0",
                                        "-show_entries", "stream=width,height,avg_frame_rate",
                                        "-of", "csv=p=0:s=x", mediaEntry.path
                                    ]
                                    stdout: SplitParser {
                                        onRead: data => metadataProbe.probeOutput += data
                                    }
                                    onExited: code => {
                                        if (code === 0)
                                            mediaDelegate.qualityLabel = root.qualityLabelFor(mediaEntry.kind, probeOutput)
                                    }
                                }

                                Rectangle {
                                    anchors.fill: parent; anchors.margins: Theme.spacingXS
                                    color: Theme.withAlpha(Theme.surfaceContainerHighest, Theme.popupTransparency)
                                    radius: Theme.cornerRadius; clip: true

                                    Rectangle {
                                        anchors.fill: parent; radius: parent.radius; z: 9; color: isSelected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : "transparent"
                                        Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                                    }

                                    Rectangle {
                                        anchors.fill: parent; radius: parent.radius; z: 10; color: "transparent"; border.width: isSelected ? 3 : 0; border.color: Theme.primary
                                        Behavior on border.width { NumberAnimation { duration: Theme.shortDuration } }
                                    }

                                    Rectangle { id: maskRect; width: thumbnailImage.width; height: thumbnailImage.height; radius: Theme.cornerRadius; visible: false; layer.enabled: true }

                                    Image {
                                        id: thumbnailImage
                                        anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: true
                                        layer.enabled: true; layer.effect: MultiEffect { maskEnabled: true; maskSource: maskRect }
                                        property string mediaPath: mediaEntry.path
                                        property string mediaKind: mediaEntry.kind
                                        property string thumbnailPath: ""
                                        property string thumbnailSource: ""
                                        property string thumbnailCacheDir: ""
                                        sourceSize: Qt.size(320, 180)
                                        source: mediaKind === "image"
                                            ? root.imageFolderUrl(mediaPath)
                                            : thumbnailSource
                                        Component.onCompleted: {
                                            if (mediaKind === "video") generateThumbnail()
                                        }
                                        function generateThumbnail() {
                                            thumbnailCacheDir = StandardPaths.writableLocation(StandardPaths.GenericCacheLocation).toString().replace("file://", "") + "/DankMaterialShell/mpvpaper_thumbnails"
                                            const hash = mediaPath.split('').reduce((a, b) => {
                                                a = ((a << 5) - a) + b.charCodeAt(0)
                                                return a & a
                                            }, 0)
                                            const fileName = Math.abs(hash) + "_thumb.jpg"
                                            const cached = StandardPaths.locate(
                                                StandardPaths.GenericCacheLocation,
                                                "DankMaterialShell/mpvpaper_thumbnails/" + fileName,
                                                StandardPaths.LocateFile
                                            )
                                            thumbnailPath = thumbnailCacheDir + "/" + fileName
                                            if (cached.toString() !== "") {
                                                thumbnailSource = cached.toString()
                                                return
                                            }
                                            thumbGen.running = true
                                        }
                                        Process {
                                            id: thumbGen
                                            command: [
                                                "bash", "-c",
                                                'mkdir -p -- "$1" && ffmpeg -loglevel error -i "$2" -ss 00:00:01 -vframes 1 -vf "scale=320:180:force_original_aspect_ratio=increase,crop=320:180" -q:v 3 "$3" -y',
                                                "mpvpaper-thumbnail", thumbnailImage.thumbnailCacheDir, thumbnailImage.mediaPath, thumbnailImage.thumbnailPath
                                            ]
                                            onExited: code => {
                                                if (code === 0)
                                                    thumbnailImage.thumbnailSource = root.imageFolderUrl(thumbnailImage.thumbnailPath)
                                            }
                                        }
                                    }
                                    Loader {
                                        anchors.fill: parent
                                        active: mediaEntry.kind === "video"
                                            && root.previewedVideoPath === mediaEntry.path
                                        sourceComponent: Component {
                                            Video {
                                                anchors.fill: parent
                                                source: root.imageFolderUrl(mediaEntry.path)
                                                fillMode: VideoOutput.PreserveAspectCrop
                                                loops: MediaPlayer.Infinite
                                                volume: 0
                                                opacity: hasVideo
                                                    && playbackState === MediaPlayer.PlayingState
                                                    && error === MediaPlayer.NoError ? 1 : 0
                                                Behavior on opacity { NumberAnimation { duration: 140 } }
                                                onSourceChanged: if (source.toString() !== "") play()
                                                Component.onCompleted: play()
                                            }
                                        }
                                    }
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.margins: Theme.spacingS
                                        z: 11
                                        radius: Theme.cornerRadius
                                        color: Theme.withAlpha(Theme.surface, 0.82)
                                        width: mediaBadge.implicitWidth + Theme.spacingS
                                        height: mediaBadge.implicitHeight + 4
                                        StyledText {
                                            id: mediaBadge
                                            anchors.centerIn: parent
                                            text: mediaEntry.kind === "video" ? "VIDEO" : "IMAGE"
                                            font.pixelSize: Theme.fontSizeSmall * 0.78
                                            font.weight: Font.Bold
                                            color: Theme.primary
                                        }
                                    }
                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.margins: Theme.spacingS
                                        z: 11
                                        radius: Theme.cornerRadius
                                        color: Theme.withAlpha(Theme.surface, 0.86)
                                        width: qualityBadge.implicitWidth + Theme.spacingS * 2
                                        height: qualityBadge.implicitHeight + 6
                                        visible: qualityLabel.length > 0
                                        StyledText {
                                            id: qualityBadge
                                            anchors.centerIn: parent
                                            text: qualityLabel
                                            font.pixelSize: Theme.fontSizeSmall * 0.82
                                            font.weight: Font.Bold
                                            color: Theme.surfaceText
                                        }
                                    }
                                    DankIcon {
                                        anchors.centerIn: parent
                                        name: mediaEntry.kind === "video" ? "movie" : "image"
                                        size: 24
                                        color: Theme.primary
                                        visible: thumbnailImage.status !== Image.Ready
                                    }
                                    MouseArea {
                                        id: mediaHoverArea
                                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onEntered: {
                                            if (mediaEntry.kind === "video") previewDelay.restart()
                                        }
                                        onExited: {
                                            previewDelay.stop()
                                            if (root.previewedVideoPath === mediaEntry.path)
                                                root.previewedVideoPath = ""
                                        }
                                        onClicked: {
                                            videoGrid.currentIndex = index
                                            if (mediaEntry.kind === "video") root.setCurrentVideo(mediaEntry.path)
                                            else root.setCurrentImage(mediaEntry.path)
                                        }
                                    }
                                    Timer {
                                        id: previewDelay
                                        interval: 1000
                                        repeat: false
                                        onTriggered: {
                                            if (mediaHoverArea.containsMouse && mediaEntry.kind === "video")
                                                root.previewedVideoPath = mediaEntry.path
                                        }
                                    }

                                    Rectangle {
                                        id: trashButton
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.topMargin: Theme.spacingS
                                        anchors.rightMargin: Theme.spacingS
                                        width: 30
                                        height: 30
                                        radius: Theme.cornerRadius
                                        z: 12
                                        color: trashButtonMouse.containsMouse
                                            ? Theme.error
                                            : Theme.withAlpha(Theme.surface, 0.9)
                                        border.width: 1
                                        border.color: Theme.outlineVariant
                                        opacity: root.trashRunning ? 0.45 : 1

                                        DankIcon {
                                            anchors.centerIn: parent
                                            name: "delete"
                                            size: 17
                                            color: trashButtonMouse.containsMouse ? Theme.onError : Theme.surfaceText
                                        }

                                        MouseArea {
                                            id: trashButtonMouse
                                            anchors.fill: parent
                                            enabled: !root.trashRunning
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.moveMediaToTrash(mediaEntry)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Bottom navigation: the pager is geometrically centered;
                    // the library button is independently pinned to the right.
                    Item {
                        width: parent.width
                        height: 40

                        Row {
                            anchors.centerIn: parent
                            spacing: Theme.spacingS

                            DankActionButton {
                                iconName: "chevron_left"
                                iconSize: 18
                                buttonSize: 32
                                enabled: root.currentPage > 0
                                opacity: enabled ? 0.8 : 0.2
                                onClicked: { root.currentPage--; root.gridIndex = 0 }
                            }

                            StyledText {
                                width: 56
                                height: 32
                                text: (root.currentPage + 1) + " / " + root.totalPages
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                                opacity: 0.65
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            DankActionButton {
                                iconName: "chevron_right"
                                iconSize: 18
                                buttonSize: 32
                                enabled: root.currentPage < root.totalPages - 1
                                opacity: enabled ? 0.8 : 0.2
                                onClicked: { root.currentPage++; root.gridIndex = 0 }
                            }
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingXS

                            DankActionButton {
                                iconName: "image"
                                iconSize: 18
                                buttonSize: 32
                                opacity: 0.7
                                onClicked: imageFileBrowser.open()
                            }

                            DankActionButton {
                                iconName: "movie"
                                iconSize: 18
                                buttonSize: 32
                                opacity: 0.7
                                onClicked: root.openSystemFilePicker()
                            }
                        }
                    }
            }
        }
    }

    DModal {
        id: chooserModal
        layerNamespace: "dms:plugins:mpvpaper:chooser"
        targetScreen: root.parentScreen
        useOverlayLayer: true
        allowStacking: true
        modalWidth: Math.min(root.chooserWidth, screenWidth - Theme.spacingXL * 2)
        modalHeight: Math.min(root.chooserViewportHeight, screenHeight - Theme.spacingXL * 2)
        backgroundColor: Theme.floatingWindowSurface
        borderWidth: 1
        enableShadow: true
        content: popoutBody
        onBackgroundClicked: close()
        onOpened: {
            root.fileBrowserParentPopout = chooserModal
            root.previewedVideoPath = ""
        }
        onDialogClosed: {
            root.previewedVideoPath = ""
            if (root.fileBrowserParentPopout === chooserModal)
                root.fileBrowserParentPopout = null
        }
    }

    pillClickAction: function(x, y, width, section, screen) {
        if (chooserModal.shouldBeVisible) {
            chooserModal.close()
            return
        }

        root.previewedVideoPath = ""
        root.syncSelectionToPlayback()
        chooserModal.open()
    }

    popoutWidth: chooserWidth
    popoutHeight: chooserHeight
}
