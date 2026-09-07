import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins

PluginComponent {
    id: root
    pluginId: "mpvpaper"

    // Follow DMS's actual shell lock state. SessionService.locked is a
    // loginctl hint and may remain stale even when no lock surface exists.
    property bool isLocked: IdleService.isShellLocked
    
    onIsLockedChanged: {
        if (isLocked) {
            console.info("MpvPaper: Screen locked - stopping all videos")
            stopAllVideos()
        } else {
            console.info("MpvPaper: Screen unlocked - restoring videos")
            // 使用一个小延迟确保屏幕状态已完全恢复
            Qt.callLater(() => {
                if (!isLocked) syncVideosWithData()
            })
        }
    }

    function stopAllVideos() {
        // 停止所有重启定时器
        for (const monitor in restartTimers) {
            stopRestartTimer(monitor)
        }

        // 停止所有进程对象
        for (const monitor in processes) {
            if (processes[monitor]) {
                processes[monitor].stopping = true
                processes[monitor].running = false
                processes[monitor].destroy()
                delete processes[monitor]
            }
        }
        processes = ({})
    }

    property var monitorVideos: pluginData.monitorVideos || {}
    property bool sameOnAllMonitors: pluginData.sameOnAllMonitors || false
    property string allMonitorsVideo: pluginData.allMonitorsVideo || ""
    property var processes: ({})
    property var previousScreenNames: []
    property bool ready: false
    property var pendingLaunches: ({})
    property bool isSyncing: false
    property var restartTimers: ({})  // 每个显示器的重启定时器
    property var recoveryTimers: ({})
    property var stabilityTimers: ({})
    property var recoveryAttempts: ({})
    property var recoveryKeys: ({})
    property int maxRecoveryAttempts: 5
    property int restartInterval: (pluginData.restartInterval || 60) * 60000 // 默认60分钟，转为毫秒

    // --- Wallpaper palette update ---
    // Cache directory for extracted still frames used by matugen
    readonly property string stillFrameCacheDir: StandardPaths.writableLocation(StandardPaths.GenericCacheLocation).toString().replace("file://", "") + "/DankMaterialShell/mpvpaper_stills"
    property string lastPaletteVideoPath: ""

    onPluginDataChanged: {
        MpvPaperI18n.language = pluginData.language || "en"
        if (ready && !isSyncing) {
            // Update restart interval if changed
            const newInterval = (pluginData.restartInterval || 60) * 60000
            if (newInterval !== restartInterval) {
                restartInterval = newInterval
                console.info("MpvPaper: Restart interval changed to", pluginData.restartInterval, "minutes")
                // Re-setup all timers
                for (const monitor in restartTimers) {
                    setupRestartTimer(monitor)
                }
            }
            syncDebounce.restart()
        }
    }

    Timer {
        id: syncDebounce
        interval: 50
        repeat: false
        onTriggered: syncVideosWithData()
    }

    // Watch for display hotplug events
    Connections {
        target: Quickshell

        function onScreensChanged() {
            const currentScreenNames = Quickshell.screens.map(screen => screen.name)

            // Find disconnected screens and stop their processes
            const removedScreens = previousScreenNames.filter(name => !currentScreenNames.includes(name))
            for (const screenName of removedScreens) {
                if (processes[screenName]) {
                    console.info("MpvPaper: Display disconnected:", screenName, "- stopping video")
                    stopMpvPaper(screenName, false, "")
                }
            }

            // Find newly connected screens and restore their videos
            const newScreens = currentScreenNames.filter(name => !previousScreenNames.includes(name))
            for (const screenName of newScreens) {
                const videoPath = getEffectiveVideo(screenName)
                if (!isLocked && videoPath) {
                    console.info("MpvPaper: Display connected:", screenName, "- restoring video:", videoPath)
                    launchMpvPaper(screenName, videoPath)
                }
            }

            previousScreenNames = currentScreenNames
        }
    }

    function deepEqual(a, b) {
        if (a === b) return true
        if (a === null || b === null) return false
        if (typeof a !== "object" || typeof b !== "object") return false

        const aIsArray = Array.isArray(a)
        const bIsArray = Array.isArray(b)
        if (aIsArray !== bIsArray) return false

        const aKeys = Object.keys(a)
        const bKeys = Object.keys(b)
        if (aKeys.length !== bKeys.length) return false

        for (let i = 0; i < aKeys.length; ++i) {
            const key = aKeys[i]
            if (!b.hasOwnProperty(key)) return false
            if (!deepEqual(a[key], b[key])) return false
        }

        return true
    }

    function migrateLegacyVideoLibrary() {
        const canSave = pluginService && pluginService.savePluginData
        const existingLibrary = Array.isArray(pluginData.videoLibrary) ? pluginData.videoLibrary : []
        const library = []

        for (const path of existingLibrary) {
            if (path && library.indexOf(path) === -1) library.push(path)
        }

        const legacyPlaylists = pluginData.monitorPlaylists || {}
        const legacyIndices = pluginData.playlistIndices || {}
        const videos = Object.assign({}, pluginData.monitorVideos || {})

        for (const monitor in legacyPlaylists) {
            const list = legacyPlaylists[monitor]
            if (!Array.isArray(list)) continue

            for (const path of list) {
                if (path && library.indexOf(path) === -1) library.push(path)
            }

            if (list.length > 0) {
                let index = legacyIndices[monitor] ?? 0
                if (index < 0 || index >= list.length) index = 0
                if (list[index]) videos[monitor] = list[index]
            }
        }

        for (const monitor in videos) {
            const path = videos[monitor]
            if (path && library.indexOf(path) === -1) library.push(path)
        }

        if (!deepEqual(existingLibrary, library)) {
            pluginData.videoLibrary = library
            if (canSave) pluginService.savePluginData(pluginId, "videoLibrary", library)
        }

        if (!deepEqual(pluginData.monitorVideos || {}, videos)) {
            pluginData.monitorVideos = videos
            if (canSave) pluginService.savePluginData(pluginId, "monitorVideos", videos)
        }

        if (Object.keys(legacyPlaylists).length > 0) {
            pluginData.monitorPlaylists = {}
            if (canSave) pluginService.savePluginData(pluginId, "monitorPlaylists", {})
        }
        if (Object.keys(legacyIndices).length > 0) {
            pluginData.playlistIndices = {}
            if (canSave) pluginService.savePluginData(pluginId, "playlistIndices", {})
        }
    }

    function getEffectiveVideo(monitor) {
        if (sameOnAllMonitors && allMonitorsVideo) return allMonitorsVideo
        return monitorVideos[monitor] || ""
    }

    function syncVideosWithData() {
        if (isLocked) {
            console.info("MpvPaper: Screen is locked, skipping video sync")
            return
        }
        if (isSyncing) {
            console.warn("MpvPaper: Sync already in progress, skipping")
            return
        }

        isSyncing = true
        if (Object.keys(pluginData.monitorPlaylists || {}).length > 0 || Object.keys(pluginData.playlistIndices || {}).length > 0) {
            migrateLegacyVideoLibrary()
        }
        monitorVideos = pluginData.monitorVideos || {}
        sameOnAllMonitors = pluginData.sameOnAllMonitors || false
        allMonitorsVideo = pluginData.allMonitorsVideo || ""

        const connectedMonitors = Quickshell.screens.map(screen => screen.name)
        console.info("MpvPaper: Syncing videos. Connected monitors:", JSON.stringify(connectedMonitors))

        for (const monitor of connectedMonitors) {
            const newVideoPath = getEffectiveVideo(monitor)
            const oldVideoPath = processes[monitor] ? processes[monitor].videoPath : ""

            if (!newVideoPath) {
                if (processes[monitor]) stopMpvPaper(monitor, false, "")
                continue
            }

            const newSettings = getEffectiveSettings(newVideoPath)
            const oldSettings = processes[monitor] ? processes[monitor].settings : null
            const videoChanged = newVideoPath !== oldVideoPath
            const settingsChanged = !deepEqual(newSettings || {}, oldSettings || {})
            const processNotRunning = !processes[monitor]
            const isPending = pendingLaunches[monitor]

            console.info("MpvPaper: Monitor", monitor, "- videoChanged:", videoChanged, "settingsChanged:", settingsChanged, "processNotRunning:", processNotRunning, "isPending:", isPending, "processExists:", !!processes[monitor], "processKeys:", Object.keys(processes))

            if ((videoChanged || settingsChanged || processNotRunning) && !isPending) {
                try {
                    launchMpvPaper(monitor, newVideoPath)
                } catch (e) {
                    console.error("MpvPaper: Failed to launch for", monitor, ":", e)
                }
            }
        }

        isSyncing = false
    }

    function launchMpvPaper(monitor, videoPath) {
        if (isLocked || !videoPath) {
            console.info("MpvPaper: Refusing launch while locked or without a video for", monitor)
            return
        }

        const recoveryKey = videoPath + "\n" + JSON.stringify(getEffectiveSettings(videoPath) || {})
        if (recoveryKeys[monitor] !== recoveryKey) {
            resetRecovery(monitor)
            const keys = Object.assign({}, recoveryKeys)
            keys[monitor] = recoveryKey
            recoveryKeys = keys
        }

        // Prevent duplicate launches
        if (pendingLaunches[monitor]) {
            console.warn("MpvPaper: Launch already pending for", monitor, "- skipping")
            return
        }
        
        const pending = Object.assign({}, pendingLaunches)
        pending[monitor] = true
        pendingLaunches = pending
        
        console.info("MpvPaper: Launching video for", monitor, ":", videoPath)
        stopMpvPaper(monitor, true, videoPath)
        
        // 设置重启定时器
        setupRestartTimer(monitor)
    }

    function getVideoSettings(videoPath) {
        var allSettings = pluginData.videoSettings || {}
        return allSettings[videoPath] || {}
    }

    function getEffectiveSettings(videoPath) {
        const settings = Object.assign({}, getVideoSettings(videoPath))
        settings.disableUserScripts = pluginData.disableUserScripts !== undefined ? pluginData.disableUserScripts : true
        settings.customMpvOptions = pluginData.customMpvOptions || ""
        return settings
    }

    function stopMpvPaper(monitor, startNew, newVideoPath) {
        if (startNew === undefined) startNew = false
        if (newVideoPath === undefined) newVideoPath = ""

        console.info("MpvPaper: Stopping video for", monitor, "startNew:", startNew)

        if (processes[monitor]) {
            processes[monitor].stopping = true
            processes[monitor].running = false
            processes[monitor].destroy()
            const procs = Object.assign({}, processes)
            delete procs[monitor]
            processes = procs
        }
        
        // 停止重启定时器
        stopRestartTimer(monitor)

        if (startNew) {
            var delay = launchDelayComponent.createObject(root, {
                monitor: monitor,
                videoPath: newVideoPath
            })
            delay.start()
        } else {
            const pending = Object.assign({}, pendingLaunches)
            delete pending[monitor]
            pendingLaunches = pending
        }
    }

    Component {
        id: mpvProcessComponent

        Process {
            id: mpvProc

            property string monitor: ""
            property string videoPath: ""
            property var settings: ({})
            property bool stopping: false

            command: {
                var args = [
                    "mpvpaper",
                    "-l", "background"
                ]

                var mpvOptions = []
                
                // Loop video
                mpvOptions.push("loop")
                
                // Hardware decoding - force it
                var hwdec = settings.hwdec || "auto"
                if (hwdec !== "no") {
                    mpvOptions.push("--hwdec=" + hwdec)
                }
                mpvOptions.push("--hwdec-codecs=all")
                
                // Video output - use GPU
                mpvOptions.push("--vo=gpu")
                mpvOptions.push("--gpu-api=auto")
                mpvOptions.push("--gpu-context=auto")
                
                // Reduce CPU usage significantly
                mpvOptions.push("--profile=fast")
                mpvOptions.push("--video-sync=display-resample")
                mpvOptions.push("--interpolation=no")
                mpvOptions.push("--scale=bilinear")
                mpvOptions.push("--cscale=bilinear")
                mpvOptions.push("--dscale=bilinear")
                mpvOptions.push("--correct-downscaling=no")
                mpvOptions.push("--linear-downscaling=no")
                mpvOptions.push("--sigmoid-upscaling=no")
                
                // Thread optimization
                mpvOptions.push("--vd-lavc-threads=1")
                
                // Cache settings - DISABLED for local files to save memory
                mpvOptions.push("--cache=no")
                mpvOptions.push("--demuxer-max-bytes=10M")
                mpvOptions.push("--demuxer-readahead-secs=1")
                
                // Memory optimization
                mpvOptions.push("--vd-lavc-dr=yes")
                mpvOptions.push("--opengl-pbo")
                mpvOptions.push("--swapchain-depth=1") // 减少缓冲区深度
                
                // Disable unnecessary features
                mpvOptions.push("--no-audio-display")
                mpvOptions.push("--no-osc")
                mpvOptions.push("--no-osd-bar")
                mpvOptions.push("--no-input-default-bindings")
                mpvOptions.push("--no-input-cursor")
                mpvOptions.push("--cursor-autohide=no")
                mpvOptions.push("--no-keepaspect-window")

                if (settings.disableUserScripts !== false) {
                    mpvOptions.push("--load-scripts=no")
                }
                
                // Panscan setting
                var panscan = settings.panscan
                if (panscan === undefined || panscan === null) {
                    panscan = 1.0
                }
                mpvOptions.push("--panscan=" + panscan)
                
                // Volume setting
                var volume = settings.volume
                if (volume === undefined || volume === null) {
                    volume = 0
                }
                mpvOptions.push("--volume=" + volume)

                const customMpvOptions = (settings.customMpvOptions || "").trim()
                if (customMpvOptions) {
                    mpvOptions.push(customMpvOptions)
                }

                if (mpvOptions.length > 0) {
                    args.push("-o")
                    args.push(mpvOptions.join(" "))
                }

                args.push(monitor)
                args.push(videoPath)

                return args
            }

            onExited: (code) => {
                const procs = Object.assign({}, processes)
                if (procs[monitor] === mpvProc) {
                    delete procs[monitor]
                    processes = procs
                }

                if (!stopping && code !== 0) {
                    console.warn("MpvPaper: Process exited with code:", code, "for video", videoPath, "on", monitor)
                    ToastService.showError(MpvPaperI18n.tr("MpvPaper Error", "mpvpaper"), MpvPaperI18n.tr("Video playback failed on %1", "mpvpaper").arg(monitor))
                }

                if (!stopping && !isLocked && getEffectiveVideo(monitor)) {
                    scheduleRecovery(monitor, videoPath, settings)
                }
            }
        }
    }

    Component {
        id: launchDelayComponent

        Timer {
            id: launchDelay
            property string monitor: ""
            property string videoPath: ""
            interval: 150
            repeat: false

            onTriggered: {
                const pending = Object.assign({}, pendingLaunches)
                if (!isLocked && videoPath) {
                    var videoSettings = getEffectiveSettings(videoPath)
                    console.info("MpvPaper: Creating new process for", monitor, "video:", videoPath)

                    var mpvProc = mpvProcessComponent.createObject(root, {
                        monitor: launchDelay.monitor,
                        videoPath: launchDelay.videoPath,
                        settings: videoSettings
                    })

                    const procs = Object.assign({}, processes)
                    procs[monitor] = mpvProc
                    processes = procs
                    mpvProc.running = true
                    scheduleStabilityReset(monitor, videoPath, videoSettings)

                    console.info("MpvPaper: Process started for", monitor)

                    // Extract a still frame and update the DMS wallpaper palette
                    root.updateWallpaperPalette(monitor, videoPath)
                }
                delete pending[monitor]
                pendingLaunches = pending
                destroy()
            }
        }
    }

    Component {
        id: recoveryTimerComponent

        Timer {
            property string monitor: ""
            interval: 1500
            repeat: false
            onTriggered: {
                const timers = Object.assign({}, recoveryTimers)
                delete timers[monitor]
                recoveryTimers = timers
                destroy()
                if (!isLocked) syncVideosWithData()
            }
        }
    }

    function scheduleRecovery(monitor, videoPath, settings) {
        if (recoveryTimers[monitor]) return

        const key = videoPath + "\n" + JSON.stringify(settings || {})
        if (recoveryKeys[monitor] !== key) {
            resetRecovery(monitor)
            const keys = Object.assign({}, recoveryKeys)
            keys[monitor] = key
            recoveryKeys = keys
        }

        const attempt = (recoveryAttempts[monitor] || 0) + 1
        const attempts = Object.assign({}, recoveryAttempts)
        attempts[monitor] = attempt
        recoveryAttempts = attempts

        if (attempt > maxRecoveryAttempts) {
            console.error("MpvPaper: Giving up recovery for", monitor, "after", maxRecoveryAttempts, "attempts")
            ToastService.showError(MpvPaperI18n.tr("MpvPaper Error", "mpvpaper"), MpvPaperI18n.tr("Video playback failed on %1", "mpvpaper").arg(monitor))
            return
        }

        const delay = 1500 * Math.pow(2, attempt - 1)
        console.warn("MpvPaper: Scheduling recovery", attempt, "of", maxRecoveryAttempts, "for", monitor, "in", delay, "ms")
        const timer = recoveryTimerComponent.createObject(root, {
            monitor: monitor,
            interval: delay
        })
        const timers = Object.assign({}, recoveryTimers)
        timers[monitor] = timer
        recoveryTimers = timers
        timer.start()
    }

    function resetRecovery(monitor) {
        if (recoveryTimers[monitor]) {
            recoveryTimers[monitor].stop()
            recoveryTimers[monitor].destroy()
        }
        const timers = Object.assign({}, recoveryTimers)
        const attempts = Object.assign({}, recoveryAttempts)
        const keys = Object.assign({}, recoveryKeys)
        delete timers[monitor]
        delete attempts[monitor]
        delete keys[monitor]
        recoveryTimers = timers
        recoveryAttempts = attempts
        recoveryKeys = keys
    }

    Component {
        id: stabilityTimerComponent

        Timer {
            property string monitor: ""
            property string recoveryKey: ""
            interval: 30000
            repeat: false
            onTriggered: {
                const timers = Object.assign({}, stabilityTimers)
                delete timers[monitor]
                stabilityTimers = timers
                destroy()
                if (recoveryKeys[monitor] === recoveryKey && processes[monitor]) {
                    console.info("MpvPaper: Playback stable on", monitor, "- clearing recovery count")
                    const attempts = Object.assign({}, recoveryAttempts)
                    delete attempts[monitor]
                    recoveryAttempts = attempts
                }
            }
        }
    }

    function scheduleStabilityReset(monitor, videoPath, settings) {
        if (stabilityTimers[monitor]) {
            stabilityTimers[monitor].stop()
            stabilityTimers[monitor].destroy()
        }
        const key = videoPath + "\n" + JSON.stringify(settings || {})
        const timer = stabilityTimerComponent.createObject(root, {
            monitor: monitor,
            recoveryKey: key
        })
        const timers = Object.assign({}, stabilityTimers)
        timers[monitor] = timer
        stabilityTimers = timers
        timer.start()
    }

    // --- Still frame extraction for palette update ---
    function updateWallpaperPalette(monitor, videoPath) {
        // Whichever monitor changes video most recently becomes
        // the source for the global Dynamic palette.
        // Don't re-extract if the video hasn't changed
        if (videoPath === lastPaletteVideoPath) {
            console.info("MpvPaper: Palette already up-to-date for", videoPath)
            return
        }
        lastPaletteVideoPath = videoPath

        // Build a deterministic filename from the video path
        var hash = videoPath.split('').reduce((a, b) => { a = ((a << 5) - a) + b.charCodeAt(0); return a & a }, 0)
        var stillPath = stillFrameCacheDir + "/" + Math.abs(hash) + "_still.png"

        console.info("MpvPaper: Extracting still frame for palette from", videoPath, "to", stillPath)

        var extractor = stillFrameExtractorComponent.createObject(root, {
            videoPath: videoPath,
            outputPath: stillPath
        })
        extractor.running = true
    }

    Component {
        id: stillFrameExtractorComponent

        Process {
            id: extractorProc
            property string videoPath: ""
            property string outputPath: ""

            command: [
                "bash", "-c",
                'mkdir -p -- "$1" && ffmpeg -loglevel error -i "$2" -ss 00:00:02 -vframes 1 -vf "scale=1280:-1" -q:v 2 "$3" -y',
                "mpvpaper-still",
                root.stillFrameCacheDir,
                videoPath,
                outputPath
            ]

            onExited: (code) => {
                if (code === 0) {
                    console.info("MpvPaper: Still frame extracted, updating DMS wallpaper palette:", outputPath)
                    // Generate the Dynamic theme directly from the extracted frame.
                    // This keeps DMS per-monitor wallpaper assignments untouched.
                    if (typeof Theme !== "undefined" && Theme.currentTheme === Theme.dynamic) {
                        const isLight = typeof SessionData !== "undefined"
                            ? SessionData.isLightMode
                            : false
                        const iconTheme = typeof SettingsData !== "undefined" && SettingsData.iconTheme
                            ? SettingsData.iconTheme
                            : "System Default"
                        const matugenType = typeof SettingsData !== "undefined" && SettingsData.matugenScheme
                            ? SettingsData.matugenScheme
                            : "scheme-tonal-spot"

                        Theme.setDesiredTheme("image", outputPath, isLight, iconTheme, matugenType)
                    }
                } else {
                    console.warn("MpvPaper: Failed to extract still frame (exit code:", code, ") from", videoPath)
                }
                destroy()
            }
        }
    }

    Component.onCompleted: {
        MpvPaperI18n.language = pluginData.language || "en"
        migrateLegacyVideoLibrary()

        previousScreenNames = Quickshell.screens.map(screen => screen.name)
        console.info("MpvPaper Daemon: Starting...")

        // Clear any stale process references
        processes = {}
        pendingLaunches = {}
        recoveryTimers = {}
        stabilityTimers = {}
        recoveryAttempts = {}
        recoveryKeys = {}
        
        ready = true
        syncVideosWithData()
    }

    function setupRestartTimer(monitor) {
        // 停止现有的定时器
        stopRestartTimer(monitor)
        
        // 如果重启间隔为0，则不设置定时器（禁用自动重启）
        if (restartInterval <= 0) {
            console.info("MpvPaper: Auto-restart disabled for", monitor)
            return
        }
        
        const timer = restartTimerComponent.createObject(root, {
            monitor: monitor,
            interval: restartInterval
        })
        const timers = Object.assign({}, restartTimers)
        timers[monitor] = timer
        restartTimers = timers
        timer.start()
        console.info("MpvPaper: Set up restart timer for", monitor, "- will restart in", restartInterval/1000/60, "minutes")
    }

    Component {
        id: restartTimerComponent

        Timer {
            property string monitor: ""
            repeat: false
            onTriggered: {
                const videoPath = root.getEffectiveVideo(monitor)
                if (!isLocked && videoPath) {
                    console.info("MpvPaper: Restarting video for", monitor, ":", videoPath)
                    root.launchMpvPaper(monitor, videoPath)
                }
            }
        }
    }
    
    function stopRestartTimer(monitor) {
        if (restartTimers[monitor]) {
            restartTimers[monitor].stop()
            restartTimers[monitor].destroy()
            delete restartTimers[monitor]
        }
    }

    Component.onDestruction: {
        console.info("MpvPaper Daemon: Stopping, cleaning up processes")

        // 停止所有重启定时器
        for (const monitor in restartTimers) {
            if (restartTimers[monitor]) {
                restartTimers[monitor].stop()
                restartTimers[monitor].destroy()
            }
        }

        for (const monitor in recoveryTimers) {
            if (recoveryTimers[monitor]) {
                recoveryTimers[monitor].stop()
                recoveryTimers[monitor].destroy()
            }
        }


        for (const monitor in stabilityTimers) {
            if (stabilityTimers[monitor]) {
                stabilityTimers[monitor].stop()
                stabilityTimers[monitor].destroy()
            }
        }

        for (const monitor in processes) {
            if (processes[monitor]) {
                processes[monitor].stopping = true
                processes[monitor].running = false
                processes[monitor].destroy()
            }
        }
    }
}
