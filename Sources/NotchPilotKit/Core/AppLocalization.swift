import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case zhHans = "zh-Hans"
    case english = "en"

    public var id: String { rawValue }

    var displayName: String {
        switch self {
        case .zhHans:
            return "中文"
        case .english:
            return "English"
        }
    }
}

enum AppTextKey {
    case general
    case approval
    case application
    case startup
    case launchAtLogin
    case launchAtLoginDetail
    case language
    case interfaceLanguage
    case interfaceLanguageDetail
    case displayApprovalSneakNotifications
    case displayApprovalSneakNotificationsDetail
    case sneakPreviews
    case hideAllSneakPreviewsTitle
    case hideAllSneakPreviewsDetail
    case toggleHideAllPreviewsShortcutTitle
    case toggleHideAllPreviewsShortcutDetail
    case quitAppTitle
    case quitAppDetail
    case quitAppButton
    case media
    case system
    case playback
    case enableMediaPlugin
    case enableMediaPluginDetail
    case showPlaybackPreview
    case showPlaybackPreviewDetail
    case desktopLyricsCard
    case desktopLyricsCardDetail
    case lyricsStyle
    case highlightColor
    case highlightColorDetail
    case fontSize
    case plugin
    case enableClaudePlugin
    case enableClaudePluginDetail
    case claudeCode
    case integrationStatus
    case actions
    case installIntegration
    case updateIntegration
    case removeIntegration
    case claudeCodeMissingDetail
    case missingClaudeBridgeScriptError
    case enableCodexPlugin
    case enableCodexPluginDetail
    case codexDesktop
    case connectionStatus
    case enableSystemMonitorPlugin
    case enableSystemMonitorPluginDetail
    case preview
    case showSystemMonitorPreview
    case sneakPreviewMode
    case sneakPreviewModeDetail
    case sneakPreviewModeAlwaysOn
    case sneakPreviewModePinnedReactive
    case sneakPreviewModeAmbient
    case pinnedSlots
    case pinnedSlotsFooter
    case reactiveMetrics
    case reactiveMetricsDetail
    case reactiveMetricsFooter
    case reactiveThresholds
    case reactiveThresholdsFooter
    case cpuThresholdTitle
    case memoryThresholdTitle
    case temperatureThresholdTitle
    case batteryThresholdTitle
    case diskThresholdTitle
    case networkThresholdTitle
    case leftSlot1
    case leftSlot2
    case rightSlot1
    case rightSlot2
    case hidden
    case searchLyricsMenu
    case markLyricsWrongMenu
    case revealLyricsCacheMenu
    case hideAllSneaksMenu
    case settingsMenu
    case settingsWindowTitle
    case quitNotchPilotMenu
    case lyricsOffsetLabel
    case lyricsBoundTo
    case searchLyricsWindowTitle
    case close
    case song
    case artist
    case source
    case search
    case searching
    case applyToCurrentSong
    case noLyricsPreview
    case noLyricsFound
    case unableToLoadLyrics
    case noPluginsEnabled
    case openSettings
    case playbackProgress
    case noActiveMediaPlayback
    case unknownTrack
    case idle
    case actionNeeded
    case networkAccess
    case networkAccessRequest
    case claudeWaitingApproval
    case tellClaudeWhatToChange
    case send
    case noTellClaudeWhy
    case codexTextInputFallback
    case typeHere
    case codexNeedsInput
    case submit
    case skip
    case commandApprovalSummary
    case fileChangeApprovalSummary
    case soundFeedback
    case enableSounds
    case enableSoundsDetail
    case soundTaskCompleteVolume
    case soundTaskCompleteVolumeDetail
    case soundInputRequiredVolume
    case soundInputRequiredVolumeDetail
}

enum AppConnectionStatus {
    case notDetected
    case notInstalled
    case updateAvailable
    case connected
    case disconnected
    case connecting
    case error
}

