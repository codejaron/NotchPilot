import AppKit
import KeyboardShortcuts
import SwiftUI

struct GeneralSettingsTab: View {
    @ObservedObject private var generalSettings = SettingsStore.shared.general
    @ObservedObject private var aiSettings = SettingsStore.shared.ai
    @ObservedObject private var soundSettings = SettingsStore.shared.sound

    var body: some View {
        SettingsPage(title: AppStrings.text(.general, language: language)) {
            SettingsGroupSection(title: AppStrings.text(.language, language: language)) {
                SettingsPickerRow(
                    title: AppStrings.text(.interfaceLanguage, language: language),
                    detail: AppStrings.text(.interfaceLanguageDetail, language: language),
                    selection: $generalSettings.interfaceLanguage
                ) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName)
                            .tag(language)
                    }
                }
            }

            SettingsGroupSection(title: AppStrings.text(.startup, language: language)) {
                SettingsToggleRow(
                    title: AppStrings.text(.launchAtLogin, language: language),
                    detail: AppStrings.text(.launchAtLoginDetail, language: language),
                    isOn: $generalSettings.launchAtLoginEnabled
                )
            }

            SettingsGroupSection(title: AppStrings.text(.sneakPreviews, language: language)) {
                SettingsToggleRow(
                    title: AppStrings.text(.hideAllSneakPreviewsTitle, language: language),
                    detail: AppStrings.text(.hideAllSneakPreviewsDetail, language: language),
                    isOn: $generalSettings.activitySneakPreviewsHidden
                )

                SettingsRowDivider()

                SettingsRow(
                    title: AppStrings.text(.toggleHideAllPreviewsShortcutTitle, language: language),
                    detail: AppStrings.text(.toggleHideAllPreviewsShortcutDetail, language: language)
                ) {
                    KeyboardShortcuts.Recorder(for: .toggleHideAllPreviews)
                }
            }

            SettingsGroupSection(title: AppStrings.text(.approval, language: language)) {
                SettingsToggleRow(
                    title: AppStrings.text(.displayApprovalSneakNotifications, language: language),
                    detail: AppStrings.text(.displayApprovalSneakNotificationsDetail, language: language),
                    isOn: $aiSettings.approvalSneakNotificationsEnabled
                )
            }

            SettingsGroupSection(
                title: AppStrings.text(.soundFeedback, language: language)
            ) {
                SettingsToggleRow(
                    title: AppStrings.text(.enableSounds, language: language),
                    detail: AppStrings.text(.enableSoundsDetail, language: language),
                    isOn: $soundSettings.soundEnabled
                )

                if soundSettings.soundEnabled {
                    SettingsRowDivider()

                    SettingsActionRow(
                        title: AppStrings.text(.avoidDuplicateSounds, language: language),
                        detail: AppStrings.text(.avoidDuplicateSoundsDetail, language: language),
                        buttonTitle: AppStrings.text(.openNotificationSettings, language: language)
                    ) {
                        SystemNotificationSettingsOpener().openNotificationsPane()
                    }
                }

                SettingsRowDivider()

                SettingsRow(
                    title: AppStrings.text(.soundTaskCompleteVolume, language: language),
                    detail: AppStrings.text(.soundTaskCompleteVolumeDetail, language: language),
                    isEnabled: soundSettings.soundEnabled
                ) {
                    HStack(spacing: 8) {
                        Slider(value: $soundSettings.soundTaskCompleteVolume, in: 0 ... 1)
                            .frame(width: 130)
                            .disabled(soundSettings.soundEnabled == false)

                        Text("\(Int((soundSettings.soundTaskCompleteVolume * 100).rounded()))%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                }

                SettingsRowDivider()

                SettingsRow(
                    title: AppStrings.text(.soundInputRequiredVolume, language: language),
                    detail: AppStrings.text(.soundInputRequiredVolumeDetail, language: language),
                    isEnabled: soundSettings.soundEnabled
                ) {
                    HStack(spacing: 8) {
                        Slider(value: $soundSettings.soundInputRequiredVolume, in: 0 ... 1)
                            .frame(width: 130)
                            .disabled(soundSettings.soundEnabled == false)

                        Text("\(Int((soundSettings.soundInputRequiredVolume * 100).rounded()))%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
            }

            SettingsGroupSection(title: AppStrings.text(.application, language: language)) {
                SettingsActionRow(
                    title: AppStrings.text(.quitAppTitle, language: language),
                    detail: AppStrings.text(.quitAppDetail, language: language),
                    buttonTitle: AppStrings.text(.quitAppButton, language: language),
                    role: .destructive
                ) {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private var language: AppLanguage {
        generalSettings.interfaceLanguage
    }

}
