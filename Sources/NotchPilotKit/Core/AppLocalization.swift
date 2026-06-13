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

enum AppTextKey: String, CaseIterable {
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
    case blockHTTPLyricsSources
    case blockHTTPLyricsSourcesDetail
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
    case enableDevinPlugin
    case enableDevinPluginDetail
    case devinIntegration
    case devinIntegrationDetail
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
    case stopSessionDetection
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
    case avoidDuplicateSounds
    case avoidDuplicateSoundsDetail
    case openNotificationSettings
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
        AppStringCatalog.shared.text(for: key, language: language) ?? key.rawValue
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
            return "\(metricName)低于 \(valueText) 时触发变色或冒出"
        case (.zhHans, false):
            return "\(metricName)超过 \(valueText) 时触发变色或冒出"
        case (.english, true):
            return "Tints or pops out when \(metricName.lowercased()) drops below \(valueText)"
        case (.english, false):
            return "Tints or pops out when \(metricName.lowercased()) exceeds \(valueText)"
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
        return title
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
        case "Allow":
            return language == .zhHans ? "允许" : title
        case "Cancel":
            return language == .zhHans ? "取消" : title
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
        case "Allow":
            return "允许"
        case "Cancel":
            return "取消"
        case "Yes, and don't ask again for this command in this session":
            return "是，且本会话不再询问这条命令"
        case "Allow for this chat":
            return "仅在此对话中允许"
        case "Always allow":
            return "始终允许"
        case "Don't ask again":
            return "不再询问"
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
                return "是，且对于以后续内容开头的命令不再询问 \(prefix)"
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

}
