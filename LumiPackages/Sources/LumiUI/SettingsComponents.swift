import SwiftUI

/// Settings modal'ının v1 paritesindeki ortak görsel parçaları (globals.css
/// .settings-* kuralları). Tek dosyada toplanır — yalnız SettingsView kullanır.

/// v1 .settings-field: başlık (12/600 primary) + hint (11 muted) + kontrol;
/// alt ayraç son alanda gizlenir.
struct SettingsField<Content: View>: View {
    let title: String
    let hint: String?
    var isLast = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .padding(.bottom, hint == nil ? 8 : 2)
            if let hint {
                Text(hint)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
                    .padding(.bottom, 8)
            }
            content()
            if !isLast {
                Rectangle()
                    .fill(Theme.border.opacity(0.3))
                    .frame(height: 1)
                    .padding(.top, 24)
            }
        }
        .padding(.bottom, isLast ? 0 : 24)
    }
}

/// v1 .settings-section başlığı + açıklaması.
struct SettingsSectionTitle: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
            Text(description)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.bottom, 24)
    }
}

/// v1 .settings-input: bgDeep zemin, focus'ta accent kenarlık.
struct SettingsTextInput: View {
    @Binding var text: String
    var placeholder = ""
    var width: CGFloat?

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Theme.textPrimary)
            .focused($isFocused)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: width)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .background(Theme.bgDeep)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isFocused ? Theme.accentVivid : Theme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// v1 .settings-browse-btn: elevated zemin, hover'da accent-deep.
struct SettingsBrowseButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 12, design: .monospaced))
            }
            .foregroundStyle(isHovering ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovering ? Theme.accentDeep : Theme.bgElevated)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isHovering ? Theme.accentDeep : Theme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// v1 .settings-theme-btn segmented grubu: pasif bgDeep, aktif accent kenarlık +
/// accent metin + soluk accent zemin; disabled %40 soluk.
struct SettingsSegmented<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let label: String
        var isEnabled = true
        var id: String { label }
    }

    let options: [Option]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options) { option in
                segment(option)
            }
        }
    }

    private func segment(_ option: Option) -> some View {
        let isActive = selection == option.value
        return Button {
            if option.isEnabled { selection = option.value }
        } label: {
            Text(option.label)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(isActive ? Theme.accentPrimary : Theme.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isActive ? Theme.accentVivid.opacity(0.1) : Theme.bgDeep)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isActive ? Theme.accentVivid : Theme.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!option.isEnabled)
        .opacity(option.isEnabled ? 1 : 0.4)
    }
}

/// v1 .settings-toggle: 40×22 pill, açıkken accent-vivid + beyaz thumb sağda.
struct SettingsToggleSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 11)
                    .fill(isOn ? Theme.accentVivid : Theme.bgDeep)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11)
                            .stroke(isOn ? Theme.accentVivid : Theme.border, lineWidth: 1)
                    )
                    .frame(width: 40, height: 22)
                Circle()
                    .fill(isOn ? Color.white : Theme.textSecondary)
                    .frame(width: 16, height: 16)
                    .padding(.horizontal, 2)
            }
            .frame(width: 40, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isOn)
    }
}

/// v1 .settings-toggle-row: solda içerik (başlık + hint), sağda toggle.
struct SettingsToggleRow<Trailing: View>: View {
    let title: String
    let hint: String
    @Binding var isOn: Bool
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        hint: String,
        isOn: Binding<Bool>,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.hint = hint
        self._isOn = isOn
        self.trailing = trailing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                    Text(hint)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer(minLength: 0)
                SettingsToggleSwitch(isOn: $isOn)
            }
            if isOn {
                trailing()
            }
        }
    }
}

/// v1 .shortcut-kbd: keycap görünümü (alt kenar 2px + gölge ile derinlik).
struct Keycap: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Theme.textSecondary)
            .frame(minWidth: 24, minHeight: 24)
            .padding(.horizontal, 6)
            .background(Theme.bgSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .overlay(alignment: .bottom) {
                // border-bottom-width: 2px karşılığı — keycap derinliği
                Rectangle().fill(Theme.border).frame(height: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: .black.opacity(0.2), radius: 0, y: 1)
    }
}