enum AppStrings {
    static func text(_ key: AppTextKey, language: AppLanguage) -> String {
        switch language {
        case .zhHans:
            return chineseText(key)
        case .english:
            return englishText(key)
        }
    }

    static func connectionStatus(_ status: AppConnectionStatus, language: AppLanguage) -> String {
        switch (language, status) {
        case (.zhHans, .notDetected):
            return "未检测到"
        case (.zhHans, .notInstalled):
            return "未安装"
        case (.zhHans, .updateAvailable):
            return "可更新"
        case (.zhHans, .connected):
            return "已连接"
        case (.zhHans, .disconnected):
            return "未连接"
        case (.zhHans, .connecting):
            return "连接中"
        case (.zhHans, .error):
            return "错误"
        case (.english, .notDetected):
            return "Not Detected"
        case (.english, .notInstalled):
            return "Not Installed"
        case (.english, .updateAvailable):
            return "Update Available"
        case (.english, .connected):
            return "Connected"
        case (.english, .disconnected):
            return "Disconnected"
        case (.english, .connecting):
            return "Connecting"
        case (.english, .error):
            return "Error"
        }
    }

    static func fontSizeDetail(_ size: Double, language: AppLanguage) -> String {
        switch language {
        case .zhHans:
            return "当前歌词行文字大小（\(Int(size))pt）。"
        case .english:
            return "Current lyric line text size (\(Int(size)) pt)."
        }
    }

    static func systemMonitorThresholdValueText(metric: SystemMonitorMetric, value: Double) -> String {
        let intValue = Int(value.rounded())
        switch metric {
        case .cpu, .memory, .battery:
            return "\(intValue)%"
        case .temperature:
            return "\(intValue)°C"
        case .disk:
            return "\(intValue) GB"
        case .network:
            return "\(intValue) MB/s"
        }
    }

    static func systemMonitorThresholdDetail(
        metric: SystemMonitorMetric,
        value: Double,
        language: AppLanguage
    ) -> String {
        let valueText = systemMonitorThresholdValueText(metric: metric, value: value)
        let metricName = systemMonitorMetricTitle(metric, language: language)
        let isLowTrigger = metric == .battery || metric == .disk

        switch (language, isLowTrigger) {
        case (.zhHans, true):
            return "\(metricName)低于 \(valueText) 时进入 sneak"
        case (.zhHans, false):
            return "\(metricName)超过 \(valueText) 时进入 sneak"
        case (.english, true):
            return "Surfaces when \(metricName.lowercased()) drops below \(valueText)"
        case (.english, false):
            return "Surfaces when \(metricName.lowercased()) exceeds \(valueText)"
        }
    }

    static func systemMonitorMetricTitle(_ metric: SystemMonitorMetric, language: AppLanguage) -> String {
        switch (language, metric) {
        case (_, .cpu):
            return "CPU"
        case (.zhHans, .memory):
            return "内存"
        case (.zhHans, .network):
            return "网络"
        case (.zhHans, .disk):
            return "磁盘剩余"
        case (.zhHans, .temperature):
            return "温度"
        case (.zhHans, .battery):
            return "电量"
        case (.english, .memory):
            return "Memory"
        case (.english, .network):
            return "Network"
        case (.english, .disk):
            return "Disk Free"
        case (.english, .temperature):
            return "Temperature"
        case (.english, .battery):
            return "Battery"
        }
    }

    static func systemMonitorCompactMetricTitle(_ metric: SystemMonitorMetric, language: AppLanguage) -> String {
        switch (language, metric) {
        case (_, .cpu):
            return "CPU"
        case (.zhHans, .memory):
            return "内存"
        case (.zhHans, .network):
            return "网络"
        case (.zhHans, .temperature):
            return "温度"
        case (.zhHans, .disk):
            return "磁盘"
        case (.zhHans, .battery):
            return "电量"
        case (.english, .memory):
            return "MEM"
        case (.english, .network):
            return "NET"
        case (.english, .temperature):
            return "TMP"
        case (.english, .disk):
            return "DSK"
        case (.english, .battery):
            return "BAT"
        }
    }

