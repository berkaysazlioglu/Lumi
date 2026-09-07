import AppKit
import SwiftUI
import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiUI

/// Opt-in native render harness; does not touch real config, projects, or SCM.
@MainActor
final class WorkspaceRenderingTests: XCTestCase {
    func testRenderWorkspaceViews() async throws {
        guard ProcessInfo.processInfo.environment["LUMI_RENDER_WORKSPACE"] == "1" else {
            throw XCTSkip("Set LUMI_RENDER_WORKSPACE=1 to export native workspace views")
        }
        _ = NSApplication.shared
        let repoService = FakeRepoService()
        let project = Repo(name: "Unity Game", path: "/Projects/UnityGame", isGitRepo: false, source: .standalone)
        await repoService.setRepos([project])
        let workspaceService = FakeWorkspaceService()
        await workspaceService.setDefaultInspection(.success(WorkspaceSource(projectPath: project.path, scm: .plastic,
            branch: "/main", revision: "2588", repositorySpec: "game@team@cloud",
            destinationDirectory: "~/lumi/workspaces/Unity-Game", isUnityProject: true, hasLibrary: true)))
        let fixture = await ShellContextFixture.make(repo: repoService, workspaces: workspaceService)
        defer { fixture.stop() }
        fixture.context.workspaces.updateSidebarProjects([project.path])
        await fixture.context.repos.reload()
        let record = ProjectWorkspace(projectPath: project.path, path: NSTemporaryDirectory(), name: "Combat UI", branch: "/main/combat-ui", scm: .plastic)
        fixture.context.workspaces.updateRecords([record])
        fixture.context.navigation.openTab(record.path)
        try await render(ProjectsPanel().environment(\.shell, fixture.context), size: NSSize(width: 320, height: 580), name: "sidebar")
        fixture.context.dialogs.present(.createWorkspace(projectPath: project.path))
        try await render(CreateWorkspaceOverlay().environment(\.shell, fixture.context), size: NSSize(width: 900, height: 800), name: "create") {
            fixture.context.workspaces.name = "Inventory UI"
        }
        await workspaceService.setCreateDelay(.milliseconds(600))
        await workspaceService.setCreateOutcome(.success(WorkspaceCreateResult(workspace: ProjectWorkspace(
            projectPath: project.path, path: NSTemporaryDirectory() + "inventory-ui", name: "Inventory UI", branch: "/main", scm: .plastic))))
        fixture.context.startWorkspaceCreation()
        XCTAssertEqual(fixture.context.dialogs.active, .none)
        try await render(ProjectsPanel().environment(\.shell, fixture.context), size: NSSize(width: 320, height: 580), name: "loading")
        while fixture.context.workspaces.isCreating { try await Task.sleep(for: .milliseconds(10)) }

    }

    private func render<Content: View>(_ content: Content, size: NSSize, name: String,
                                       prepare: (() -> Void)? = nil) async throws {
        let host = NSHostingView(rootView: content.background(Theme.bgSurface).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(200))
        prepare?()
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/private/tmp/lumi-workspace-\(name).png"))
    }
}
