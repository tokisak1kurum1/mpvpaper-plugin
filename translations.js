/**
 * MpvPaper Plugin Translations
 * This file is dynamically injected into the global I18n singleton at runtime.
 */

const translations = {
    "zh_CN": {
        "mpvpaper": {
            "MpvPaper Plugin": "MpvPaper 插件",
            "MPV Wallpaper": "MpvPaper 插件",
            "Video wallpaper using mpvpaper": "本插件基于 mpvpaper 提供底层的视频动态壁纸支持",
            "Monitor": "当前控制显示器",
            "No Monitors": "未检测到显示器",
            "Video List (%1 videos)": "播放列表 (共 %1 个视频)",
            "Video List (Empty)": "播放列表 (暂无视频)",
            "Add videos to the list and select a playback mode": "在此管理您的视频壁纸库",
            "Add Video": "添加视频",
            "Add Folder": "添加文件夹",
            "Clear List": "清空列表",
            "Video Settings": "画面设置",
            "Hardware Decoding": "GPU 硬件加速",
            "Hardware acceleration method for video decoding": "建议选择 auto 以降低 CPU 占用",
            "Tiling Mode": "画面填充方式",
            "Fill Screen (Crop)": "全屏填充 (裁剪)",
            "Fit Screen (Letterbox)": "比例优先 (留黑边)",
            "Stretch Fill": "拉伸填充 (铺满)",
            "Choose how the video fits the screen size": "设置视频如何适应屏幕尺寸",
            "Volume": "播放音量",
            "Audio volume (0 = Mute)": "设置视频背景音量 (0 为静音)",
            "Scheduled Restart Interval": "自动重载间隔",
            "Disabled": "已禁用",
            "10 Minutes": "10 分钟",
            "30 Minutes": "30 分钟",
            "1 Hour": "1 小时",
            "2 Hours": "2 小时",
            "Periodically restart mpv process to prevent potential memory leaks": "定时重启进程以解决 mpvpaper 长时间运行导致的内存占用持续增长（内存泄漏）问题",
            "Select Video Files": "选择视频文件",
            "Video Files": "视频文件",
            "All Files": "所有文件",
            "Video Added": "视频已添加",
            "Successfully added %1 videos": "成功添加了 %1 个视频",
            "Select Video Folder": "选择视频文件夹",
            "Folder Added": "文件夹已添加",
            "Added %1 videos from directory": "从目录中导入了 %1 个视频",
            "No Videos Found": "未找到视频",
            "No supported video files found in selected folder": "所选文件夹中没有支持的视频格式",
            "Select Video to Add to Playlist": "选择视频添加到列表",
            "Select Video": "选择视频文件",
            "Close": "关闭",
            "Back": "返回",
            "Home": "主目录",
            "Videos": "视频",
            "Downloads": "下载",
            "Enter path...": "输入路径...",
            "Go": "前往",
            "Root": "根目录",
            "Search current directory...": "搜索当前目录...",
            "Refresh": "刷新",
            "%1 folders, %2 videos": "%1 个文件夹，%2 个视频",
            "Folder": "文件夹",
            "Video File": "视频文件",
            "No matching items": "没有匹配的项目",
            "This directory is empty": "此目录为空",
            "Video Wallpaper": "视频壁纸",
            "No Wallpapers": "暂无壁纸",
            "%1 Wallpapers • Page %2/%3": "共 %1 个壁纸 • 第 %2/%3 页",
            "Page %1/%2": "第 %1/%2 页",
            "MpvPaper Error": "播放器异常",
            "Video playback failed on %1": "显示器 %1 上的视频播放失败",
            "Play videos as desktop wallpapers with multi-monitor support and playlist management.": "高性能桌面视频壁纸插件，支持多显示器和播放列表管理。",
            "Language": "语言"
            ,"Simplified Chinese": "简体中文"
            ,"English": "English"
        }
    }
}

function tr(language, term) {
    if (language !== "zh_CN") return term;
    const table = translations.zh_CN.mpvpaper;
    return table[term] || term;
}