    static func systemMonitorBlockTitle(_ metric: SystemMonitorMetric, language: AppLanguage) -> String {
        switch (language, metric) {
        case (_, .cpu):
            return "CPU"
        case (.zhHans, .memory):
            return "内存"
        case (.zhHans, .network):
            return "网络"
        case (.zhHans, .disk):
            return "系统"
        case (.zhHans, .temperature):
            return "温度"
        case (.zhHans, .battery):
            return "电量"
        case (.english, .memory):
            return "Memory"
        case (.english, .network):
            return "Network"
        case (.english, .disk):
            return "System"
        case (.english, .temperature):
            return "Temperature"
        case (.english, .battery):
            return "Battery"
        }
    }

    static func systemMonitorTopItemName(_ name: String, language: AppLanguage) -> String {
        guard language == .zhHans else {
            return name
        }

        switch name {
        case "Disk Free":
            return "磁盘剩余"
        case "Temperature":
            return "温度"
        case "Battery":
            return "电量"
        default:
            return name
        }
    }

    static func systemMonitorDetail(_ detail: String, language: AppLanguage) -> String {
        guard language == .zhHans,
              detail.hasPrefix("Pressure "),
              let separatorRange = detail.range(of: " · Memory ")
        else {
            return detail
        }

        let pressure = detail[detail.index(detail.startIndex, offsetBy: "Pressure ".count)..<separatorRange.lowerBound]
        let memory = detail[separatorRange.upperBound...]
        return "压力 \(pressure) · 内存 \(memory)"
    }

    static func activityLabel(_ raw: String, language: AppLanguage) -> String {
        switch (language, raw) {
        case (.zhHans, "Plan"):
            return "计划"
        case (.zhHans, "Working"):
            return "处理中"
        case (.zhHans, "Completed"):
            return "已完成"
        case (.zhHans, "Connected"):
            return "已连接"
        case (.zhHans, "Interrupted"):
            return "已中断"
        case (.zhHans, "Error"):
            return "错误"
        case (.zhHans, "Waiting Approval"):
            return "等待审批"
        case (.zhHans, "Prompt Sent"):
            return "提示已发送"
        case (.zhHans, "Stopped"):
            return "已停止"
        case (.zhHans, "Running"):
            return "运行中"
        case (.zhHans, "Done"):
            return "已完成"
        case (.zhHans, "Active"):
            return "活跃"
        case (.zhHans, "Action Needed"):
            return text(.actionNeeded, language: language)
        case (.zhHans, "Approval"):
            return text(.approval, language: language)
        case (.zhHans, "Network Access"):
            return text(.networkAccess, language: language)
        default:
            if language == .zhHans, raw.hasSuffix(" Done") {
                return "\(raw.dropLast(" Done".count)) 完成"
            }
            return raw
        }
    }

    static func approvalActionTitle(_ title: String, id: String, language: AppLanguage) -> String {
        if id == "claude-deny-feedback-submit" {
            return text(.noTellClaudeWhy, language: language)
        }

        switch (language, title) {
        case (.zhHans, "Deny"):
            return "拒绝"
        case (.zhHans, "Allow once"):
            return "允许一次"
        case (.zhHans, "Always allow"):
            return "始终允许"
        case (.zhHans, "Allow for session"):
            return "本会话允许"
        case (.zhHans, "No, tell Claude why"):
            return text(.noTellClaudeWhy, language: language)
        default:
            return title
        }
    }

