import SwiftUI
import LumiMobileKit

/// Decision 132: a project card's header row is the drag handle. Press and hold
/// lifts it, moving the finger drags it; letting go over another card takes
/// that card's place, and the Mac's Projects follows.
///
/// Built on a long-press → drag gesture, not system drag and drop: `List`'s
/// collection view keeps every drop to itself — row drop targets, a drop
/// target on the list and `onInsert` over the project sections all stayed silent.
enum ProjectReorder {
    /// Header frames and the finger are both global: a named space set on the
    /// `List` doesn't reach a gesture inside its cells (it reported row-local points).
    static let liftDelay = 0.35

    /// The card whose header is the last one above `y`; above the first header,
    /// the first card. `nil` over the dragged project itself.
    static func target(at y: CGFloat, headers: [String: CGRect], dragging: String) -> String? {
        let sorted = headers.sorted { $0.value.minY < $1.value.minY }
        guard let card = sorted.last(where: { $0.value.minY <= y }) ?? sorted.first,
              card.key != dragging else { return nil }
        return card.key
    }
}

/// Header frames by project path, in global coordinates.
struct ProjectHeaderFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// The list's side of a reorder in progress.
struct ProjectDragState: Equatable {
    var path: String
    var location: CGPoint
    var target: String?
}

private struct ProjectDragSource: ViewModifier {
    let project: ProjectNode
    /// Off while searching: the filtered list hides the real neighbours.
    let isEnabled: Bool
    let onChanged: (_ path: String, _ location: CGPoint) -> Void
    let onEnded: () -> Void

    func body(content: Content) -> some View {
        let tracked = content.background(GeometryReader { geo in
            Color.clear.preference(key: ProjectHeaderFramesKey.self,
                                   value: [project.path: geo.frame(in: .global)])
        })
        if #available(iOS 18.0, *) {
            // A real UIKit long press: it fails as soon as the finger moves
            // early, so a swipe that starts on the header still scrolls the list.
            if isEnabled {
                tracked.gesture(ProjectLiftRecognizer(onChanged: { onChanged(project.path, $0) }, onEnded: onEnded))
            } else {
                tracked
            }
        } else {
            tracked.simultaneousGesture(swiftUIGesture, including: isEnabled ? .all : .subviews)
        }
    }

    /// iOS 17 fallback (no `UIGestureRecognizerRepresentable`).
    private var swiftUIGesture: some Gesture {
        LongPressGesture(minimumDuration: ProjectReorder.liftDelay)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                onChanged(project.path, drag.location)
            }
            .onEnded { _ in onEnded() }
    }
}

/// Press and hold, then follow the finger until it lifts (global points).
@available(iOS 18.0, *)
private struct ProjectLiftRecognizer: UIGestureRecognizerRepresentable {
    let onChanged: (CGPoint) -> Void
    let onEnded: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = ProjectReorder.liftDelay
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    /// Runs alongside the header's own button (a tap still folds the card);
    /// the list stops scrolling once a project is lifted (`scrollDisabled`).
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onChanged(context.converter.location(in: .global))
        case .ended, .cancelled, .failed:
            onEnded()
        default:
            break
        }
    }
}

/// What follows the finger: the project's badge and name on a capsule.
struct ProjectDragPreview: View {
    let project: ProjectNode

    private static let padding: CGFloat = 12
    private static let shadowRadius: CGFloat = 8

    var body: some View {
        HStack(spacing: AppleProjectsMetrics.rowSpacing) {
            AppleProjectBadge(appearance: project.appearance)
            Text(project.name).font(.subheadline.weight(.semibold)).lineLimit(1)
        }
        .padding(.horizontal, Self.padding)
        .padding(.vertical, Self.padding / 2)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: Self.shadowRadius)
        .allowsHitTesting(false)
    }
}

/// The swipe-left `Edit` of a project header (besides its `⋯` menu). No
/// long-press menu: press and hold belongs to the reorder.
private struct ProjectEditable: ViewModifier {
    let project: ProjectNode
    let actions: ProjectsListActions

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing) {
                Button { actions.edit(project) } label: {
                    Label("Edit", systemImage: "paintpalette")
                }
                .tint(.indigo)
                .disabled(!actions.isOnline)
            }
    }
}

extension View {
    func projectDragSource(_ project: ProjectNode, isEnabled: Bool,
                           onChanged: @escaping (_ path: String, _ location: CGPoint) -> Void,
                           onEnded: @escaping () -> Void) -> some View {
        modifier(ProjectDragSource(project: project, isEnabled: isEnabled, onChanged: onChanged, onEnded: onEnded))
    }

    func projectEditable(_ project: ProjectNode, actions: ProjectsListActions) -> some View {
        modifier(ProjectEditable(project: project, actions: actions))
    }
}
