import SwiftUI
import LumiMobileKit
import LumiWire

/// Phase 3 / 3.1: interactive prompt card above the composer. Renders the latest pending item.
/// approval: title+detail + Allow(blue)/Deny(/don't-ask). question: single-select tap; multiSelect
/// toggle+Submit; allowOther free-text. Grouped multi-question (questions.count>1) = Phase 3.1 Task 8.
/// Task 3: draft state lives in AppModel.promptDrafts so selections survive leaving the chat.
struct MobileChatPromptCard: View {
    let prompt: ChatPrompt
    let maxHeight: CGFloat
    let draft: PromptDraft
    let onDraftChange: (PromptDraft) -> Void
    let onApproval: (String) -> Void                                   // optionId
    let onQuestion: ([(indices: [Int], other: String?)]) -> Void       // tek soru: [ (indices, other) ]
    @State private var sending = false

    private enum SelectionMark { case none, radio(Bool), checkbox(Bool) }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: prompt.kind == .approval ? "shield.lefthalf.filled" : "questionmark.circle")
                        Text(prompt.kind == .question && prompt.questions.count > 1 ? prompt.questions[0].question : prompt.title)
                            .font(.footnote.bold())
                    }
                    if let detail = prompt.detail, !detail.isEmpty {
                        Text(detail).font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                    }
                    switch prompt.kind {
                    case .approval: approvalButtons
                    case .question:
                        if prompt.questions.count > 1 {
                            groupedQuestionBody
                        } else {
                            questionBody
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: maxHeight)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color(uiColor: .systemBackground))
        }
    }

    // MARK: Approval

    private var approvalButtons: some View {
        ForEach(Array(prompt.options.enumerated()), id: \.element.id) { idx, opt in
            optionButton(opt.label, description: opt.description, primary: idx == 0) {
                guard !sending else { return }
                sending = true
                onApproval(opt.id)
            }
        }
    }

    // MARK: Question (single question)

    @ViewBuilder private var questionBody: some View {
        let selected = draft.selections[0] ?? []
        ForEach(Array(prompt.options.enumerated()), id: \.element.id) { idx, opt in
            optionButton(opt.label, description: opt.description, primary: false,
                         selection: prompt.multiSelect ? .checkbox(draft.isSelected(question: 0, option: idx))
                                                        : .radio(draft.isSelected(question: 0, option: idx))) {
                if prompt.multiSelect {
                    onDraftChange(draft.toggling(question: 0, option: idx, multiSelect: true))
                } else {
                    guard !sending else { return }
                    onDraftChange(draft.toggling(question: 0, option: idx, multiSelect: false))
                    sending = true
                    onQuestion([(indices: [idx], other: nil)])
                }
            }
        }
        if prompt.multiSelect {
            Button {
                guard !sending, !selected.isEmpty else { return }
                sending = true
                onQuestion([(indices: selected.sorted(), other: trimmedOther(for: 0))])
            } label: {
                Text("Send\(selected.isEmpty ? "" : " (\(selected.count))")")
                    .font(.footnote.bold()).frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(selected.isEmpty ? 0.08 : 0.22),
                                in: RoundedRectangle(cornerRadius: 6))
            }
            .disabled(sending || selected.isEmpty)
        }
        if prompt.allowOther { freeTextRow }
    }

    // MARK: Grouped question (multi-question; Component D)

    @ViewBuilder private var groupedQuestionBody: some View {
        ForEach(Array(prompt.questions.enumerated()), id: \.element.id) { qi, q in
            VStack(alignment: .leading, spacing: 4) {
                Text(q.header ?? q.question)
                    .font(.footnote.bold())
                    .padding(.top, qi == 0 ? 0 : 4)
                ForEach(Array(q.options.enumerated()), id: \.element.id) { oi, opt in
                    optionButton(opt.label, description: opt.description, primary: false,
                                 selection: q.multiSelect ? .checkbox(draft.isSelected(question: qi, option: oi))
                                                           : .radio(draft.isSelected(question: qi, option: oi))) {
                        onDraftChange(draft.toggling(question: qi, option: oi, multiSelect: q.multiSelect))
                    }
                }
                if q.allowOther {
                    HStack(spacing: 6) {
                        TextField("Or type…", text: Binding(
                            get: { draft.texts[qi] ?? "" },
                            set: { onDraftChange(draft.withText($0, question: qi)) }
                        ), axis: .vertical)
                            .textFieldStyle(.roundedBorder).lineLimit(1...3)
                    }
                }
            }
        }
        // Single Send button — collects all questions in order.
        // groupedReady: every question must be answered (a selection OR non-empty free-text).
        let groupedReady = prompt.questions.indices.allSatisfy { qi in
            !(draft.selections[qi] ?? []).isEmpty
                || !(draft.texts[qi] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        Button {
            guard !sending else { return }
            sending = true
            let result = prompt.questions.indices.map { qi -> (indices: [Int], other: String?) in
                (indices: (draft.selections[qi] ?? []).sorted(), other: trimmedOther(for: qi))
            }
            onQuestion(result)
        } label: {
            Text("Send")
                .font(.footnote.bold()).frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(groupedReady ? 0.22 : 0.08),
                            in: RoundedRectangle(cornerRadius: 6))
        }
        .disabled(sending || !groupedReady)
    }

    private var freeTextRow: some View {
        HStack(spacing: 6) {
            TextField("Or type…", text: Binding(
                get: { draft.texts[0] ?? "" },
                set: { onDraftChange(draft.withText($0, question: 0)) }
            ), axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(1...3)
            Button {
                guard !sending, !trimmedOtherIsEmpty(for: 0) else { return }
                sending = true
                onQuestion([(indices: prompt.multiSelect ? (draft.selections[0] ?? []).sorted() : [],
                            other: trimmedOther(for: 0))])
            } label: { Image(systemName: "arrow.up.circle.fill").font(.title3) }
                .disabled(sending || trimmedOtherIsEmpty(for: 0))
        }
    }

    // MARK: helpers

    private func trimmedOther(for question: Int) -> String? {
        let t = (draft.texts[question] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
    private func trimmedOtherIsEmpty(for question: Int) -> Bool { trimmedOther(for: question) == nil }

    private func selectionIcon(_ selection: SelectionMark) -> (isSelected: Bool, iconName: String?) {
        switch selection {
        case .none: return (false, nil)
        case .radio(let on): return (on, on ? "largecircle.fill.circle" : "circle")
        case .checkbox(let on): return (on, on ? "checkmark.square.fill" : "square")
        }
    }

    @ViewBuilder
    private func optionButton(_ label: String, description: String?, primary: Bool,
                              selection: SelectionMark = .none, action: @escaping () -> Void) -> some View {
        let (isSelected, iconName) = selectionIcon(selection)
        Button(action: action) {
            HStack(spacing: 8) {
                if let iconName {
                    Image(systemName: iconName)
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.footnote.bold())
                    if let d = description { Text(d).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
            }
            .padding(.vertical, 8).padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.22)
                                    : (primary ? Color.accentColor.opacity(0.18) : Color(uiColor: .secondarySystemBackground)),
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
            )
        }
        .disabled(sending)
    }
}