    static func claudeApprovalTitle(_ title: String, language: AppLanguage) -> String {
        guard language == .zhHans else {
            return title
        }

        switch title {
        case "Allow Claude to run this command?":
            return "允许 Claude 运行这条命令吗？"
        case "Allow Claude to edit files?":
            return "允许 Claude 编辑文件吗？"
        case "Allow Claude to access the web?":
            return "允许 Claude 访问网络吗？"
        default:
            if title.hasPrefix("Allow Claude to run "), title.hasSuffix("?") {
                let description = title
                    .dropFirst("Allow Claude to run ".count)
                    .dropLast()
                return "允许 Claude 运行 \(description) 吗？"
            }
            if title.hasPrefix("Allow Claude to use "), title.hasSuffix("?") {
                let description = title
                    .dropFirst("Allow Claude to use ".count)
                    .dropLast()
                return "允许 Claude 使用 \(description) 吗？"
            }
            return title
        }
    }

    static func codexSurfaceSummary(_ summary: String, language: AppLanguage) -> String {
        switch (language, summary) {
        case (.zhHans, "Would you like to run the following command?"):
            return text(.commandApprovalSummary, language: language)
        case (.zhHans, "Would you like to make the following edits?"):
            return text(.fileChangeApprovalSummary, language: language)
        case (.zhHans, "Codex needs your input"):
            return text(.codexNeedsInput, language: language)
        default:
            return summary
        }
    }

    static func codexButtonTitle(_ title: String, language: AppLanguage) -> String {
        switch title {
        case "Submit":
            return text(.submit, language: language)
        case "Skip":
            return text(.skip, language: language)
        default:
            return title
        }
    }

    static func codexOptionTitle(_ title: String, language: AppLanguage) -> String {
        guard language == .zhHans else {
            return title
        }

        switch title {
        case "Yes":
            return "是"
        case "Yes, and don't ask again for this command in this session":
            return "是，且本会话不再询问这条命令"
        case "Yes, and don't ask again for these files":
            return "是，且不再询问这些文件"
        case "No, continue without running it":
            return "否，继续但不运行"
        case "No, continue without applying them":
            return "否，继续但不应用"
        case "Type here":
            return text(.typeHere, language: language)
        case "Yes, and allow this host in the future":
            return "是，且以后允许这个主机"
        default:
            if title.hasPrefix("Yes, and don't ask again for commands that start with `"),
               title.hasSuffix("`") {
                let prefix = title
                    .dropFirst("Yes, and don't ask again for commands that start with `".count)
                    .dropLast()
                return "是，且对于以 `\(prefix)` 开头的命令不再询问"
            }
            if title.hasPrefix("Yes, and allow "),
               title.hasSuffix(" in the future") {
                let host = title
                    .dropFirst("Yes, and allow ".count)
                    .dropLast(" in the future".count)
                return "是，且以后允许 \(host)"
            }
            return title
        }
    }

