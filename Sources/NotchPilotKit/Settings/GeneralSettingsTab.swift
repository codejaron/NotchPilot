import AppKit
import SwiftUI

struct GeneralSettingsTab: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        SettingsPage(title: AppStrings.text(.general, language: store.interfaceLanguage)) {
            SettingsGroupSection(title: AppStrings.text(.language, language: store.interfaceLanguage)) {
                SettingsPickerRow(
                    title: AppStrings.text(.interfaceLanguage, language: store.interfaceLanguage),
                    detail: AppStrings.text(.interfaceLanguageDetail, language: store.interfaceLanguage),
                    selection: $store.interfaceLanguage
                ) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName)
                            .tag(language)
                    }
                }
            }

            SettingsGroupSection(title: AppStrings.text(.startup, language: store.interfaceLanguage)) {
                SettingsToggleRow(
                    title: AppStrings.text(.launchAtLogin, language: store.interfaceLanguage),
                    detail: AppStrings.text(.launchAtLoginDetail, language: store.interfaceLanguage),
                    isOn: $store.launchAtLoginEnabled
                )
            }

            SettingsGroupSection(title: AppStrings.text(.approval, language: store.interfaceLanguage)) {
                SettingsToggleRow(
                    title: AppStrings.text(.displayApprovalSneakNotifications, language: store.interfaceLanguage),
                    detail: AppStrings.text(.displayApprovalSneakNotificationsDetail, language: store.interfaceLanguage),
                    isOn: $store.approvalSneakNotificationsEnabled
                )
            }

            SettingsGroupSection(
                title: AppStrings.text(.soundFeedback, language: store.interfaceLanguage)
            ) {
                SettingsToggleRow(
                    title: AppStrings.text(.enableSounds, language: store.interfaceLanguage),
                    detail: AppStrings.text(.enableSoundsDetail, language: store.interfaceLanguage),
                    isOn: $store.soundEnabled
                )

                SettingsRowDivider()

                SettingsRow(
                    title: AppStrings.text(.soundTaskCompleteVolume, language: store.interfaceLanguage),
                    detail: AppStrings.text(.soundTaskCompleteVolumeDetail, language: store.interfaceLanguage),
                    isEnabled: store.soundEnabled
                ) {
                    HStack(spacing: 8) {
                        Slider(value: $store.soundTaskCompleteVolume, in: 0 ... 1)
                            .frame(width: 130)
                            .disabled(store.soundEnabled == false)

                        Text("\(Int((store.soundTaskCompleteVolume * 100).rounded()))%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                }

                SettingsRowDivider()

                SettingsRow(
                    title: AppStrings.text(.soundInputRequiredVolume, language: store.interfaceLanguage),
                    detail: AppStrings.text(.soundInputRequiredVolumeDetail, language: store.interfaceLanguage),
                    isEnabled: store.soundEnabled
                ) {
                    HStack(spacing: 8) {
                        Slider(value: $store.soundInputRequiredVolume, in: 0 ... 1)
                            .frame(width: 130)
                            .disabled(store.soundEnabled == false)

                        Text("\(Int((store.soundInputRequiredVolume * 100).rounded()))%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
            }

            SettingsGroupSection(title: AppStrings.text(.application, language: store.interfaceLanguage)) {
                SettingsActionRow(
                    title: AppStrings.text(.quitAppTitle, language: store.interfaceLanguage),
                    detail: AppStrings.text(.quitAppDetail, language: store.interfaceLanguage),
                    buttonTitle: AppStrings.text(.quitAppButton, language: store.interfaceLanguage),
                    role: .destructive
                ) {
                    NSApp.terminate(nil)
                }
            }
        }
    }

}
