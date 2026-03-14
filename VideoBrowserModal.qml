import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modals.Common

DankModal {
    id: root

    property string selectedVideoPath: ""
    property string searchText: ""
    property bool addToPlaylistMode: false
    property string currentDirectory: ""
    property var pathHistory: []
    property string initialDirectory: ""

    signal videoSelected(string videoPath)

    modalWidth: Math.min(screenWidth - 100, 1200)
    modalHeight: Math.min(screenHeight - 100, 800)
    width: modalWidth
    height: modalHeight
    positioning: "center"
    allowStacking: true

    Component.onCompleted: {
        const homeDir = StandardPaths.writableLocation(StandardPaths.HomeLocation).toString().replace("file://", "")
        const startDir = initialDirectory && initialDirectory !== "" ? initialDirectory : homeDir
        currentDirectory = startDir
        pathHistory = [startDir]
        scanDirectory()
    }

    onDialogClosed: {
        selectedVideoPath = ""
        searchText = ""
    }

    content: Item {
        anchors.fill: parent

        Rectangle {
            id: header
            width: parent.width
            height: 60
            color: Theme.surfaceContainer

            Row {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingL
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingM

                DankIcon {
                    name: "movie"
                    size: Theme.iconSize
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: addToPlaylistMode ? "选择视频添加到播放列表" : "选择视频"
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.Bold
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            DankButton {
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingL
                anchors.verticalCenter: parent.verticalCenter
                text: "关闭"
                onClicked: root.close()
            }
        }

        Rectangle {
            id: contentContainer
            anchors.top: header.bottom
            anchors.bottom: parent.bottom
            width: parent.width
            color: "transparent"

            Column {
                anchors.fill: parent
                spacing: 0

                // Navigation bar with shortcuts
                Rectangle {
                    width: parent.width
                    height: 50
                    color: Theme.surfaceContainer

                    Row {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        DankButton {
                            text: "返回"
                            enabled: pathHistory.length > 1
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: {
                                if (pathHistory.length > 1) {
                                    pathHistory.pop()
                                    currentDirectory = pathHistory[pathHistory.length - 1]
                                    scanDirectory()
                                }
                            }
                        }

                        DankButton {
                            text: "主目录"
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: {
                                const homeDir = StandardPaths.writableLocation(StandardPaths.HomeLocation).toString().replace("file://", "")
                                navigateToDirectory(homeDir)
                            }
                        }

                        DankButton {
                            text: "视频"
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: {
                                const videosDir = StandardPaths.writableLocation(StandardPaths.MoviesLocation).toString().replace("file://", "")
                                navigateToDirectory(videosDir)
                            }
                        }

                        DankButton {
                            text: "下载"
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: {
                                const downloadsDir = StandardPaths.writableLocation(StandardPaths.DownloadLocation).toString().replace("file://", "")
                                navigateToDirectory(downloadsDir)
                            }
                        }
                    }
                }

                // Editable address bar
                Rectangle {
                    width: parent.width
                    height: 50
                    color: Theme.surfaceContainer

                    Row {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingM

                        DankIcon {
                            name: "folder_open"
                            size: 20
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.primary
                        }

                        DankTextField {
                            id: addressBar
                            width: parent.width - 20 - goButton.width - Theme.spacingM * 3
                            text: root.currentDirectory
                            placeholderText: "输入路径..."
                            anchors.verticalCenter: parent.verticalCenter
                            onAccepted: {
                                if (text.trim() !== "") {
                                    navigateToDirectory(text.trim())
                                }
                            }
                        }

                        DankButton {
                            id: goButton
                            text: "前往"
                            anchors.verticalCenter: parent.verticalCenter
                            enabled: addressBar.text.trim() !== "" && addressBar.text !== root.currentDirectory
                            onClicked: {
                                if (addressBar.text.trim() !== "") {
                                    navigateToDirectory(addressBar.text.trim())
                                }
                            }
                        }
                    }
                }

                // Breadcrumb navigation
                Rectangle {
                    width: parent.width
                    height: 45
                    color: Theme.surfaceContainer

                    Flickable {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingM
                        anchors.rightMargin: Theme.spacingM
                        anchors.topMargin: Theme.spacingS
                        anchors.bottomMargin: Theme.spacingS
                        contentWidth: breadcrumbRow.width
                        clip: true

                        Row {
                            id: breadcrumbRow
                            spacing: 0
                            height: parent.height

                            Repeater {
                                model: {
                                    const parts = root.currentDirectory.split('/').filter(p => p !== '')
                                    const result = [{ name: "根目录", path: "/" }]
                                    let currentPath = ""
                                    for (const part of parts) {
                                        currentPath += "/" + part
                                        result.push({ name: part, path: currentPath })
                                    }
                                    return result
                                }

                                delegate: Row {
                                    required property var modelData
                                    required property int index
                                    spacing: 4
                                    height: breadcrumbRow.height

                                    StyledRect {
                                        height: 32
                                        width: breadcrumbText.width + Theme.spacingM * 2
                                        radius: Theme.cornerRadius
                                        color: breadcrumbMouseArea.containsMouse ? Theme.primaryContainer : "transparent"
                                        anchors.verticalCenter: parent.verticalCenter

                                        StyledText {
                                            id: breadcrumbText
                                            anchors.centerIn: parent
                                            text: modelData.name
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: breadcrumbMouseArea.containsMouse ? Theme.primary : Theme.surfaceText
                                        }

                                        MouseArea {
                                            id: breadcrumbMouseArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                navigateToDirectory(modelData.path)
                                            }
                                        }
                                    }

                                    StyledText {
                                        text: "/"
                                        font.pixelSize: Theme.fontSizeSmall
                                        opacity: 0.5
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: index < breadcrumbRow.children.length - 1
                                    }
                                }
                            }
                        }
                    }
                }

                // Search bar
                Rectangle {
                    width: parent.width
                    height: 50
                    color: Theme.surfaceContainer

                    Row {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingM

                        DankTextField {
                            id: searchField
                            width: parent.width - refreshButton.width - Theme.spacingM
                            placeholderText: "搜索当前目录..."
                            text: root.searchText
                            anchors.verticalCenter: parent.verticalCenter
                            onTextChanged: {
                                root.searchText = text
                                filterItems()
                            }
                        }

                        DankButton {
                            id: refreshButton
                            text: "刷新"
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: scanDirectory()
                        }
                    }
                }

                // Item count
                Rectangle {
                    width: parent.width
                    height: 35
                    color: Theme.surfaceContainer

                    StyledText {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            const folderCount = filteredItems.count - videoCount
                            return folderCount + " 个文件夹，" + videoCount + " 个视频"
                        }
                        font.pixelSize: Theme.fontSizeSmall
                        opacity: 0.7
                    }
                }

                // File/Folder list
                Rectangle {
                    width: parent.width
                    height: parent.height - 50 - 50 - 45 - 50 - 35
                    color: Theme.surface

                    ListView {
                        id: itemListView
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        clip: true
                        model: filteredItems
                        spacing: Theme.spacingS

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                        }

                        delegate: StyledRect {
                            required property var modelData
                            required property int index

                            width: itemListView.width - Theme.spacingM
                            height: 80
                            radius: Theme.cornerRadius
                            color: mouseArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainer
                            border.width: 1
                            border.color: Theme.outlineStrong

                            Row {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingM

                                // Thumbnail/Icon
                                Rectangle {
                                    width: 120
                                    height: 68  // 16:9 ratio
                                    radius: Theme.cornerRadius
                                    color: modelData.isDirectory ? Theme.primaryContainer : Theme.surface
                                    anchors.verticalCenter: parent.verticalCenter
                                    clip: true

                                    // Video thumbnail
                                    Image {
                                        id: thumbnail
                                        anchors.fill: parent
                                        fillMode: Image.PreserveAspectCrop
                                        visible: !modelData.isDirectory && status === Image.Ready
                                        asynchronous: true
                                        cache: true

                                        property string videoPath: modelData.path
                                        property string thumbnailPath: ""

                                        Component.onCompleted: {
                                            if (!modelData.isDirectory) {
                                                generateThumbnail()
                                            }
                                        }

                                        function generateThumbnail() {
                                            const cacheHome = StandardPaths.writableLocation(StandardPaths.GenericCacheLocation).toString().replace("file://", "")
                                            const cacheDir = cacheHome + "/DankMaterialShell/mpvpaper_thumbnails"
                                            
                                            // Create hash from video path for cache filename
                                            const hash = videoPath.split('').reduce((a, b) => {
                                                a = ((a << 5) - a) + b.charCodeAt(0)
                                                return a & a
                                            }, 0)
                                            
                                            thumbnailPath = cacheDir + "/" + Math.abs(hash) + "_thumb.jpg"
                                            
                                            // Check if thumbnail already exists
                                            thumbnailCheckProcess.thumbnailPath = thumbnailPath
                                            thumbnailCheckProcess.videoPath = videoPath
                                            thumbnailCheckProcess.cacheDir = cacheDir
                                            thumbnailCheckProcess.command = ["test", "-f", thumbnailPath]
                                            thumbnailCheckProcess.running = true
                                        }

                                        Process {
                                            id: thumbnailCheckProcess
                                            property string thumbnailPath: ""
                                            property string videoPath: ""
                                            property string cacheDir: ""

                                            onExited: (code) => {
                                                if (code === 0) {
                                                    // Thumbnail exists, use it
                                                    thumbnail.source = "file://" + thumbnailPath
                                                } else {
                                                    // Generate thumbnail - 16:9 at 320x180 with cover crop
                                                    thumbnailGenProcess.thumbnailPath = thumbnailPath
                                                    thumbnailGenProcess.videoPath = videoPath
                                                    thumbnailGenProcess.cacheDir = cacheDir
                                                    thumbnailGenProcess.command = ["bash", "-c",
                                                        `mkdir -p "${cacheDir}" && ffmpeg -i "${videoPath}" -ss 00:00:01 -vframes 1 -vf "scale=320:180:force_original_aspect_ratio=increase,crop=320:180" -q:v 3 "${thumbnailPath}" -y 2>/dev/null`
                                                    ]
                                                    thumbnailGenProcess.running = true
                                                }
                                            }
                                        }

                                        Process {
                                            id: thumbnailGenProcess
                                            property string thumbnailPath: ""
                                            property string videoPath: ""
                                            property string cacheDir: ""

                                            onExited: (code) => {
                                                if (code === 0) {
                                                    thumbnail.source = "file://" + thumbnailPath
                                                }
                                            }
                                        }
                                    }

                                    // Fallback icon
                                    DankIcon {
                                        anchors.centerIn: parent
                                        name: modelData.isDirectory ? "folder" : "movie"
                                        size: 40
                                        color: modelData.isDirectory ? Theme.primary : Theme.primary
                                        visible: modelData.isDirectory || thumbnail.status !== Image.Ready
                                    }
                                }

                                Column {
                                    width: parent.width - 120 - Theme.spacingM
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4

                                    StyledText {
                                        width: parent.width
                                        text: modelData.name
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: modelData.isDirectory ? Font.Bold : Font.Medium
                                        elide: Text.ElideMiddle
                                    }

                                    StyledText {
                                        width: parent.width
                                        text: modelData.isDirectory ? "文件夹" : "视频文件"
                                        font.pixelSize: Theme.fontSizeSmall
                                        opacity: 0.7
                                    }
                                }
                            }

                            MouseArea {
                                id: mouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.isDirectory) {
                                        navigateToDirectory(modelData.path)
                                    } else {
                                        selectedVideoPath = modelData.path
                                        videoSelected(selectedVideoPath)
                                        root.close()
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        text: root.searchText ? "没有匹配的项目" : "此目录为空"
                        opacity: 0.7
                        visible: filteredItems.count === 0
                        wrapMode: Text.Wrap
                        width: parent.width - 40
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }

    ListModel {
        id: allItems
    }

    ListModel {
        id: filteredItems
    }

    property int videoCount: 0

    function navigateToDirectory(path) {
        currentDirectory = path
        pathHistory.push(path)
        scanDirectory()
    }

    function scanDirectory() {
        if (!currentDirectory) {
            return
        }

        console.log("MpvPaper: Scanning directory:", currentDirectory)
        allItems.clear()
        filteredItems.clear()
        searchText = ""

        // Scan for directories and video files using a more reliable method
        dirScanProcess.command = ["bash", "-c",
            `cd "${currentDirectory}" 2>/dev/null || exit 1
            # List directories first
            for dir in */; do
                if [ -d "$dir" ]; then
                    dirname="\${dir%/}"
                    echo "DIR:$dirname"
                fi
            done | sort
            # List video files
            for file in *; do
                if [ -f "$file" ]; then
                    case "$file" in
                        *.mp4|*.MP4|*.mkv|*.MKV|*.webm|*.WEBM|*.avi|*.AVI|*.mov|*.MOV|*.flv|*.FLV|*.wmv|*.WMV|*.m4v|*.M4V)
                            echo "FILE:$file"
                            ;;
                    esac
                fi
            done | sort`
        ]
        dirScanProcess.running = true
    }

    Process {
        id: dirScanProcess
        property string scanOutput: ""

        stdout: SplitParser {
            onRead: (data) => {
                dirScanProcess.scanOutput += data + "\n"
            }
        }

        stderr: SplitParser {
            onRead: (data) => {
                console.warn("MpvPaper: Directory scan error:", data)
            }
        }

        onExited: (code) => {
            console.log("MpvPaper: Scan completed with code:", code)
            if (scanOutput) {
                console.log("MpvPaper: Scan output length:", scanOutput.length)
                const lines = scanOutput.trim().split('\n')
                console.log("MpvPaper: Found", lines.length, "lines")
                let vCount = 0
                
                for (const line of lines) {
                    const trimmedLine = line.trim()
                    if (!trimmedLine) continue
                    
                    if (trimmedLine.startsWith("DIR:")) {
                        const dirName = trimmedLine.substring(4)
                        if (dirName && dirName !== "." && dirName !== "..") {
                            console.log("MpvPaper: Found directory:", dirName)
                            allItems.append({
                                name: dirName,
                                path: currentDirectory + "/" + dirName,
                                isDirectory: true
                            })
                        }
                    } else if (trimmedLine.startsWith("FILE:")) {
                        const fileName = trimmedLine.substring(5)
                        if (fileName) {
                            console.log("MpvPaper: Found video:", fileName)
                            allItems.append({
                                name: fileName,
                                path: currentDirectory + "/" + fileName,
                                isDirectory: false
                            })
                            vCount++
                        }
                    }
                }
                
                console.log("MpvPaper: Total items:", allItems.count, "Videos:", vCount)
                videoCount = vCount
                filterItems()
            } else {
                console.warn("MpvPaper: No output from directory scan")
            }
            scanOutput = ""
        }
    }

    function filterItems() {
        filteredItems.clear()
        const searchTerm = searchText.toLowerCase()
        let vCount = 0

        for (let i = 0; i < allItems.count; i++) {
            const item = allItems.get(i)
            if (!searchTerm || item.name.toLowerCase().includes(searchTerm)) {
                filteredItems.append(item)
                if (!item.isDirectory) {
                    vCount++
                }
            }
        }
        
        if (searchTerm) {
            videoCount = vCount
        }
    }
}
