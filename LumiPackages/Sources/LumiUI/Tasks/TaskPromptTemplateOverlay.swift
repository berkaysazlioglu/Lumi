import LumiKit
import LumiState
import SwiftUI

public extension OverlayID {
    /// Karar 137 eki: kaynak başına prompt ön eki / son eki.
    static let taskPromptTemplate = OverlayID("taskPromptTemplate")
}

/// Kaynağın prompt şablonu: ön ek + son ek, o kaynağın bir task'iyle canlı
/// önizleme. Ajan prompt'u (Start) ve `Copy as Prompt` bununla sarılır.
public struct TaskPromptTemplateOverlay: View {
    let store: TasksStore

    @State private var prefix = ""
    @State private var suffix = ""
    @State private var showsAgentPreview = true

    public init(store: TasksStore) {
        self.store = store
    }

    private static var panelWidth: CGFloat { Theme.scaled(820) }
    private static var panelHeight: CGFloat { Theme.scaled(600) }
    private static var editorHeight: CGFloat { Theme.scaled(110) }

    private var source: TasksStore.SourceState? { store.editingPromptTemplate.flatMap { store.state(of: $0) } }
    private var template: TaskPromptTemplate { TaskPromptTemplate(prefix: prefix, suffix: suffix) }

    /// Önizlemenin task'i: kaynağın ilk açık task'i, yoksa örnek.
    private var sampleTask: TaskItem {
        let entries = store.entries.filter { $0.source == source?.id }
        return (entries.first { $0.item.status != .done } ?? entries.first)?.item
            ?? TaskItem(id: "TASK-1", title: "Example task", status: .todo, updatedAt: Date(), body: "Task description.")
    }

    private var preview: String {
        let includeBody = source?.info?.canRead(.body) == true
        return showsAgentPreview
            ? TaskAgentPrompt.make(task: sampleTask, includeBody: includeBody, template: template)
            : TaskAgentPrompt.copyText(task: sampleTask, includeBody: includeBody, template: template)
    }

    public var body: some View {
        ModalOverlay(onDismiss: close) {
            Panel(variant: .modal) {
                VStack(spacing: 0) {
                    header
                    Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
                    HStack(alignment: .top, spacing: 0) {
                        editors
                            .padding(Theme.Spacing.xl)
                            .frame(maxWidth: .infinity)
                        Rectangle().fill(Theme.border).frame(width: Theme.Stroke.hairline)
                        previewPane
                            .padding(Theme.Spacing.xl)
                            .frame(maxWidth: .infinity)
                    }
                    Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
                    footer
                }
            }
            .frame(width: Self.panelWidth, height: Self.panelHeight)
        }
        .onAppear {
            prefix = source?.source.promptTemplate.prefix ?? ""
            suffix = source?.source.promptTemplate.suffix ?? ""
        }
    }

    private func close() {
        store.editingPromptTemplate = nil
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("Prompt Template")
                    .font(Theme.Typography.mono(.headline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Wraps every prompt made from \(source?.source.name ?? "this source")'s tasks")
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
            IconButton(systemName: "xmark", label: "Close", side: Theme.scaled(28), cornerRadius: Theme.Radius.md, action: close)
        }
        .padding(Theme.Spacing.xl)
    }

    private var editors: some View {
        VStack(alignment: .leading, spacing: 0) {
            LumiField(title: "Prefix", hint: "Before the task — conventions, context, constraints") {
                editor($prefix, placeholder: "e.g. This repo uses Swift 6 strict concurrency. Run swift test before submitting.")
            }
            LumiField(title: "Suffix", hint: "After the task — what to do at the end", isLast: true) {
                editor($suffix, placeholder: "e.g. Update CHANGELOG.md and open a draft PR.")
            }
        }
    }

    private func editor(_ text: Binding<String>, placeholder: String) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(Theme.Typography.bodyMono)
                    .foregroundStyle(Theme.textMuted)
                    .padding(Theme.Spacing.md)
                    .allowsHitTesting(false)
            }
            TextEditor(text: text)
                .font(Theme.Typography.bodyMono)
                .scrollContentBackground(.hidden)
                .padding(Theme.Spacing.sm)
        }
        .frame(height: Self.editorHeight)
        .background(Theme.bgDeep)
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.border, lineWidth: Theme.Stroke.hairline))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("PREVIEW · \(sampleTask.id)")
                    .font(Theme.Typography.ui(.caption, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                Spacer()
                SegmentedModeSwitch(
                    options: [true, false],
                    selection: $showsAgentPreview,
                    title: { $0 ? "Agent" : "Copy" },
                    help: { $0 ? "Prompt sent to Claude by Start (ends with the submit instruction)" : "Text copied by Copy as Prompt" },
                    accessibilityLabel: "Preview"
                )
                .frame(width: Theme.scaled(140))
            }
            ScrollView(.vertical) {
                Text(preview)
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.md)
            }
            .background(Theme.bgDeep)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            if !template.isEmpty {
                LumiActionButton(title: "Clear") {
                    prefix = ""
                    suffix = ""
                }
            }
            Spacer()
            LumiActionButton(title: "Cancel", action: close)
            LumiActionButton(title: "Save", kind: .primary) {
                if let id = source?.id { store.setPromptTemplate(template, for: id) }
                close()
            }
        }
        .padding(Theme.Spacing.xl)
    }
}
