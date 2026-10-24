import SwiftUI
import LumiMobileKit
import LumiWire

/// Edit Project… (decision 132): the Mac's Appearance… modal on the phone —
/// color, icon (SF Symbol from the shared list, or one emoji) and the root
/// checkout's title. Save sends the whole appearance; the list shows it at once
/// and the Mac's Projects follows.
struct ProjectAppearanceSheet: View {
    let project: ProjectNode
    let isOnline: Bool
    let onSave: (ProjectAppearance) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var color: ProjectColorID?
    @State private var iconKind: IconKind
    @State private var symbol: String
    @State private var emoji: String
    @State private var rootTitle: String

    private enum IconKind: String, CaseIterable, Identifiable {
        case symbol = "Symbol", emoji = "Emoji"
        var id: String { rawValue }
    }

    private static let previewBadgeSize: CGFloat = 56
    private static let swatchSize: CGFloat = 32
    private static let symbolCellSize: CGFloat = 40
    private static let gridSpacing: CGFloat = 12
    private static let selectionRingWidth: CGFloat = 2.5
    private static let selectionRingGap: CGFloat = 3
    private static let emojiFieldFont = Font.system(size: 28)

    init(project: ProjectNode, isOnline: Bool, onSave: @escaping (ProjectAppearance) -> Void) {
        self.project = project
        self.isOnline = isOnline
        self.onSave = onSave
        let appearance = project.appearance
        _color = State(initialValue: appearance.color)
        switch appearance.icon {
        case let .emoji(value)?:
            _iconKind = State(initialValue: .emoji)
            _symbol = State(initialValue: ProjectIdentityRules.defaultSymbol)
            _emoji = State(initialValue: value)
        case let .symbol(name)?:
            _iconKind = State(initialValue: .symbol)
            _symbol = State(initialValue: name)
            _emoji = State(initialValue: "")
        case nil:
            _iconKind = State(initialValue: .symbol)
            _symbol = State(initialValue: ProjectIdentityRules.defaultSymbol)
            _emoji = State(initialValue: "")
        }
        _rootTitle = State(initialValue: appearance.rootTitle ?? "")
    }

    // MARK: - Result

    private var validEmoji: String? { ProjectIdentityRules.emoji(from: emoji) }

    private var icon: ProjectIconID? {
        switch iconKind {
        case .symbol: symbol == ProjectIdentityRules.defaultSymbol ? nil : .symbol(symbol)
        case .emoji: validEmoji.map(ProjectIconID.emoji)
        }
    }

    /// `nil` while the emoji field holds something that isn't one emoji.
    private var result: ProjectAppearance? {
        if iconKind == .emoji && validEmoji == nil { return nil }
        return ProjectAppearance(color: color, icon: icon,
                                 rootTitle: ProjectIdentityRules.normalizedRootTitle(rootTitle))
    }

    private var canSave: Bool {
        guard isOnline, let result else { return false }
        return result != project.appearance
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                previewSection
                colorSection
                iconSection
                rootTitleSection
                Section {
                    Button("Reset to Default", role: .destructive, action: reset)
                        .disabled(result == ProjectAppearance.none)
                } footer: {
                    if !isOnline { Text("Your Mac is offline — changes can be saved once it reconnects.") }
                }
            }
            .navigationTitle("Edit Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let result else { return }
                        onSave(result)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
        .lumiThemed()
    }

    private var previewSection: some View {
        Section {
            VStack(spacing: Self.gridSpacing / 2) {
                AppleProjectBadge(appearance: result ?? ProjectAppearance(color: color),
                                  baseSize: Self.previewBadgeSize)
                Text(project.name).font(.headline).lineLimit(1)
                Label(ProjectIdentityRules.normalizedRootTitle(rootTitle) ?? ProjectIdentityRules.defaultRootTitle,
                      systemImage: "house")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Self.gridSpacing / 2)
            .accessibilityElement(children: .combine)
        }
    }

    private var colorSection: some View {
        Section("Color") {
            LazyVGrid(columns: grid(Self.swatchSize), spacing: Self.gridSpacing) {
                swatch(nil)
                ForEach(ProjectColorID.allCases, id: \.self) { swatch($0) }
            }
            .padding(.vertical, Self.gridSpacing / 2)
        }
    }

    private var iconSection: some View {
        Section {
            Picker("Icon", selection: $iconKind) {
                ForEach(IconKind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)
            switch iconKind {
            case .symbol:
                LazyVGrid(columns: grid(Self.symbolCellSize), spacing: Self.gridSpacing) {
                    ForEach(ProjectIdentityRules.symbolNames, id: \.self) { symbolCell($0) }
                }
                .padding(.vertical, Self.gridSpacing / 2)
            case .emoji:
                TextField("😀", text: $emoji)
                    .font(Self.emojiFieldFont)
                    .multilineTextAlignment(.center)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Emoji")
            }
        } header: {
            Text("Icon")
        } footer: {
            if iconKind == .emoji {
                Text(emoji.isEmpty || validEmoji != nil ? "Use the emoji keyboard — exactly one emoji."
                                                        : "That isn't a single emoji.")
                    .foregroundStyle(emoji.isEmpty || validEmoji != nil ? Color.secondary : Color.red)
            }
        }
    }

    private var rootTitleSection: some View {
        Section {
            TextField(ProjectIdentityRules.defaultRootTitle, text: $rootTitle)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: rootTitle) { _, value in
                    if value.count > ProjectIdentityRules.rootTitleMaxLength {
                        rootTitle = String(value.prefix(ProjectIdentityRules.rootTitleMaxLength))
                    }
                }
        } header: {
            Text("Root Checkout Title")
        } footer: {
            Text("Shown instead of “\(ProjectIdentityRules.defaultRootTitle)” for the project's own folder. "
                 + "Up to \(ProjectIdentityRules.rootTitleMaxLength) characters.")
        }
    }

    // MARK: - Cells

    private func grid(_ cell: CGFloat) -> [GridItem] {
        [GridItem(.adaptive(minimum: cell, maximum: cell + Self.gridSpacing), spacing: Self.gridSpacing)]
    }

    private func swatch(_ id: ProjectColorID?) -> some View {
        let isSelected = color == id
        return Button { color = id } label: {
            ZStack {
                Circle().fill(AppleProjectBadge.color(id))
                if id == nil {
                    Image(systemName: "slash.circle").font(.body.weight(.semibold)).foregroundStyle(.white)
                } else if isSelected {
                    Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(.white)
                }
            }
            .frame(width: Self.swatchSize, height: Self.swatchSize)
            .padding(Self.selectionRingGap)
            .overlay(Circle().strokeBorder(isSelected ? Color.accentColor : .clear,
                                           lineWidth: Self.selectionRingWidth))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(id.map { $0.rawValue.capitalized } ?? "No Color")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func symbolCell(_ name: String) -> some View {
        let isSelected = symbol == name
        return Button { symbol = name } label: {
            Image(systemName: name)
                .font(.body.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .primary)
                .frame(width: Self.symbolCellSize, height: Self.symbolCellSize)
                .background(isSelected ? AppleProjectBadge.color(color) : Color(.tertiarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func reset() {
        color = nil
        iconKind = .symbol
        symbol = ProjectIdentityRules.defaultSymbol
        emoji = ""
        rootTitle = ""
    }
}
