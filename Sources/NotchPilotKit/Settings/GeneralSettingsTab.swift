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