    private static func chineseText(_ key: AppTextKey) -> String {
        switch key {
        case .general:
            return "通用"
        case .approval:
            return "审批"
        case .application:
            return "应用"
        case .startup:
            return "启动"
        case .launchAtLogin:
            return "开机自动启动"
        case .launchAtLoginDetail:
            return "登录到 Mac 时自动运行 NotchPilot。"
        case .language:
            return "语言"
        case .interfaceLanguage:
            return "界面语言"
        case .interfaceLanguageDetail:
            return "切换 NotchPilot 的显示语言。"
        case .displayApprovalSneakNotifications:
            return "显示 Claude / Codex 审批弹窗"
        case .displayApprovalSneakNotificationsDetail:
            return "关闭后审批不会主动弹出，但运行中的会话预览（含计时）仍会显示。"
        case .sneakPreviews:
            return "刘海预览"
        case .hideAllSneakPreviewsTitle:
            return "隐藏所有预览"
        case .hideAllSneakPreviewsDetail:
            return "关闭运行中的会话与播放预览（含计时）。审批弹窗不受此设置影响。"
        case .toggleHideAllPreviewsShortcutTitle:
            return "切换\"隐藏所有预览\"快捷键"
        case .toggleHideAllPreviewsShortcutDetail:
            return "全局快捷键，菜单栏菜单同步显示。点击右侧方框开始录制，按下 Delete 清除。"
        case .quitAppTitle, .quitAppButton:
            return "退出应用"
        case .quitAppDetail:
            return "结束 NotchPilot"
        case .media:
            return "媒体"
        case .system:
            return "系统"
        case .playback:
            return "播放"
        case .enableMediaPlugin:
            return "启用媒体插件"
        case .enableMediaPluginDetail:
            return "关闭后不再监听播放状态，也不会出现在 Notch。"
        case .showPlaybackPreview:
            return "播放变化时显示预览"
        case .showPlaybackPreviewDetail:
            return "在 Notch 闭合态显示当前播放信息。"
        case .desktopLyricsCard:
            return "桌面底部歌词卡片"
        case .desktopLyricsCardDetail:
            return "在当前活跃屏幕底部显示当前歌词与下一句。"
        case .lyricsStyle:
            return "歌词样式"
        case .highlightColor:
            return "高亮颜色"
        case .highlightColorDetail:
            return "歌词进度填充颜色。"
        case .fontSize:
            return "字体大小"
        case .plugin:
            return "插件"
        case .enableClaudePlugin:
            return "启用 Claude 插件"
        case .enableClaudePluginDetail:
            return "关闭后不会处理 Claude Hook，也不会在 Notch 中显示 Claude 会话。"
        case .claudeCode:
            return "Claude Code"
        case .integrationStatus:
            return "集成状态"
        case .actions:
            return "操作"
        case .installIntegration:
            return "安装集成"
        case .updateIntegration:
            return "更新集成"
        case .removeIntegration:
            return "移除集成"
        case .claudeCodeMissingDetail:
            return "请先安装 Claude Code。"
        case .missingClaudeBridgeScriptError:
            return "未找到 Claude 集成所需脚本，无法完成安装。"
        case .enableCodexPlugin:
            return "启用 Codex 插件"
        case .enableCodexPluginDetail:
            return "关闭后不再监听 Codex Desktop 会话，也不会出现在 Notch。"
        case .codexDesktop:
            return "Codex Desktop"
        case .connectionStatus:
            return "连接状态"
        case .enableSystemMonitorPlugin:
            return "启用系统监控插件"
        case .enableSystemMonitorPluginDetail:
            return "关闭后停止采样 CPU、内存、网络等指标，并从 Notch 中移除。"
        case .preview:
            return "预览"
        case .showSystemMonitorPreview:
            return "在 Notch 闭合态显示系统监控"
        case .sneakPreviewMode:
            return "预览模式"
        case .sneakPreviewModeDetail:
            return "决定刘海闭合时何时显示系统监控数据。"
        case .sneakPreviewModeAlwaysOn:
            return "始终显示"
        case .sneakPreviewModePinnedReactive:
            return "常驻 + 异常扩展"
        case .sneakPreviewModeAmbient:
            return "仅异常时显示"
        case .pinnedSlots:
            return "常驻槽位"
        case .pinnedSlotsFooter:
            return "「仅异常时显示」模式下不会展示这些槽位。"
        case .reactiveMetrics:
            return "反应式指标"
        case .reactiveMetricsDetail:
            return "勾选的指标在阈值越界时自动出现在 sneak 中。"
        case .reactiveMetricsFooter:
            return "已选为常驻槽位的指标会自动从此列表中排除。"
        case .reactiveThresholds:
            return "反应阈值"
        case .reactiveThresholdsFooter:
            return "突破阈值后，对应指标会临时插入到 sneak 中；按需调高/调低敏感度。"
        case .cpuThresholdTitle:
            return "CPU 触发线"
        case .memoryThresholdTitle:
            return "内存触发线"
        case .temperatureThresholdTitle:
            return "温度触发线"
        case .batteryThresholdTitle:
            return "电量触发线"
        case .diskThresholdTitle:
            return "磁盘剩余触发线"
        case .networkThresholdTitle:
            return "网络突发触发线"
        case .leftSlot1:
            return "左侧槽位 1"
        case .leftSlot2:
            return "左侧槽位 2"
        case .rightSlot1:
            return "右侧槽位 1"
        case .rightSlot2:
            return "右侧槽位 2"
        case .hidden:
            return "隐藏"
        case .searchLyricsMenu:
            return "搜索歌词…"
        case .markLyricsWrongMenu:
            return "标记当前歌词错误"
        case .revealLyricsCacheMenu:
            return "在 Finder 中显示歌词缓存"
        case .hideAllSneaksMenu:
            return "隐藏所有预览"
        case .settingsMenu:
            return "设置…"
        case .settingsWindowTitle:
            return "NotchPilot 设置"
        case .quitNotchPilotMenu:
            return "退出 NotchPilot"
        case .lyricsOffsetLabel:
            return "歌词偏移:"
        case .lyricsBoundTo:
            return "绑定到"
        case .searchLyricsWindowTitle:
            return "搜索歌词"
        case .close:
            return "关闭"
        case .song:
            return "歌曲"
        case .artist:
            return "艺人"
        case .source:
            return "来源"
        case .search:
            return "搜索"
        case .searching:
            return "搜索中…"
        case .applyToCurrentSong:
            return "应用到当前歌曲"
        case .noLyricsPreview:
            return "没有可预览的歌词。"
        case .noLyricsFound:
            return "没有找到可用歌词。"
        case .unableToLoadLyrics:
            return "无法加载所选歌词。"
        case .noPluginsEnabled:
            return "没有启用插件。"
        case .openSettings:
            return "打开设置"
        case .playbackProgress:
            return "播放进度"
        case .noActiveMediaPlayback:
            return "没有正在播放的媒体。"
        case .unknownTrack:
            return "未知曲目"
        case .idle:
            return "空闲"
        case .actionNeeded:
            return "需要操作"
        case .networkAccess:
            return "网络访问"
        case .networkAccessRequest:
            return "网络访问请求"
        case .claudeWaitingApproval:
            return "Claude 正在等待审批"
        case .tellClaudeWhatToChange:
            return "告诉 Claude 要修改什么"
        case .send:
            return "发送"
        case .noTellClaudeWhy:
            return "否，告诉 Claude 原因"
        case .codexTextInputFallback:
            return "否，请告知 Codex 如何调整"
        case .typeHere:
            return "在此输入"
        case .codexNeedsInput:
            return "Codex 需要你的输入"
        case .submit:
            return "提交"
        case .skip:
            return "跳过"
        case .commandApprovalSummary:
            return "是否运行以下命令？"
        case .fileChangeApprovalSummary:
            return "是否应用以下编辑？"
        case .soundFeedback:
            return "声音反馈"
        case .enableSounds:
            return "启用声音"
        case .enableSoundsDetail:
            return "AI 任务完成或等待审批时播放声音。"
        case .soundTaskCompleteVolume:
            return "任务完成音量"
        case .soundTaskCompleteVolumeDetail:
            return "调整 AI 任务完成时提示音的音量。"
        case .soundInputRequiredVolume:
            return "等待审批音量"
        case .soundInputRequiredVolumeDetail:
            return "调整 AI 请求审批或输入时提示音的音量。"
        }
    }

