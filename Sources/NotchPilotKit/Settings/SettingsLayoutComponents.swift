import SwiftUI

struct SettingsPage<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 24) {
                Text(title)
                    .font(.system(size: 28, weight: .semibold))

                content
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NotchPilotTheme.settingsWindowBackground(for: colorScheme))
    }
}

struct SettingsGroupSection<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let footer: String?
    let content: Content

    init(title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotchPilotTheme.settingsTextSecondary(for: colorScheme))

            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(NotchPilotTheme.settingsGroupFill(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(NotchPilotTheme.settingsGroupStroke(for: colorScheme), lineWidth: 1)
            )

            if let footer, footer.isEmpty == false {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(NotchPilotTheme.settingsTextSecondary(for: colorScheme))
                    .padding(.horizontal, 4)
            }
        }
    }
}

struct SettingsRow<Control: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let detail: String?
    let isEnabled: Bool
    let control: Control

    init(
        title: String,
        detail: String? = nil,
        isEnabled: Bool = true,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.detail = detail
        self.isEnabled = isEnabled
        self.control = control()
    }

    var body: some View {
        HStack(alignment: detail == nil ? .center : .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isEnabled ? .primary : NotchPilotTheme.settingsTextSecondary(for: colorScheme))

                if let detail, detail.isEmpty == false {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(NotchPilotTheme.settingsTextSecondary(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 16)

            control
                .frame(minWidth: 170, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .opacity(isEnabled ? 1 : 0.42)
    }
}

struct SettingsRowDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(NotchPilotTheme.settingsDivider(for: colorScheme))
            .frame(height: 1)
            .padding(.leading, 16)
    }
}

struct SettingsToggleRow: View {
    let title: String
    let detail: String?
    let isEnabled: Bool
    @Binding var isOn: Bool

    init(title: String, detail: String? = nil, isEnabled: Bool = true, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        self.isEnabled = isEnabled
        _isOn = isOn
    }

    var body: some View {
        SettingsRow(title: title, detail: detail, isEnabled: isEnabled) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!isEnabled)
        }
    }
}

struct SettingsStatusRow: View {
    let title: String
    let detail: String?
    let value: String
    let valueColor: Color

    init(title: String, detail: String? = nil, value: String, valueColor: Color = .secondary) {
        self.title = title
        self.detail = detail
        self.value = value
        self.valueColor = valueColor
    }

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(valueColor)
        }
    }
}

struct SettingsActionRow: View {
    let title: String
    let detail: String?
    let buttonTitle: String
    let role: ButtonRole?
    let isEnabled: Bool
    let action: () -> Void

    init(
        title: String,
        detail: String? = nil,
        buttonTitle: String,
        role: ButtonRole? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.detail = detail
        self.buttonTitle = buttonTitle
        self.role = role
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            if role == .destructive {
                Button(buttonTitle, role: role, action: action)
                    .buttonStyle(.borderedProminent)
                    .disabled(isEnabled == false)
            } else {
                Button(buttonTitle, role: role, action: action)
                    .buttonStyle(.bordered)
                    .disabled(isEnabled == false)
            }
        }
    }
}

struct SettingsPickerRow<SelectionValue: Hashable, PickerContent: View>: View {
    let title: String
    let detail: String?
    let isEnabled: Bool
    @Binding var selection: SelectionValue
    let pickerContent: PickerContent

    init(
        title: String,
        detail: String? = nil,
        selection: Binding<SelectionValue>,
        isEnabled: Bool = true,
        @ViewBuilder content: () -> PickerContent
    ) {
        self.title = title
        self.detail = detail
        self.isEnabled = isEnabled
        _selection = selection
        self.pickerContent = content()
    }

    var body: some View {
        SettingsRow(title: title, detail: detail, isEnabled: isEnabled) {
            Picker("", selection: $selection) {
                pickerContent
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 170)
            .disabled(isEnabled == false)
        }
    }
}

struct SettingsInlineMessage: View {
    @Environment(\.colorScheme) private var colorScheme

    let text: String
    let color: Color

    init(text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
