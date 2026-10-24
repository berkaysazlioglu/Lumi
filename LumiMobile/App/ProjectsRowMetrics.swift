import SwiftUI

/// The Projects text-size test control (A− / A+ in the list header): one
/// multiplier over the Apple rows' fonts and insets.
enum ProjectsRowMetrics {
    static let scaleKey = "projectsRowScale"
    static let scaleStep = 0.1
    static let scaleRange: ClosedRange<Double> = 0.8...1.6
}

/// Fold/unfold of a project group: quick, not instant.
enum ProjectsMotion {
    static let fold = Animation.easeInOut(duration: 0.25)
}