    private static func englishText(_ key: AppTextKey) -> String {
        switch key {
        case .general:
            return "General"
        case .approval:
            return "Approval"
        case .application:
            return "Application"
        case .startup:
            return "Startup"
        case .launchAtLogin:
            return "Launch at Login"
        case .launchAtLoginDetail:
            return "Automatically start NotchPilot when you log in to your Mac."
        case .language:
            return "Language"
        case .interfaceLanguage:
            return "Interface Language"
        case .interfaceLanguageDetail:
            return "Switch the display language used by NotchPilot."
        case .displayApprovalSneakNotifications:
            return "Show Claude / Codex Approval Popups"
        case .displayApprovalSneakNotificationsDetail:
            return "When off, approval prompts will not pop up automatically. Running session previews (with timer) are still shown."
        case .sneakPreviews:
            return "Sneak Previews"
        case .hideAllSneakPreviewsTitle:
            return "Hide All Previews"
        case .hideAllSneakPreviewsDetail:
            return "Hide running session and playback previews (including the timer). Approval popups are not affected by this setting."
        case .toggleHideAllPreviewsShortcutTitle:
            return "\"Hide All Previews\" Shortcut"
        case .toggleHideAllPreviewsShortcutDetail:
            return "Global shortcut, also shown in the menu bar item. Click the field on the right to record; press Delete to clear."
        case .quitAppTitle, .quitAppButton:
            return "Quit App"
        case .quitAppDetail:
            return "Close NotchPilot"
        case .media:
            return "Media"
        case .system:
            return "System"
        case .playback:
            return "Playback"
        case .enableMediaPlugin:
            return "Enable Media Plugin"
        case .enableMediaPluginDetail:
            return "When off, playback state is not monitored and Media is removed from Notch."
        case .showPlaybackPreview:
            return "Show Preview on Playback Changes"
        case .showPlaybackPreviewDetail:
            return "Show the current playback information while Notch is closed."
        case .desktopLyricsCard:
            return "Desktop Bottom Lyrics Card"
        case .desktopLyricsCardDetail:
            return "Show the current and next lyric at the bottom of the active screen."
        case .lyricsStyle:
            return "Lyrics Style"
        case .highlightColor:
            return "Highlight Color"
        case .highlightColorDetail:
            return "Progress fill color for lyrics."
        case .fontSize:
            return "Font Size"
        case .plugin:
            return "Plugin"
        case .enableClaudePlugin:
            return "Enable Claude Plugin"
        case .enableClaudePluginDetail:
            return "When off, Claude hooks are ignored and Claude sessions are removed from Notch."
        case .claudeCode:
            return "Claude Code"
        case .integrationStatus:
            return "Integration Status"
        case .actions:
            return "Actions"
        case .installIntegration:
            return "Install Integration"
        case .updateIntegration:
            return "Update Integration"
        case .removeIntegration:
            return "Remove Integration"
        case .claudeCodeMissingDetail:
            return "Install Claude Code first."
        case .missingClaudeBridgeScriptError:
            return "The script required for Claude integration was not found, so installation cannot continue."
        case .enableCodexPlugin:
            return "Enable Codex Plugin"
        case .enableCodexPluginDetail:
            return "When off, Codex Desktop sessions are not monitored and Codex is removed from Notch."
        case .codexDesktop:
            return "Codex Desktop"
        case .connectionStatus:
            return "Connection Status"
        case .enableSystemMonitorPlugin:
            return "Enable System Monitor Plugin"
        case .enableSystemMonitorPluginDetail:
            return "When off, CPU, memory, network, and other metrics stop sampling and are removed from Notch."
        case .preview:
            return "Preview"
        case .showSystemMonitorPreview:
            return "Show System Monitor while Notch is Closed"
        case .sneakPreviewMode:
            return "Preview Mode"
        case .sneakPreviewModeDetail:
            return "Decide when the system monitor sneak appears while the notch is closed."
        case .sneakPreviewModeAlwaysOn:
            return "Always On"
        case .sneakPreviewModePinnedReactive:
            return "Pinned + Reactive"
        case .sneakPreviewModeAmbient:
            return "Only on Alert"
        case .pinnedSlots:
            return "Pinned Slots"
        case .pinnedSlotsFooter:
            return "Pinned slots are hidden when the preview mode is set to Only on Alert."
        case .reactiveMetrics:
            return "Reactive Metrics"
        case .reactiveMetricsDetail:
            return "Enabled metrics surface in the sneak only when their alert threshold fires."
        case .reactiveMetricsFooter:
            return "Metrics already pinned to a slot are removed from this list automatically."
        case .reactiveThresholds:
            return "Reactive Thresholds"
        case .reactiveThresholdsFooter:
            return "When a metric crosses its threshold, it temporarily appears in the sneak. Tune the sensitivity per metric."
        case .cpuThresholdTitle:
            return "CPU Trigger"
        case .memoryThresholdTitle:
            return "Memory Trigger"
        case .temperatureThresholdTitle:
            return "Temperature Trigger"
        case .batteryThresholdTitle:
            return "Battery Trigger"
        case .diskThresholdTitle:
            return "Disk Free Trigger"
        case .networkThresholdTitle:
            return "Network Spike Trigger"
        case .leftSlot1:
            return "Left Slot 1"
        case .leftSlot2:
            return "Left Slot 2"
        case .rightSlot1:
            return "Right Slot 1"
        case .rightSlot2:
            return "Right Slot 2"
        case .hidden:
            return "Hidden"
        case .searchLyricsMenu:
            return "Search Lyrics…"
        case .markLyricsWrongMenu:
            return "Mark Current Lyrics as Wrong"
        case .revealLyricsCacheMenu:
            return "Reveal Lyrics Cache in Finder"
        case .hideAllSneaksMenu:
            return "Hide All Sneaks"
        case .settingsMenu:
            return "Settings…"
        case .settingsWindowTitle:
            return "NotchPilot Settings"
        case .quitNotchPilotMenu:
            return "Quit NotchPilot"
        case .lyricsOffsetLabel:
            return "Lyrics Offset:"
        case .lyricsBoundTo:
            return "Bound To"
        case .searchLyricsWindowTitle:
            return "Search Lyrics"
        case .close:
            return "Close"
        case .song:
            return "Song"
        case .artist:
            return "Artist"
        case .source:
            return "Source"
        case .search:
            return "Search"
        case .searching:
            return "Searching…"
        case .applyToCurrentSong:
            return "Apply to Current Song"
        case .noLyricsPreview:
            return "No lyrics available to preview."
        case .noLyricsFound:
            return "No lyrics found."
        case .unableToLoadLyrics:
            return "Unable to load the selected lyrics."
        case .noPluginsEnabled:
            return "No plugins enabled."
        case .openSettings:
            return "Open Settings"
        case .playbackProgress:
            return "Playback progress"
        case .noActiveMediaPlayback:
            return "No active media playback."
        case .unknownTrack:
            return "Unknown Track"
        case .idle:
            return "Idle"
        case .actionNeeded:
            return "Action Needed"
        case .networkAccess:
            return "Network Access"
        case .networkAccessRequest:
            return "Network access request"
        case .claudeWaitingApproval:
            return "Claude is waiting for approval"
        case .tellClaudeWhatToChange:
            return "Tell Claude what to change"
        case .send:
            return "Send"
        case .noTellClaudeWhy:
            return "No, tell Claude why"
        case .codexTextInputFallback:
            return "No, tell Codex how to adjust"
        case .typeHere:
            return "Type here"
        case .codexNeedsInput:
            return "Codex needs your input"
        case .submit:
            return "Submit"
        case .skip:
            return "Skip"
        case .commandApprovalSummary:
            return "Run the following command?"
        case .fileChangeApprovalSummary:
            return "Apply the following edits?"
        case .soundFeedback:
            return "Sound Feedback"
        case .enableSounds:
            return "Enable Sounds"
        case .enableSoundsDetail:
            return "Play a sound when an AI task completes or asks for approval."
        case .soundTaskCompleteVolume:
            return "Task Complete Volume"
        case .soundTaskCompleteVolumeDetail:
            return "Volume of the cue played when an AI task finishes."
        case .soundInputRequiredVolume:
            return "Approval Request Volume"
        case .soundInputRequiredVolumeDetail:
            return "Volume of the cue played when AI asks for approval or input."
        }
    }
}
