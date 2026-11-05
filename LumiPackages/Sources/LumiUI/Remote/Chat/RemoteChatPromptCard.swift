import LumiKit
import SwiftUI

/// Uzak Claude'un bekleyen izin / soru kartı (telefonun `MobileChatPromptCard`'ının Mac
/// karşılığı). Onayda seçenekler (ilki birincil); soruda tek seçim dokununca gider,
/// çoklu seçim ve serbest metin `Send` ister; gruplu sorular tek `Send`'le toplanır.
/// Taslak `RemoteChatSession`'dadır — kart yeniden kurulsa da seçimler kalır.
struct RemoteChatPromptCard: View {
    let prompt: ChatPrompt
    let draft: PromptDraft
    let onDraftChange: (PromptDraft) -> Void
    let onAnswer: (RemotePromptAnswer) -> Void

    @State private var isSending = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: prompt.kind == .approval ? "shield.lefthalf.filled" : "questionmark.circle")
                    .foregroundStyle(Theme.warning)
                Text(title)
                    .font(Theme.Typography.mono(.body, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            if let detail = prompt.detail, !detail.isEmpty {
                Text(detail)
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(Self.detailLines)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            switch prompt.kind {
            case .approval: approvalButtons
            case .question:
                if prompt.questions.count > 1 { groupedQuestions } else { singleQuestion }
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgSurface)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.warning.opacity(Self.edgeOpacity)).frame(height: Theme.Stroke.hairline)
        }
    }

    private var title: String {
        prompt.kind == .question && prompt.questions.count > 1 ? prompt.questions[0].question : prompt.title
    }

    // MARK: - Onay

    private var approvalButtons: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(Array(prompt.options.enumerated()), id: \.element.id) { index, option in
                optionRow(option, index: index, mark: nil, isPrimary: index == 0) {
                    send(.option(option.id))
                }
            }
        }
    }

    // MARK: - Tek soru

    @ViewBuilder
    private var singleQuestion: some View {
        let selected = draft.selections[0] ?? []
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(Array(prompt.options.enumerated()), id: \.element.id) { index, option in
                optionRow(option, index: index, mark: mark(question: 0, option: index, multi: prompt.multiSelect),
                          isPrimary: false) {
                    if prompt.multiSelect {
                        onDraftChange(draft.toggling(question: 0, option: index, multiSelect: true))
                    } else {
                        onDraftChange(draft.toggling(question: 0, option: index, multiSelect: false))
                        send(.selections([RemotePromptSelection(indices: [index])]))
                    }
                }
            }
            if prompt.allowOther { otherField(question: 0) }
            if prompt.multiSelect || prompt.allowOther {
                LumiActionButton(title: selected.isEmpty ? "Send" : "Send (\(selected.count))", kind: .primary) {
                    send(.selections([RemotePromptSelection(indices: selected.sorted(), other: other(0))]))
                }
                .disabled(isSending || (selected.isEmpty && other(0) == nil))
            }
        }
    }

    // MARK: - Gruplu sorular

    private var groupedQuestions: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ForEach(Array(prompt.questions.enumerated()), id: \.element.id) { questionIndex, question in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(question.header ?? question.question)
                        .font(Theme.Typography.mono(.label, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    ForEach(Array(question.options.enumerated()), id: \.element.id) { optionIndex, option in
                        optionRow(option, index: optionIndex,
                                  mark: mark(question: questionIndex, option: optionIndex, multi: question.multiSelect),
                                  isPrimary: false) {
                            onDraftChange(draft.toggling(question: questionIndex, option: optionIndex,
                                                         multiSelect: question.multiSelect))
                        }
                    }
                    if question.allowOther { otherField(question: questionIndex) }
                }
            }
            LumiActionButton(title: "Send", kind: .primary) {
                send(.selections(prompt.questions.indices.map { index in
                    RemotePromptSelection(indices: (draft.selections[index] ?? []).sorted(), other: other(index))
                }))
            }
            .disabled(isSending || !isGroupedReady)
        }
    }

    /// Her soru bir seçim ya da boş olmayan metinle cevaplanmalı.
    private var isGroupedReady: Bool {
        prompt.questions.indices.allSatisfy { index in
            !(draft.selections[index] ?? []).isEmpty || other(index) != nil
        }
    }

    // MARK: - Parçalar

    private enum SelectionMark { case radio(Bool), checkbox(Bool) }

    private func mark(question: Int, option: Int, multi: Bool) -> SelectionMark {
        let isOn = draft.isSelected(question: question, option: option)
        return multi ? .checkbox(isOn) : .radio(isOn)
    }

    private func optionRow(_ option: ChatPromptOption, index: Int, mark: SelectionMark?, isPrimary: Bool,
                           action: @escaping () -> Void) -> some View {
        let isSelected: Bool
        let icon: String?
        switch mark {
        case .radio(let on)?: (isSelected, icon) = (on, on ? "largecircle.fill.circle" : "circle")
        case .checkbox(let on)?: (isSelected, icon) = (on, on ? "checkmark.square.fill" : "square")
        case nil: (isSelected, icon) = (false, nil)
        }
        return HoverReader { isHovering in
            Button(action: action) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                    Text("\(index + 1).")
                        .font(Theme.Typography.labelMono)
                        .foregroundStyle(Theme.textMuted)
                    if let icon {
                        Image(systemName: icon).foregroundStyle(isSelected ? Theme.accentPrimary : Theme.textSecondary)
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(option.label)
                            .font(Theme.Typography.mono(.body, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if let description = option.description, !description.isEmpty {
                            Text(description)
                                .font(Theme.Typography.labelMono)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(rowBackground(isSelected: isSelected, isPrimary: isPrimary, isHovering: isHovering),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(isSelected ? Theme.accentPrimary : .clear, lineWidth: Theme.Stroke.hairline))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isSending)
        }
    }

    private func rowBackground(isSelected: Bool, isPrimary: Bool, isHovering: Bool) -> Color {
        if isSelected || isPrimary { return Theme.accentVivid.opacity(isHovering ? Self.accentHover : Self.accentRest) }
        return isHovering ? Theme.bgElevated.opacity(Self.hoverOpacity) : Theme.bgElevated
    }

    private func otherField(question: Int) -> some View {
        TextField("Or type an answer…", text: Binding(
            get: { draft.texts[question] ?? "" },
            set: { onDraftChange(draft.withText($0, question: question)) }
        ), axis: .vertical)
        .textFieldStyle(.plain)
        .font(Theme.Typography.bodyMono)
        .lineLimit(1...Self.otherLines)
        .padding(Theme.Spacing.md)
        .background(Theme.bgDeep, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private func other(_ question: Int) -> String? {
        let text = (draft.texts[question] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Kart hub'ın `resolved` yayınıyla kalkar; çift göndermeyi önlemek için kilitlenir.
    private func send(_ answer: RemotePromptAnswer) {
        guard !isSending else { return }
        isSending = true
        onAnswer(answer)
    }

    private static let detailLines = 3
    private static let otherLines = 4
    private static let edgeOpacity = 0.6
    private static let accentRest = 0.22
    private static let accentHover = 0.32
    private static let hoverOpacity = 0.7
}
