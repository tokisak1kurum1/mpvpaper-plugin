import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins
import "./translations.js" as Translations

PluginComponent {
    id: root
    pluginId: "mpvpaper"

    property bool isLocked: SessionService.locked
    
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
                processes[monitor].running = false
                processes[monitor].destroy()
                delete processes[monitor]
            }
        }

        // 强制杀掉所有 mpvpaper 进程
        Quickshell.execDetached([
            "bash", "-c",
            "pkill -9 -f 'mpvpaper' 2>/dev/null || true"
        ])
    }

    property var monitorVideos: pluginData.monitorVideos || {}
    property var monitorPlaylists: pluginData.monitorPlaylists || {}
    property var processes: ({})
    property var previousScreenNames: []
    property var playlistIndices: pluginData.playlistIndices || {}
    property bool ready: false
    property var pendingLaunches: ({})
    property bool isSyncing: false
    property var restartTimers: ({})  // 每个显示器的重启定时器
    property int restartInterval: (pluginData.restartInterval || 60) * 60000 // 默认60分钟，转为毫秒

    onPluginDataChanged: {
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
                if (videoPath) {
                    console.info("MpvPaper: Display connected:", screenName, "- restoring video:", videoPath)
                    launchMpvPaper(screenName, videoPath)
                }
            }

            previousScreenNames = currentScreenNames
        }
    }

    function escapeRegex(str) {
        return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
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

    function getEffectiveVideo(monitor) {
        const playlist = monitorPlaylists[monitor]
        if (playlist && Array.isArray(playlist) && playlist.length > 0) {
            let idx = playlistIndices[monitor]
            if (idx === undefined) {
                idx = 0
                const indices = Object.assign({}, playlistIndices)
                indices[monitor] = idx
                playlistIndices = indices
            }
            if (idx < 0 || idx >= playlist.length) {
                idx = 0
            }
            return playlist[idx]
        }
        return (pluginData.monitorVideos || {})[monitor] || ""
    }

    function syncVideosWithData() {
        if (isSyncing) {
            console.warn("MpvPaper: Sync already in progress, skipping")
            return
        }
        
        isSyncing = true
        
        // Refresh data from pluginData to ensure we have the latest from widget
        monitorVideos = pluginData.monitorVideos || {}
        monitorPlaylists = pluginData.monitorPlaylists || {}
        playlistIndices = pluginData.playlistIndices || {}
        
        const connectedMonitors = Quickshell.screens.map(screen => screen.name)
        console.info("MpvPaper: Syncing videos. Connected monitors:", JSON.stringify(connectedMonitors))
        const effectiveVideos = {}
        for (const monitor of connectedMonitors) {
            const video = getEffectiveVideo(monitor)
            if (video) effectiveVideos[monitor] = video
        }

        for (const monitor in monitorVideos) {
            if (!effectiveVideos.hasOwnProperty(monitor) && !(monitorPlaylists[monitor] && monitorPlaylists[monitor].length > 0)) {
                stopMpvPaper(monitor, false, "")
            }
        }

        const newVideos = Object.assign({}, pluginData.monitorVideos || {})
        let needsLaunch = false
        
        for (const monitor of connectedMonitors) {
            const newVideoPath = effectiveVideos[monitor]
            const oldVideoPath = processes[monitor] ? processes[monitor].videoPath : ""

            if (!newVideoPath) {
                if (processes[monitor]) {
                    stopMpvPaper(monitor, false, "")
                }
                continue
            }

            newVideos[monitor] = newVideoPath
            const newSettings = getVideoSettings(newVideoPath)

            let oldSettings = null
            if (processes[monitor] && processes[monitor].videoPath === oldVideoPath) {
                oldSettings = processes[monitor].settings
            }

            const videoChanged = newVideoPath !== oldVideoPath
            const settingsChanged = !deepEqual(newSettings || {}, oldSettings || {})
            const processNotRunning = !processes[monitor]
            const isPending = pendingLaunches[monitor]

            console.info("MpvPaper: Monitor", monitor, "- videoChanged:", videoChanged, "settingsChanged:", settingsChanged, "processNotRunning:", processNotRunning, "isPending:", isPending, "processExists:", !!processes[monitor], "processKeys:", Object.keys(processes))

            if ((videoChanged || settingsChanged || processNotRunning) && !isPending) {
                try {
                    launchMpvPaper(monitor, newVideoPath)
                    needsLaunch = true
                } catch (e) {
                    console.error("MpvPaper: Failed to launch for", monitor, ":", e)
                }
            }
        }

        // Only save if data actually changed
        const dataChanged = !deepEqual(pluginData.monitorVideos || {}, newVideos)
        if (dataChanged && !needsLaunch) {
            pluginData.monitorVideos = newVideos
            if (pluginService && pluginService.savePluginData) {
                pluginService.savePluginData(pluginId, "monitorVideos", newVideos)
            }
        }
        monitorVideos = newVideos
        
        isSyncing = false
    }

    function launchMpvPaper(monitor, videoPath) {
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

    function stopMpvPaper(monitor, startNew, newVideoPath) {
        if (startNew === undefined) startNew = false
        if (newVideoPath === undefined) newVideoPath = ""

        console.info("MpvPaper: Stopping video for", monitor, "startNew:", startNew)

        if (processes[monitor]) {
            processes[monitor].running = false
            processes[monitor].destroy()
            delete processes[monitor]
        }
        
        // 停止重启定时器
        stopRestartTimer(monitor)

        var killerProc = killerComponent.createObject(root, {
            monitor: monitor,
            startNew: startNew,
            newVideoPath: newVideoPath
        })
        killerProc.running = true
    }

    Component {
        id: mpvProcessComponent

        Process {
            id: mpvProc

            property string monitor: ""
            property string videoPath: ""
            property var settings: ({})

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

                if (mpvOptions.length > 0) {
                    args.push("-o")
                    args.push(mpvOptions.join(" "))
                }

                args.push(monitor)
                args.push(videoPath)

                return args
            }

            onExited: (code) => {
                if (code !== 0) {
                    console.warn("MpvPaper: Process exited with code:", code, "for video", videoPath, "on", monitor)
                    ToastService.showError(I18n.tr("MpvPaper Error", "mpvpaper"), I18n.tr("Video playback failed on %1", "mpvpaper").arg(monitor))
                }
            }
        }
    }

    Component {
        id: killerComponent

        Process {
            property string monitor: ""
            property bool startNew: false
            property string newVideoPath: ""

            command: [
                "bash", "-c",
                "pkill -9 -f 'mpvpaper.*" + escapeRegex(monitor) + "' 2>/dev/null; sleep 0.1; exit 0"
            ]

            onExited: () => {
                console.info("MpvPaper: Killer process finished for", monitor, "startNew:", startNew)
                
                const pending = Object.assign({}, pendingLaunches)
                if (!startNew) {
                    delete pending[monitor]
                    pendingLaunches = pending
                }
                if (startNew) {
                    var videoSettings = getVideoSettings(newVideoPath)
                    console.info("MpvPaper: Creating new process for", monitor, "video:", newVideoPath)
                    
                    var mpvProc = mpvProcessComponent.createObject(root, {
                        monitor: monitor,
                        videoPath: newVideoPath,
                        settings: videoSettings
                    })

                    const procs = Object.assign({}, processes)
                    procs[monitor] = mpvProc
                    processes = procs
                    mpvProc.running = true
                    
                    console.info("MpvPaper: Process started for", monitor)
                    delete pending[monitor]
                    pendingLaunches = pending
                }

                destroy()
            }
        }
    }

    Component.onCompleted: {
        // Inject translations into global I18n singleton
        Translations.inject(I18n)

        previousScreenNames = Quickshell.screens.map(screen => screen.name)
        console.info("MpvPaper Daemon: Starting...")
        
        // Clear any stale process references
        processes = {}
        pendingLaunches = {}
        
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
        
        // 创建新的定时器
        const timer = Qt.createQmlObject(`
            import QtQuick
            Timer {
                interval: ${restartInterval}
                repeat: false
                running: true
                onTriggered: {
                    console.info("MpvPaper: Restart timer triggered for", "${monitor}")
                    // 重启进程
                    const videoPath = root.getEffectiveVideo("${monitor}")
                    if (videoPath) {
                        console.info("MpvPaper: Restarting video for", "${monitor}", ":", videoPath)
                        root.launchMpvPaper("${monitor}", videoPath)
                    }
                }
            }
        `, root)
        
        restartTimers[monitor] = timer
        console.info("MpvPaper: Set up restart timer for", monitor, "- will restart in", restartInterval/1000/60, "minutes")
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

        for (const monitor in processes) {
            if (processes[monitor]) {
                processes[monitor].running = false
                processes[monitor].destroy()
            }
        }

        for (const monitor in monitorVideos) {
            Quickshell.execDetached([
                "bash", "-c",
                "pkill -9 -f 'mpvpaper.*" + escapeRegex(monitor) + "' 2>/dev/null || true"
            ])
        }
    }
}
