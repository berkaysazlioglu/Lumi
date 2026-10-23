import Foundation
import LumiMobileKit

/// A checkout as the Apple list shows it: the agents left after search.
struct AppleCheckoutSlice: Identifiable {
    let checkout: CheckoutRowData
    let agents: [AgentRowData]
    var id: String { checkout.id }
}

/// A project as the Apple list shows it: the checkouts left after search.
struct AppleProjectSlice: Identifiable {
    let project: ProjectRowData
    let checkouts: [AppleCheckoutSlice]
    var id: String { project.id }
    var agentCount: Int { checkouts.reduce(0) { $0 + $1.agents.count } }
}

/// A loose-terminal folder (Projects ▸ Other) after search.
struct AppleOtherSlice: Identifiable {
    let group: OtherGroupRowData
    let agents: [AgentRowData]
    var id: String { group.id }
}

/// `.searchable` filter of the Apple Projects list. A matching project or
/// checkout keeps everything under it; otherwise only matching agents stay.
struct AppleProjectsFilter {
    let query: String

    private var needle: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isActive: Bool { !needle.isEmpty }

    func projects(_ tree: [ProjectRowData]) -> [AppleProjectSlice] {
        tree.compactMap { project in
            let keepAll = !isActive || matches(project.node.name)
            let checkouts = project.checkouts.compactMap { checkout(in: project, $0, keepAll: keepAll) }
            if keepAll { return AppleProjectSlice(project: project, checkouts: checkouts) }
            return checkouts.isEmpty ? nil : AppleProjectSlice(project: project, checkouts: checkouts)
        }
    }

    func others(_ groups: [OtherGroupRowData]) -> [AppleOtherSlice] {
        groups.compactMap { group in
            if !isActive || matches(group.node.label) { return AppleOtherSlice(group: group, agents: group.agents) }
            let agents = group.agents.filter { matches($0.title) }
            return agents.isEmpty ? nil : AppleOtherSlice(group: group, agents: agents)
        }
    }

    private func checkout(in project: ProjectRowData, _ checkout: CheckoutRowData,
                          keepAll: Bool) -> AppleCheckoutSlice? {
        let title = checkoutDisplayTitle(checkout.node, in: project.node)
        if keepAll || matches(title) || matches(checkout.node.branch) {
            return AppleCheckoutSlice(checkout: checkout, agents: checkout.agents)
        }
        let agents = checkout.agents.filter { matches($0.title) }
        return agents.isEmpty ? nil : AppleCheckoutSlice(checkout: checkout, agents: agents)
    }

    private func matches(_ text: String?) -> Bool {
        guard let text else { return false }
        return text.localizedStandardContains(needle)
    }
}
