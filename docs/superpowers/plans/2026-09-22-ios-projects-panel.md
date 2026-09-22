# iOS Projects Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the phone's flat session list with a Projects tree (`Project → Checkout → Agent`) that mirrors the Mac's Projects panel live, and let the phone add a Mac-known project to favorites via `+`.

**Architecture:** The Mac broadcasts a new `projects` snapshot (favorites + checkouts + per-checkout agent ids) alongside the existing `sessions` stream; the relay caches/forwards it (and includes it in `welcome`); the phone renders the tree, joins agent ids against the `sessions` stream, and navigates into the existing terminal/chat views. `add_project` rides the existing generic `command` frame (already forwarded), so no new relay allowlist entry is needed.

**Tech Stack:** Swift 6 (LumiMobileKit + LumiRemote), SwiftUI (LumiMobile app), TypeScript (RelayServer, Node test runner via `npm test`).

## Global Constraints

- Wire envelope is `{v:1, type, payload}`; incoming decode MUST stay tolerant — an unknown field or enum value returns nil/skips, never throws (design §12.2).
- `~/.lumi` JSON/YAML formats are read/written unchanged (decision 9); config mutation goes only through `ConfigServicing.updateConfig`.
- New `SessionMeta` fields (`provider`, `lastActivityAt`) are **additive and optional** — an old Mac that omits them must still decode.
- Mac is the single source of truth for favorites; the phone holds no independent favorites list.
- Blocking waits never run on the cooperative pool (decision 86) — not relevant here (all async), but do not introduce `waitUntilExit`/`sleep` loops.
- Phone dev/test: `cd LumiMobile/LumiMobileKit && swift test`. Mac dev/test: `cd LumiPackages && swift test`. Relay: `cd RelayServer && npm test`.
- Work happens on branch `feat/ios-projects-panel` (commits to `main` are forbidden on this machine).

---

## File Structure

**Phone (`LumiMobile/LumiMobileKit/Sources/LumiMobileKit/`)**
- `Models.swift` — modify `SessionMeta` (+`provider`, `+lastActivityAt`); add `ProjectNode`, `CheckoutNode`, `ProjectsSnapshot`; modify `Welcome` (+`projects`, `+addable`).
- `PhoneProtocol.swift` — decode `type:"projects"`; add `CommandAction.addProject`; encode it in `commandFrame`; add `ServerMessage.projects`.
- `ProjectTree.swift` (create) — pure helpers: `assembleProjectTree`, `terminalNeedsAttention`, `PhoneRelativeTime`, row data structs.
- `AppModel.swift` — hold `projectsSnapshot`; route `.projects` + `welcome.projects`; `addProject(path:)`; command-result handling.

**Phone app (`LumiMobile/App/`)**
- `ProjectsView.swift` (create) — tree UI + `AddProjectSheet`.
- `RootView.swift` — show `ProjectsView` when paired.

**Mac (`LumiPackages/Sources/LumiRemote/`)**
- `RemoteProtocol.swift` — `SessionMeta` (+`provider`, `+lastActivityAt`) in `toDict`; add `projectsPayload`.
- `RemoteCommandHandler.swift` — `add_project` action (+`config` dependency).
- `RemoteService.swift` — store app `config`; `sendProjects()`; observe `config.events()`; call on welcome/terminal/config change; add provider/lastActivity to `sendSessions`.

**Mac composition (`LumiPackages/Sources/LumiAppCore/Features/`)**
- `RemoteFeatureAssembly.swift` — pass `services.config` to `RemoteService`.

**Relay (`RelayServer/`)**
- `src/registry.ts` — `Room.projects` field + init.
- `src/bridge.ts` — `fromMac` `projects` cache+broadcast; include `projects`/`addable` in phone `welcome`.

**Tests**
- Phone: `Tests/LumiMobileKitTests/ProjectsDecodeTests.swift`, `ProjectTreeTests.swift`, additions to `EndToEndWireTests.swift`.
- Mac: `LumiPackages/Tests/LumiRemoteTests/` — projects payload + command handler + service broadcast tests.
- Relay: additions to `RelayServer/test/bridge.test.ts`.

---

## Task 1: Phone wire types — SessionMeta fields, tree models, decode

**Files:**
- Modify: `LumiMobile/LumiMobileKit/Sources/LumiMobileKit/Models.swift`
- Modify: `LumiMobile/LumiMobileKit/Sources/LumiMobileKit/PhoneProtocol.swift`
- Test: `LumiMobile/LumiMobileKit/Tests/LumiMobileKitTests/ProjectsDecodeTests.swift` (create)

**Interfaces:**
- Produces: `SessionMeta.provider: String?`, `SessionMeta.lastActivityAt: Double?`; `ProjectNode`, `CheckoutNode`, `ProjectsSnapshot`; `ServerMessage.projects(ProjectsSnapshot)`; `Welcome.projects: [ProjectNode]?`, `Welcome.addable: [Repo]?`.

- [ ] **Step 1: Write the failing test**

Create `ProjectsDecodeTests.swift`:

```swift
import XCTest
@testable import LumiMobileKit

final class ProjectsDecodeTests: XCTestCase {
    func testProjectsMessageDecodes() {
        let frame = """
        {"v":1,"type":"projects","payload":{
          "projects":[{"name":"unco-forge","path":"/p/unco","checkouts":[
            {"kind":"original","title":"main","scm":"git","path":"/p/unco","agentIds":["t1","t2"]},
            {"kind":"workspace","title":"review","branch":"feat/review","scm":"git","path":"/p/wt","agentIds":["t3"]}
          ]}],
          "addable":[{"name":"orca","path":"/p/orca"}]
        }}
        """
        guard case .projects(let snap)? = PhoneProtocol.decodeServerMessage(frame) else {
            return XCTFail("expected .projects")
        }
        XCTAssertEqual(snap.projects.count, 1)
        XCTAssertEqual(snap.projects[0].checkouts.count, 2)
        XCTAssertEqual(snap.projects[0].checkouts[0].agentIds, ["t1", "t2"])
        XCTAssertEqual(snap.projects[0].checkouts[1].branch, "feat/review")
        XCTAssertEqual(snap.addable.map(\.path), ["/p/orca"])
    }

    func testProjectsToleratesMissingAddableAndUnknownEnums() {
        let frame = """
        {"v":1,"type":"projects","payload":{"projects":[
          {"name":"x","path":"/x","checkouts":[
            {"kind":"future-kind","title":"main","scm":"svn","path":"/x","agentIds":[]}
          ]}
        ]}}
        """
        guard case .projects(let snap)? = PhoneProtocol.decodeServerMessage(frame) else {
            return XCTFail("expected .projects")
        }
        XCTAssertTrue(snap.addable.isEmpty)
        XCTAssertEqual(snap.projects[0].checkouts[0].kind, "future-kind")
        XCTAssertEqual(snap.projects[0].checkouts[0].scm, "svn")
    }

    func testSessionMetaDecodesWithAndWithoutNewFields() {
        let withFields = """
        {"v":1,"type":"sessions","payload":{"sessions":[
          {"id":"t1","repoName":"r","status":"idle","cols":80,"rows":24,"provider":"claude","lastActivityAt":1790000000000}
        ]}}
        """
        guard case .sessions(let a)? = PhoneProtocol.decodeServerMessage(withFields) else {
            return XCTFail("sessions")
        }
        XCTAssertEqual(a[0].provider, "claude")
        XCTAssertEqual(a[0].lastActivityAt, 1_790_000_000_000)

        let withoutFields = """
        {"v":1,"type":"sessions","payload":{"sessions":[
          {"id":"t2","repoName":"r","status":"idle","cols":80,"rows":24}
        ]}}
        """
        guard case .sessions(let b)? = PhoneProtocol.decodeServerMessage(withoutFields) else {
            return XCTFail("sessions")
        }
        XCTAssertNil(b[0].provider)
        XCTAssertNil(b[0].lastActivityAt)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd LumiMobile/LumiMobileKit && swift test --filter ProjectsDecodeTests`
Expected: FAIL — `.projects` case / `ProjectsSnapshot` / `provider` do not exist (compile error).

- [ ] **Step 3: Add the model types**

In `Models.swift`, add `provider` + `lastActivityAt` to `SessionMeta`. Update the initializer, `CodingKeys`, and `init(from:)`:

```swift
public struct SessionMeta: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let repoName: String
    public let status: String
    public let title: String?
    public let model: String?
    public let cols: Int
    public let rows: Int
    public let kind: String?
    /// Agent provider ("claude" | "codex"); nil for plain shell or older Mac (tree glyph).
    public let provider: String?
    /// Last activity, epoch ms; nil if omitted by an older Mac (relative-time label).
    public let lastActivityAt: Double?

    public init(id: String, repoName: String, status: String,
                title: String? = nil, model: String? = nil,
                cols: Int, rows: Int, kind: String? = nil,
                provider: String? = nil, lastActivityAt: Double? = nil) {
        self.id = id; self.repoName = repoName; self.status = status
        self.title = title; self.model = model; self.cols = cols; self.rows = rows
        self.kind = kind; self.provider = provider; self.lastActivityAt = lastActivityAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, repoName, status, title, model, cols, rows, kind, provider, lastActivityAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            repoName: try c.decode(String.self, forKey: .repoName),
            status: try c.decode(String.self, forKey: .status),
            title: try c.decodeIfPresent(String.self, forKey: .title),
            model: try c.decodeIfPresent(String.self, forKey: .model),
            cols: try c.decode(Int.self, forKey: .cols),
            rows: try c.decode(Int.self, forKey: .rows),
            kind: try c.decodeIfPresent(String.self, forKey: .kind),
            provider: try c.decodeIfPresent(String.self, forKey: .provider),
            lastActivityAt: try c.decodeIfPresent(Double.self, forKey: .lastActivityAt)
        )
    }

    public var badge: Badge { (SessionStatus(rawValue: status) ?? .idle).badge }
}
```

Add the tree types (anywhere in `Models.swift`):

```swift
public struct CheckoutNode: Decodable, Sendable, Equatable, Identifiable {
    public let kind: String        // "original" | "workspace" (unknown tolerated)
    public let title: String
    public let branch: String?
    public let scm: String         // "git" | "plastic" | "none" (unknown tolerated)
    public let path: String
    public let agentIds: [String]
    public var id: String { path }

    public init(kind: String, title: String, branch: String?, scm: String, path: String, agentIds: [String]) {
        self.kind = kind; self.title = title; self.branch = branch
        self.scm = scm; self.path = path; self.agentIds = agentIds
    }

    private enum CodingKeys: String, CodingKey { case kind, title, branch, scm, path, agentIds }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try c.decodeIfPresent(String.self, forKey: .kind) ?? "original",
            title: try c.decodeIfPresent(String.self, forKey: .title) ?? "",
            branch: try c.decodeIfPresent(String.self, forKey: .branch),
            scm: try c.decodeIfPresent(String.self, forKey: .scm) ?? "none",
            path: try c.decode(String.self, forKey: .path),
            agentIds: try c.decodeIfPresent([String].self, forKey: .agentIds) ?? []
        )
    }
}

public struct ProjectNode: Decodable, Sendable, Equatable, Identifiable {
    public let name: String
    public let path: String
    public let checkouts: [CheckoutNode]
    public var id: String { path }

    public init(name: String, path: String, checkouts: [CheckoutNode]) {
        self.name = name; self.path = path; self.checkouts = checkouts
    }

    private enum CodingKeys: String, CodingKey { case name, path, checkouts }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try c.decodeIfPresent(String.self, forKey: .name) ?? "",
            path: try c.decode(String.self, forKey: .path),
            checkouts: try c.decodeIfPresent([CheckoutNode].self, forKey: .checkouts) ?? []
        )
    }
}

public struct ProjectsSnapshot: Decodable, Sendable, Equatable {
    public let projects: [ProjectNode]
    public let addable: [Repo]

    public init(projects: [ProjectNode], addable: [Repo]) {
        self.projects = projects; self.addable = addable
    }

    private enum CodingKeys: String, CodingKey { case projects, addable }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            projects: try c.decodeIfPresent([ProjectNode].self, forKey: .projects) ?? [],
            addable: try c.decodeIfPresent([Repo].self, forKey: .addable) ?? []
        )
    }
}
```

In `Welcome`, add `projects` + `addable` (additive, optional). Add to the `CodingKeys` and `init(from:)`:

```swift
    public let projects: [ProjectNode]?
    public let addable: [Repo]?
```
Extend `Welcome.init(from:)` with:
```swift
        self.projects = try c.decodeIfPresent([ProjectNode].self, forKey: .projects)
        self.addable = try c.decodeIfPresent([Repo].self, forKey: .addable)
```
and add `case projects, addable` to `Welcome`'s `CodingKeys`, and the two params to its memberwise `init` (default nil).

- [ ] **Step 4: Add the decode case**

In `PhoneProtocol.swift`, add to `ServerMessage`:
```swift
    case projects(ProjectsSnapshot)
```
In `decodeServerMessage`'s `switch type`, add:
```swift
        case "projects": return decodePayload(ProjectsSnapshot.self).map(ServerMessage.projects)
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd LumiMobile/LumiMobileKit && swift test --filter ProjectsDecodeTests`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add LumiMobile/LumiMobileKit/Sources/LumiMobileKit/Models.swift \
        LumiMobile/LumiMobileKit/Sources/LumiMobileKit/PhoneProtocol.swift \
        LumiMobile/LumiMobileKit/Tests/LumiMobileKitTests/ProjectsDecodeTests.swift
git commit -m "feat(mobile): projects wire types + SessionMeta provider/lastActivityAt"
```

---

## Task 2: Phone — `add_project` command encode

**Files:**
- Modify: `LumiMobile/LumiMobileKit/Sources/LumiMobileKit/PhoneProtocol.swift`
- Test: `LumiMobile/LumiMobileKit/Tests/LumiMobileKitTests/ProtocolTests.swift`

**Interfaces:**
- Produces: `CommandAction.addProject(path: String)`, encoded as `{action:"add_project", path}` inside a `command` frame.

- [ ] **Step 1: Write the failing test**

Append to `ProtocolTests.swift`:

```swift
    func testAddProjectCommandFrameEncodes() {
        let frame = PhoneProtocol.commandFrame(
            OutgoingCommand(commandId: "c1", action: .addProject(path: "/p/orca")))
        let data = frame.data(using: .utf8)!
        let obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let payload = obj["payload"] as! [String: Any]
        XCTAssertEqual(obj["type"] as? String, "command")
        XCTAssertEqual(payload["action"] as? String, "add_project")
        XCTAssertEqual(payload["path"] as? String, "/p/orca")
        XCTAssertEqual(payload["commandId"] as? String, "c1")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd LumiMobile/LumiMobileKit && swift test --filter ProtocolTests`
Expected: FAIL — `.addProject` is not a member of `CommandAction`.

- [ ] **Step 3: Implement**

In `PhoneProtocol.swift`, add to `CommandAction`:
```swift
    case addProject(path: String)
```
In `commandFrame`'s `switch command.action`, add:
```swift
        case .addProject(let path):
            payload["action"] = "add_project"
            payload["path"] = path
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd LumiMobile/LumiMobileKit && swift test --filter ProtocolTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add LumiMobile/LumiMobileKit/Sources/LumiMobileKit/PhoneProtocol.swift \
        LumiMobile/LumiMobileKit/Tests/LumiMobileKitTests/ProtocolTests.swift
git commit -m "feat(mobile): add_project command frame"
```

---

## Task 3: Phone — pure tree helpers (assembly, attention, relative time)

**Files:**
- Create: `LumiMobile/LumiMobileKit/Sources/LumiMobileKit/ProjectTree.swift`
- Test: `LumiMobile/LumiMobileKit/Tests/LumiMobileKitTests/ProjectTreeTests.swift` (create)

**Interfaces:**
- Consumes: `ProjectsSnapshot`, `SessionMeta`, `Badge` (Task 1).
- Produces: `AgentRowData`, `CheckoutRowData`, `ProjectRowData`; `func assembleProjectTree(snapshot:sessions:selectedId:) -> [ProjectRowData]`; `func terminalNeedsAttention(status:isSelected:) -> Bool`; `enum PhoneRelativeTime { static func shortLabel(_:now:) -> String }`.

- [ ] **Step 1: Write the failing test**

Create `ProjectTreeTests.swift`:

```swift
import XCTest
@testable import LumiMobileKit

final class ProjectTreeTests: XCTestCase {
    private func snap() -> ProjectsSnapshot {
        ProjectsSnapshot(projects: [
            ProjectNode(name: "p", path: "/p", checkouts: [
                CheckoutNode(kind: "original", title: "main", branch: nil, scm: "git",
                             path: "/p", agentIds: ["t1", "missing", "t2"])
            ])
        ], addable: [])
    }

    func testAssemblyJoinsSessionsInAgentIdOrderAndSkipsMissing() {
        let sessions = [
            SessionMeta(id: "t2", repoName: "p", status: "idle", cols: 80, rows: 24, provider: "codex"),
            SessionMeta(id: "t1", repoName: "p", status: "working", cols: 80, rows: 24, provider: "claude"),
        ]
        let tree = assembleProjectTree(snapshot: snap(), sessions: sessions, selectedId: nil)
        let agents = tree[0].checkouts[0].agents
        XCTAssertEqual(agents.map(\.id), ["t1", "t2"])   // agentIds order; "missing" skipped
        XCTAssertEqual(agents[0].provider, "claude")
        XCTAssertEqual(agents[0].badge, .working)
    }

    func testAttention() {
        XCTAssertTrue(terminalNeedsAttention(status: "waiting-unseen", isSelected: false))
        XCTAssertFalse(terminalNeedsAttention(status: "waiting-unseen", isSelected: true))
        XCTAssertFalse(terminalNeedsAttention(status: "waiting-seen", isSelected: false))
        XCTAssertFalse(terminalNeedsAttention(status: "idle", isSelected: false))
    }

    func testRelativeTime() {
        let now = 1_000_000.0 * 1000     // pick a base in ms
        XCTAssertEqual(PhoneRelativeTime.shortLabel(now, now: now), "now")
        XCTAssertEqual(PhoneRelativeTime.shortLabel(now - 5 * 60_000, now: now), "5m")
        XCTAssertEqual(PhoneRelativeTime.shortLabel(now - 3 * 3_600_000, now: now), "3h")
        XCTAssertEqual(PhoneRelativeTime.shortLabel(nil, now: now), "")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd LumiMobile/LumiMobileKit && swift test --filter ProjectTreeTests`
Expected: FAIL — helpers undefined.

- [ ] **Step 3: Implement**

Create `ProjectTree.swift`:

```swift
import Foundation

public struct AgentRowData: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let provider: String?
    public let badge: Badge
    public let lastActivityAt: Double?
    public let needsAttention: Bool
}

public struct CheckoutRowData: Sendable, Equatable, Identifiable {
    public let node: CheckoutNode
    public let agents: [AgentRowData]
    public var id: String { node.path }
}

public struct ProjectRowData: Sendable, Equatable, Identifiable {
    public let node: ProjectNode
    public let checkouts: [CheckoutRowData]
    public var id: String { node.path }
}

/// Attention rule (Mac `TerminalAttention` parity, decision 77): an unselected
/// terminal whose turn closed unseen / is awaiting a decision. `waiting-seen`
/// is NOT re-highlighted.
public func terminalNeedsAttention(status: String, isSelected: Bool) -> Bool {
    guard !isSelected else { return false }
    return status == "waiting-unseen" || status == "waiting-focused"
}

/// Builds the view-ready tree by joining each checkout's `agentIds` against the
/// live `sessions` map. Order comes from `agentIds` (the Mac already sorted);
/// ids not yet present in `sessions` are skipped (subscribe/broadcast race guard).
public func assembleProjectTree(snapshot: ProjectsSnapshot,
                                sessions: [SessionMeta],
                                selectedId: String?) -> [ProjectRowData] {
    let byId = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return snapshot.projects.map { project in
        ProjectRowData(node: project, checkouts: project.checkouts.map { checkout in
            let agents = checkout.agentIds.compactMap { id -> AgentRowData? in
                guard let s = byId[id] else { return nil }
                return AgentRowData(
                    id: s.id,
                    title: (s.title?.isEmpty == false ? s.title! : s.repoName),
                    provider: s.provider,
                    badge: s.badge,
                    lastActivityAt: s.lastActivityAt,
                    needsAttention: terminalNeedsAttention(status: s.status, isSelected: s.id == selectedId))
            }
            return CheckoutRowData(node: checkout, agents: agents)
        })
    }
}

/// Compact relative-time label ("now" / "5m" / "3h" / "2d"). All arithmetic in ms.
public enum PhoneRelativeTime {
    public static func shortLabel(_ epochMs: Double?, now: Double) -> String {
        guard let epochMs else { return "" }
        let secs = max(0, (now - epochMs) / 1000)
        if secs < 45 { return "now" }
        let mins = Int((secs / 60).rounded())
        if mins < 60 { return "\(mins)m" }
        let hrs = mins / 60
        if hrs < 24 { return "\(hrs)h" }
        return "\(hrs / 24)d"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd LumiMobile/LumiMobileKit && swift test --filter ProjectTreeTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add LumiMobile/LumiMobileKit/Sources/LumiMobileKit/ProjectTree.swift \
        LumiMobile/LumiMobileKit/Tests/LumiMobileKitTests/ProjectTreeTests.swift
git commit -m "feat(mobile): pure project-tree assembly + attention + relative-time helpers"
```

---

## Task 4: Phone — AppModel projects state, routing, and add_project

**Files:**
- Modify: `LumiMobile/LumiMobileKit/Sources/LumiMobileKit/AppModel.swift`
- Test: `LumiMobile/LumiMobileKit/Tests/LumiMobileKitTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `ProjectsSnapshot`, `assembleProjectTree`, `CommandAction.addProject` (Tasks 1–3), `FakeRelayClient` (existing test fake).
- Produces: `AppModel.projectsSnapshot: ProjectsSnapshot`, `AppModel.projectTree: [ProjectRowData]`, `AppModel.addProject(path:) async`, `AppModel.addProjectError: String?`.

- [ ] **Step 1: Write the failing test**

Append to `AppModelTests.swift` (uses the existing `FakeRelayClient`; follow the file's existing `makeModel()`/setup pattern — replicate whatever helper the other tests in this file use to build an `AppModel` + `FakeRelayClient`):

```swift
    @MainActor
    func testProjectsMessagePopulatesTree() async {
        let (model, client) = makeModel()   // same helper the other AppModelTests use
        await model.start()
        client.emit(.message(.sessions([
            SessionMeta(id: "t1", repoName: "p", status: "waiting-unseen", cols: 80, rows: 24, provider: "claude"),
        ])))
        client.emit(.message(.projects(ProjectsSnapshot(projects: [
            ProjectNode(name: "p", path: "/p", checkouts: [
                CheckoutNode(kind: "original", title: "main", branch: nil, scm: "git",
                             path: "/p", agentIds: ["t1"])
            ])
        ], addable: [Repo(name: "orca", path: "/p/orca")]))))

        XCTAssertEqual(model.projectTree.count, 1)
        XCTAssertEqual(model.projectTree[0].checkouts[0].agents.map(\.id), ["t1"])
        XCTAssertTrue(model.projectTree[0].checkouts[0].agents[0].needsAttention)
        XCTAssertEqual(model.projectsSnapshot.addable.map(\.path), ["/p/orca"])
        XCTAssertTrue(model.macOnline)
    }

    @MainActor
    func testAddProjectSendsCommand() async {
        let (model, client) = makeModel()
        await model.start()
        await model.addProject(path: "/p/orca")
        let sent = client.sentCommands   // adapt to the fake's recorded-command accessor
        XCTAssertTrue(sent.contains { if case .addProject(let p) = $0.action { return p == "/p/orca" } else { return false } })
    }
```

> Note: match `makeModel()`, `client.emit`, and the sent-command accessor to the exact names already used in `AppModelTests.swift` / `RelayClientTests.swift`. If a `makeModel` helper does not exist, build the model inline exactly as the neighboring tests do.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd LumiMobile/LumiMobileKit && swift test --filter AppModelTests`
Expected: FAIL — `projectTree` / `projectsSnapshot` / `addProject` undefined and `.projects` not handled.

- [ ] **Step 3: Implement**

In `AppModel.swift`, add stored state near `sessions`:
```swift
    /// Latest projects tree snapshot (favorites mirror from the Mac).
    public private(set) var projectsSnapshot = ProjectsSnapshot(projects: [], addable: [])
    /// Last add_project failure (surfaced by the add sheet).
    public private(set) var addProjectError: String?
    private var addProjectCommandIds: Set<String> = []
```

Add a derived tree accessor near `orderedSessions`:
```swift
    /// View-ready tree: joins the snapshot's agent ids against live `sessions`.
    public var projectTree: [ProjectRowData] {
        assembleProjectTree(snapshot: projectsSnapshot, sessions: sessions, selectedId: activeSessionId)
    }
```

In `handle(_:)`, add a case:
```swift
        case .projects(let snap):
            macOnline = true
            projectsSnapshot = snap
```

In the `.welcome` case, after the existing `repos`/`sessions` handling, add:
```swift
            if let projects = welcome.projects {
                projectsSnapshot = ProjectsSnapshot(projects: projects, addable: welcome.addable ?? [])
            }
```

In `describe(_:)`, add:
```swift
        case .projects(let snap):
            "projects count=\(snap.projects.count)"
```

Add the command method near `deleteSession`:
```swift
    /// Adds a Mac-known project to favorites (the one phone-side write). Not
    /// optimistic — the Mac appends the favorite and rebroadcasts `projects`.
    public func addProject(path: String) async {
        commandCounter += 1
        let commandId = "ph-\(commandCounter)"
        addProjectCommandIds.insert(commandId)
        addProjectError = nil
        let ok = await client.send(command: OutgoingCommand(commandId: commandId, action: .addProject(path: path)))
        DiagLog.shared.log("model", "out \(commandId) add_project ok=\(ok)")
        if !ok { addProjectCommandIds.remove(commandId); addProjectError = "no connection" }
    }
```

In the `.commandResult` case, add — as the FIRST check, before the `branchRequestIds` block — a handler for add_project results:
```swift
            if addProjectCommandIds.remove(result.commandId) != nil {
                if !result.ok { addProjectError = result.error ?? "couldn't add project" }
                return
            }
```

In `unpair()`, reset the new state alongside the others:
```swift
        projectsSnapshot = ProjectsSnapshot(projects: [], addable: [])
        addProjectError = nil
        addProjectCommandIds = []
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd LumiMobile/LumiMobileKit && swift test --filter AppModelTests`
Expected: PASS.

- [ ] **Step 5: Run the full phone kit suite (no regressions)**

Run: `cd LumiMobile/LumiMobileKit && swift test`
Expected: PASS (all existing tests + the new ones).

- [ ] **Step 6: Commit**

```bash
git add LumiMobile/LumiMobileKit/Sources/LumiMobileKit/AppModel.swift \
        LumiMobile/LumiMobileKit/Tests/LumiMobileKitTests/AppModelTests.swift
git commit -m "feat(mobile): AppModel projects tree + add_project"
```

---

## Task 5: Phone — ProjectsView UI + AddProjectSheet + RootView

**Files:**
- Create: `LumiMobile/App/ProjectsView.swift`
- Modify: `LumiMobile/App/RootView.swift`
- Modify: `LumiMobile/LumiMobile.xcodeproj` (regenerate — see Step 4)

**Interfaces:**
- Consumes: `AppModel.projectTree`, `.projectsSnapshot`, `.addProject(path:)`, `.macOnline`, `.connection`, `PhoneRelativeTime`, `AgentRowData`/`CheckoutRowData`/`ProjectRowData`, and the existing `TerminalSessionView` / `MobileChatView` navigation (see `SessionListView` for the routing pattern).
- Produces: `ProjectsView(model:)`.

> UI is validated by the tested helpers (Tasks 3–4); this task keeps the view thin — it renders `model.projectTree` and routes taps. There is no unit test step; verification is a device build + the manual checklist at the end of the plan.

- [ ] **Step 1: Create `ProjectsView.swift`**

```swift
import SwiftUI
import UIKit
import LumiMobileKit

struct ProjectsView: View {
    let model: AppModel
    @State private var collapsedProjects: Set<String> = []
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                if !model.macOnline { offlineBanner }
                if model.projectTree.isEmpty {
                    emptyState
                } else {
                    ForEach(model.projectTree) { project in
                        projectSection(project)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Projects")
            .navigationDestination(for: String.self) { sessionId in
                if model.isChatSession(sessionId) {
                    MobileChatView(model: model, sessionId: sessionId)
                } else {
                    TerminalSessionView(model: model, sessionId: sessionId)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { connectionDot }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .disabled(!model.macOnline || model.projectsSnapshot.addable.isEmpty)
                }
            }
            .sheet(isPresented: $showAdd) { AddProjectSheet(model: model) }
        }
    }

    @ViewBuilder
    private func projectSection(_ project: ProjectRowData) -> some View {
        let collapsed = collapsedProjects.contains(project.id)
        Section {
            if !collapsed {
                ForEach(project.checkouts) { checkout in
                    CheckoutRowView(checkout: checkout)
                }
            }
        } header: {
            Button {
                if !collapsedProjects.insert(project.id).inserted { collapsedProjects.remove(project.id) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder").foregroundStyle(.purple)
                    Text(project.node.name).font(.headline).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .textCase(nil)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.plus").font(.title).foregroundStyle(.secondary)
            Text("No projects yet").foregroundStyle(.secondary)
            Text("Add a project on the Mac, or use +").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32)
    }

    private var offlineBanner: some View {
        Label("Mac offline", systemImage: "desktopcomputer.trianglebadge.exclamationmark")
            .font(.callout).foregroundStyle(.orange)
    }

    private var connectionDot: some View {
        Circle()
            .fill(model.connection == .connected ? .green : model.connection == .connecting ? .yellow : .red)
            .frame(width: 10, height: 10)
            .accessibilityLabel("Relay connection")
    }
}

private struct CheckoutRowView: View {
    let checkout: CheckoutRowData
    @State private var agentsCollapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: checkout.node.kind == "workspace" ? "arrow.triangle.branch" : "house")
                    .font(.caption).foregroundStyle(.secondary)
                Text(checkout.node.title).font(.subheadline)
                if let branch = checkout.node.branch, !branch.isEmpty {
                    Text(branch).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                if agentsCollapsed, let lead = checkout.agents.first {
                    HStack(spacing: 4) {
                        Circle().fill(color(lead.badge)).frame(width: 8, height: 8)
                        Text("\(checkout.agents.count)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if checkout.agents.count > 1 {
                Button { agentsCollapsed.toggle() } label: {
                    HStack {
                        Text("\(checkout.agents.count) agents").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: agentsCollapsed ? "chevron.right" : "chevron.down")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain).padding(.leading, 24)
            }
            if !agentsCollapsed || checkout.agents.count == 1 {
                ForEach(checkout.agents) { agent in AgentRowView(agent: agent) }
            }
        }
    }

    private func color(_ badge: Badge) -> Color {
        switch badge { case .idle: .gray; case .working: .blue; case .waiting: .orange; case .error: .red }
    }
}

private struct AgentRowView: View {
    let agent: AgentRowData

    var body: some View {
        NavigationLink(value: agent.id) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 8, height: 8)
                Image(systemName: providerSymbol).font(.caption2).foregroundStyle(.secondary)
                Text(agent.title)
                    .font(.subheadline)
                    .foregroundStyle(agent.needsAttention ? Color.orange : .secondary)
                    .lineLimit(1).truncationMode(.tail)
                Spacer()
                Text(PhoneRelativeTime.shortLabel(agent.lastActivityAt, now: Date().timeIntervalSince1970 * 1000))
                    .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
            }
            .padding(.leading, 24)
            .overlay(alignment: .leading) {
                if agent.needsAttention {
                    RoundedRectangle(cornerRadius: 2).fill(Color.orange).frame(width: 3)
                }
            }
        }
    }

    private var providerSymbol: String {
        switch agent.provider {
        case "claude": "sparkle"
        case "codex": "chevron.left.forwardslash.chevron.right"
        default: "circle.fill"
        }
    }

    private var color: Color {
        switch agent.badge { case .idle: .gray; case .working: .blue; case .waiting: .orange; case .error: .red }
    }
}

private struct AddProjectSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(model.projectsSnapshot.addable) { repo in
                Button {
                    Task { await model.addProject(path: repo.path) }
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "folder").foregroundStyle(.purple)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(repo.name).foregroundStyle(.primary)
                            Text(repo.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
            }
            .overlay {
                if model.projectsSnapshot.addable.isEmpty {
                    Text("No more projects to add").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
```

- [ ] **Step 2: Point `RootView` at `ProjectsView`**

In `RootView.swift`, change the paired branch:
```swift
        if model.isPaired {
            ProjectsView(model: model)
        } else {
            PairingView(model: model)
        }
```

- [ ] **Step 3: Verify `MobileChatView` / `TerminalSessionView` initializers**

Confirm the `MobileChatView(model:sessionId:)` and `TerminalSessionView(model:sessionId:)` initializers match those used in `SessionListView.swift`'s `navigationDestination`. If `SessionListView` routed all sessions to `TerminalSessionView`, mirror that exactly (drop the `isChatSession` branch) — do not invent an initializer.

- [ ] **Step 4: Regenerate the Xcode project and build**

The `.xcodeproj` is generated (memory: `ios-xcodeproj-is-generated` — new `.swift` files require regeneration or the build breaks with a stale project):
```bash
cd LumiMobile && xcodegen generate
```
Then build for the simulator:
```bash
xcodebuild -project LumiMobile.xcodeproj -scheme LumiMobile \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add LumiMobile/App/ProjectsView.swift LumiMobile/App/RootView.swift LumiMobile/LumiMobile.xcodeproj
git commit -m "feat(mobile): Projects tree view + AddProjectSheet"
```

---

## Task 6: Mac — RemoteProtocol SessionMeta fields + projectsPayload

**Files:**
- Modify: `LumiPackages/Sources/LumiRemote/RemoteProtocol.swift`
- Test: `LumiPackages/Tests/LumiRemoteTests/RemoteProtocolTests.swift` (create if absent; otherwise append)

**Interfaces:**
- Produces: `SessionMeta(..., provider: String?, lastActivityAt: Double?)` with those keys in `toDict()`; `RemoteProtocol.projectsPayload(projects:addable:) -> [String: Any]`.

- [ ] **Step 1: Write the failing test**

Create/append `RemoteProtocolTests.swift`:

```swift
import XCTest
@testable import LumiRemote

final class RemoteProtocolTests: XCTestCase {
    func testSessionMetaToDictIncludesProviderAndActivity() {
        let meta = SessionMeta(id: "t1", repoName: "r", status: "idle", cols: 80, rows: 24,
                               provider: "claude", lastActivityAt: 1_790_000_000_000)
        let d = meta.toDict()
        XCTAssertEqual(d["provider"] as? String, "claude")
        XCTAssertEqual(d["lastActivityAt"] as? Double, 1_790_000_000_000)
    }

    func testSessionMetaToDictOmitsNilProvider() {
        let meta = SessionMeta(id: "t1", repoName: "r", status: "idle", cols: 80, rows: 24)
        let d = meta.toDict()
        XCTAssertNil(d["provider"])
        XCTAssertNil(d["lastActivityAt"])
    }

    func testProjectsPayloadShape() {
        let payload = RemoteProtocol.projectsPayload(
            projects: [["name": "p", "path": "/p", "checkouts": []]],
            addable: [["name": "orca", "path": "/p/orca"]])
        XCTAssertEqual((payload["projects"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((payload["addable"] as? [[String: String]])?.first?["path"], "/p/orca")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd LumiPackages && swift test --filter RemoteProtocolTests`
Expected: FAIL — extra `SessionMeta` params / `projectsPayload` undefined.

- [ ] **Step 3: Implement**

In `RemoteProtocol.swift`, extend `SessionMeta`:
```swift
    let provider: String?
    let lastActivityAt: Double?

    init(id: String, repoName: String, status: String,
         title: String? = nil, model: String? = nil,
         cols: Int, rows: Int, kind: String? = nil,
         provider: String? = nil, lastActivityAt: Double? = nil) {
        self.id = id; self.repoName = repoName; self.status = status
        self.title = title; self.model = model; self.cols = cols; self.rows = rows
        self.kind = kind; self.provider = provider; self.lastActivityAt = lastActivityAt
    }
```
In `toDict()`, before `return d`, append:
```swift
        if let provider { d["provider"] = provider }
        if let lastActivityAt { d["lastActivityAt"] = lastActivityAt }
```
Add the payload helper to `RemoteProtocol`:
```swift
    /// `projects` payload: favorites tree + addable pool (Mac → phone).
    static func projectsPayload(projects: [[String: Any]], addable: [[String: String]]) -> [String: Any] {
        ["projects": projects, "addable": addable]
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd LumiPackages && swift test --filter RemoteProtocolTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add LumiPackages/Sources/LumiRemote/RemoteProtocol.swift \
        LumiPackages/Tests/LumiRemoteTests/RemoteProtocolTests.swift
git commit -m "feat(remote): SessionMeta provider/lastActivityAt + projectsPayload"
```

---

## Task 7: Mac — RemoteCommandHandler `add_project`

**Files:**
- Modify: `LumiPackages/Sources/LumiRemote/RemoteCommandHandler.swift`
- Modify: `LumiPackages/Sources/LumiRemote/RemoteService.swift` (pass `config` into the handler)
- Test: `LumiPackages/Tests/LumiRemoteTests/` — the file where `RemoteCommandHandler` is tested (create `RemoteCommandHandlerTests.swift` if none exists)

**Interfaces:**
- Consumes: `any ConfigServicing` (has `config() async -> AppConfig`, `updateConfig(_:) async throws`), `any RepoServicing`.
- Produces: `RemoteCommandHandler(... config:)`; handling of `{action:"add_project", path}` → appends `path` to `AppConfig.sidebarProjectPaths`.

- [ ] **Step 1: Write the failing test**

Create `RemoteCommandHandlerTests.swift`. Use the existing `LumiTestSupport` fakes for `TerminalServicing`, `RepoServicing`, `ConfigServicing` — check `LumiPackages/Sources/LumiTestSupport/` for the exact fake names (e.g. `FakeConfigService`, `FakeRepoService`) and constructors, and match them:

```swift
import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiRemote

final class RemoteCommandHandlerTests: XCTestCase {
    @MainActor
    func testAddProjectAppendsFavorite() async {
        let config = FakeConfigService()                 // adapt to the real fake name
        let repos = FakeRepoService(repos: [Repo(name: "orca", path: "/p/orca", isGitRepo: true, source: .standalone)])
        let handler = RemoteCommandHandler(
            terminal: FakeTerminalService(), trust: NoopClaudeWorkspaceTrust(),
            repos: repos, workspaces: NoopWorkspaceServicing(), config: config)

        let result = await handler.handle(["commandId": "c1", "action": "add_project", "path": "/p/orca"])
        XCTAssertEqual(result["ok"] as? Bool, true)
        let saved = await config.config().sidebarProjectPaths
        XCTAssertTrue(saved.contains("/p/orca"))
    }

    @MainActor
    func testAddProjectRejectsUnknownRepo() async {
        let handler = RemoteCommandHandler(
            terminal: FakeTerminalService(), trust: NoopClaudeWorkspaceTrust(),
            repos: FakeRepoService(repos: []), workspaces: NoopWorkspaceServicing(), config: FakeConfigService())
        let result = await handler.handle(["commandId": "c1", "action": "add_project", "path": "/nope"])
        XCTAssertEqual(result["ok"] as? Bool, false)
        XCTAssertEqual(result["error"] as? String, "unknown_repo")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd LumiPackages && swift test --filter RemoteCommandHandlerTests`
Expected: FAIL — `RemoteCommandHandler` has no `config:` parameter and no `add_project` case.

- [ ] **Step 3: Implement**

In `RemoteCommandHandler.swift`, add the dependency:
```swift
    private let config: any ConfigServicing
```
Add `config` to `init` (default a fake is not needed here — it's constructed by `RemoteService`; give it no default to force wiring):
```swift
    init(terminal: any TerminalServicing, trust: any ClaudeWorkspaceTrusting,
         chatSessions: any ChatSessionServicing = NoopChatSessionService(),
         repos: any RepoServicing = NoopRepoServicing(),
         workspaces: any WorkspaceServicing = NoopWorkspaceServicing(),
         config: any ConfigServicing) {
        self.terminal = terminal; self.trust = trust; self.chatSessions = chatSessions
        self.repos = repos; self.workspaces = workspaces; self.config = config
    }
```
Add the case to `handle`'s switch (before `default`):
```swift
        case "add_project":
            return await addProject(payload, commandId: commandId)
```
Add the method:
```swift
    private func addProject(_ payload: [String: Any], commandId: Any) async -> sending [String: Any] {
        let path = payload["path"] as? String ?? ""
        guard !path.isEmpty, await repos.repos().contains(where: { $0.path == path }) else {
            return ["commandId": commandId, "ok": false, "error": "unknown_repo"]
        }
        do {
            try await config.updateConfig { c in
                if !c.sidebarProjectPaths.contains(path) { c.sidebarProjectPaths.append(path) }
            }
            return ["commandId": commandId, "ok": true]
        } catch {
            return ["commandId": commandId, "ok": false, "error": "\(error)"]
        }
    }
```
In `RemoteService.swift`'s `init`, pass config into the handler. Add a stored property first:
```swift
    private let appConfig: any ConfigServicing
```
Add a param to `RemoteService.init` (default a real requirement — see Task 8 wiring):
```swift
        config: any ConfigServicing,
```
and inside init:
```swift
        self.appConfig = config
        self.commandHandler = RemoteCommandHandler(
            terminal: terminal, trust: trust, chatSessions: chatSessions,
            repos: repos, workspaces: workspaces, config: config)
```

> The `RemoteService.init` signature change ripples to its call site (Task 8) and any existing `RemoteService(...)` in tests — add `config:` there. If Task 8 has not run yet, temporarily default `config` to a `LumiTestSupport` fake ONLY in existing tests, not in production.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd LumiPackages && swift test --filter RemoteCommandHandlerTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add LumiPackages/Sources/LumiRemote/RemoteCommandHandler.swift \
        LumiPackages/Sources/LumiRemote/RemoteService.swift \
        LumiPackages/Tests/LumiRemoteTests/RemoteCommandHandlerTests.swift
git commit -m "feat(remote): add_project command → append favorite"
```

---

## Task 8: Mac — RemoteService projects broadcast + config observation + composition

**Files:**
- Modify: `LumiPackages/Sources/LumiRemote/RemoteService.swift`
- Modify: `LumiPackages/Sources/LumiAppCore/Features/RemoteFeatureAssembly.swift`
- Test: `LumiPackages/Tests/LumiRemoteTests/RemoteServiceProjectsTests.swift` (create)

**Interfaces:**
- Consumes: `appConfig: any ConfigServicing` (Task 7), `terminal.terminals: [TerminalMeta]` (has `repoPath`, `provider: AgentProvider?`, `status`, `displayTitle`, `lastActivityAt: Date`), `repos.repos()`, `RemoteProtocol.projectsPayload` (Task 6), the fake `RelayConnecting` used by existing `RemoteService` tests.
- Produces: `RemoteService.sendProjects()` broadcasts `type:"projects"`; broadcast fires on welcome, terminal spawn/exit/status change, and favorites/workspaces config change; `sendSessions` now includes provider + lastActivityAt.

- [ ] **Step 1: Write the failing test**

Create `RemoteServiceProjectsTests.swift`. Model it on the existing `RemoteService` tests (find them under `LumiPackages/Tests/LumiRemoteTests/` — reuse their fake `RelayConnecting` that records `send(type:payload:)` calls, and their `RemoteService` construction helper). Assert that a `welcome` inbound triggers a `projects` broadcast derived from a favorited repo:

```swift
import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiRemote

final class RemoteServiceProjectsTests: XCTestCase {
    @MainActor
    func testWelcomeBroadcastsProjectsFromFavorites() async {
        // Arrange: one favorited repo, no workspaces, no terminals.
        let config = FakeConfigService(initial: AppConfig.defaults.with {  // adapt to real fake API
            $0.sidebarProjectPaths = ["/p/unco"]
        })
        let repos = FakeRepoService(repos: [Repo(name: "unco", path: "/p/unco", isGitRepo: true, source: .standalone)])
        let connection = FakeRelayConnection()             // records sends; adapt to real fake
        let service = makeRemoteService(config: config, repos: repos, connection: connection)
        await service.start()

        // Act: simulate a phone welcome arriving from the relay.
        connection.injectInbound(.message(type: "welcome", payload: [:]))
        await Task.yield()

        // Assert: a `projects` frame was sent with the favorited repo + an original checkout.
        let projectsSend = connection.sent.first { $0.type == "projects" }
        let payload = try XCTUnwrap(projectsSend?.payload)
        let projects = try XCTUnwrap(payload["projects"] as? [[String: Any]])
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0]["path"] as? String, "/p/unco")
        let checkouts = try XCTUnwrap(projects[0]["checkouts"] as? [[String: Any]])
        XCTAssertEqual(checkouts.first?["kind"] as? String, "original")
    }
}
```

> Adapt `FakeConfigService`, `FakeRelayConnection`, `injectInbound`, `makeRemoteService`, and the `.sent` accessor to whatever the existing LumiRemote tests already use. If the existing tests inject inbound relay messages a different way, follow that mechanism exactly.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd LumiPackages && swift test --filter RemoteServiceProjectsTests`
Expected: FAIL — no `projects` frame is ever sent.

- [ ] **Step 3: Implement `sendProjects` and wire the triggers**

In `RemoteService.swift`, add a config-observation task field near `terminalTask`:
```swift
    private var configTask: Task<Void, Never>?
```
Add the broadcast method (near `sendSessions`):
```swift
    /// Favorites tree (decision 48–51 parity): favorited projects → checkouts
    /// (original + managed workspaces) → agent ids grouped by checkout path.
    /// v1: original checkout's real branch is omitted (nil) to avoid pulling the
    /// git/plastic stores into RemoteService; workspace checkouts carry their branch.
    /// Agents are ordered most-recent-first (attention-priority ordering is a v2 refinement).
    private func sendProjects() async {
        let cfg = await appConfig.config()
        let allRepos = await repos.repos()
        let repoByPath = Dictionary(allRepos.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let managedPaths = Set(cfg.workspaces.map(\.path))

        func agentIds(at path: String) -> [String] {
            terminal.terminals
                .filter { $0.repoPath == path }
                .sorted { $0.lastActivityAt > $1.lastActivityAt }
                .map { $0.id.description }
        }

        var projects: [[String: Any]] = []
        for favPath in cfg.sidebarProjectPaths {
            guard let repo = repoByPath[favPath] else { continue }
            var checkouts: [[String: Any]] = [[
                "kind": "original", "title": "main",
                "scm": repo.isGitRepo ? "git" : "none",
                "path": repo.path, "agentIds": agentIds(at: repo.path),
            ]]
            for ws in cfg.workspaces where ws.projectPath == favPath {
                checkouts.append([
                    "kind": "workspace", "title": ws.name, "branch": ws.branch,
                    "scm": ws.scm.rawValue, "path": ws.path, "agentIds": agentIds(at: ws.path),
                ])
            }
            projects.append(["name": repo.name, "path": repo.path, "checkouts": checkouts])
        }

        let favorited = Set(cfg.sidebarProjectPaths)
        let addable = allRepos
            .filter { !favorited.contains($0.path) && !managedPaths.contains($0.path) }
            .map { ["name": $0.name, "path": $0.path] }

        await connection.send(type: "projects", payload: RemoteProtocol.projectsPayload(projects: projects, addable: addable))
    }
```
Extend `sendSessions`'s `SessionMeta(...)` construction with the two new fields:
```swift
                provider: meta.provider?.rawValue,
                lastActivityAt: meta.lastActivityAt.timeIntervalSince1970 * 1000
```
(Place them after the existing `kind:` argument.)

In `handleInbound`'s `"welcome"` case, add a third send:
```swift
            case "welcome":
                await sendSessions()
                await sendRepos()
                await sendProjects()
```
In `handleTerminalEvent`, after the existing `await sendSessions()` (in the `.spawned, .exited, .statusChanged` branch), add:
```swift
            await sendProjects()
```
In `start()`, after the `terminalTask` is set up, observe config changes:
```swift
        let configStream = appConfig.events()
        configTask = Task { [weak self] in
            for await event in configStream {
                if case .configChanged(let old, let new) = event,
                   old.sidebarProjectPaths != new.sidebarProjectPaths || old.workspaces != new.workspaces {
                    await self?.sendProjects()
                }
            }
        }
```
In `shutdown()`, cancel it:
```swift
        configTask?.cancel(); configTask = nil
```

- [ ] **Step 4: Wire the composition root**

In `RemoteFeatureAssembly.swift`, pass `services.config` into `RemoteService(...)`:
```swift
        remoteService = RemoteService(
            paths: services.paths,
            terminal: services.terminal,
            repos: services.repo,
            config: services.config,
            chatSource: TranscriptChatSource(),
            trust: ClaudeWorkspaceTrust(),
            hookEvents: { services.agentHooks.events() },
            transcriptLocator: TranscriptLocator(),
            chatSessions: services.chatSessions,
            workspaces: services.workspaces
        )
```
(Place `config:` in the position matching the `RemoteService.init` signature from Task 7.)

- [ ] **Step 5: Run test + full LumiRemote suite**

Run: `cd LumiPackages && swift test --filter RemoteServiceProjectsTests`
Expected: PASS.
Then: `cd LumiPackages && swift test`
Expected: PASS — fix any pre-existing `RemoteService(...)` call sites in tests that now need `config:` (pass a `LumiTestSupport` fake config).

- [ ] **Step 6: Commit**

```bash
git add LumiPackages/Sources/LumiRemote/RemoteService.swift \
        LumiPackages/Sources/LumiAppCore/Features/RemoteFeatureAssembly.swift \
        LumiPackages/Tests/LumiRemoteTests/RemoteServiceProjectsTests.swift
git commit -m "feat(remote): broadcast projects tree on welcome/terminal/config change"
```

---

## Task 9: Relay — cache + forward `projects`, include in `welcome`

**Files:**
- Modify: `RelayServer/src/registry.ts`
- Modify: `RelayServer/src/bridge.ts`
- Test: `RelayServer/test/bridge.test.ts`

**Interfaces:**
- Consumes: existing `Room` shape, `envelope`, `broadcast`.
- Produces: `Room.projects`; `fromMac` handles `projects` (cache + broadcast); phone `welcome` payload gains `projects` + `addable`. (`add_project` needs no change — it rides the already-forwarded `command` frame.)

- [ ] **Step 1: Write the failing test**

Append to `bridge.test.ts` (match the existing `env(...)`, `make*`, `phone.last()` helpers in the file):

```typescript
test('mac projects → odada saklanır ve telefonlara yayınlanır', () => {
  const payload = { projects: [{ name: 'p', path: '/p', checkouts: [] }], addable: [{ name: 'orca', path: '/p/orca' }] }
  bridge.handleMessage(macSession, env('projects', payload))
  expect(registry.get(TOKEN)?.projects).toEqual(payload)
  expect(phone.last().type).toBe('projects')
  expect(phone.last().payload).toEqual(payload)
})

test('telefon hello → welcome içinde projects ve addable gelir (mac önce cache etmişse)', () => {
  macSession.room.projects = { projects: [{ name: 'p', path: '/p', checkouts: [] }], addable: [] }
  const session = bridge.handleHello(phoneClient, env('hello', { role: 'phone', token: TOKEN }))!
  expect(phone.last().type).toBe('welcome')
  expect(phone.last().payload.projects).toEqual([{ name: 'p', path: '/p', checkouts: [] }])
  expect(phone.last().payload.addable).toEqual([])
})

test('telefon command add_project → mac’e forward edilir', () => {
  bridge.handleMessage(phoneSession, env('command', { commandId: 'c1', action: 'add_project', path: '/p/orca' }))
  const forwarded = mac.sent.find((m) => m.type === 'command')
  expect(forwarded?.payload.action).toBe('add_project')
})
```

> Match `macSession`, `phoneSession`, `phoneClient`, `mac`, `phone`, `registry`, `TOKEN`, and the `env()` helper to the exact setup already present in `bridge.test.ts`. If the file builds sessions differently, replicate that setup.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd RelayServer && npm test`
Expected: FAIL — `room.projects` undefined; no `projects` broadcast; `welcome` lacks `projects`/`addable`. (The add_project forward test should already PASS — it documents the existing `command` behavior; keep it as a regression guard.)

- [ ] **Step 3: Implement**

In `registry.ts`, add to the `Room` interface (after `repos`):
```typescript
  projects: unknown | null
```
and in the room-creation literal (the `room = { token, mac: null, ... }` line), add:
```typescript
    projects: null,
```

In `bridge.ts` `fromMac`'s switch, add a case:
```typescript
      case 'projects': {
        room.projects = env.payload
        this.broadcast(room, envelope('projects', env.payload))
        break
      }
```
In `handleHello`, extend the phone `welcome` payload:
```typescript
      const proj = (room.projects as { projects?: unknown; addable?: unknown } | null) ?? null
      client.send(envelope('welcome', {
        sessions: room.sessions ?? [],
        repos: room.repos ?? [],
        projects: proj?.projects ?? [],
        addable: proj?.addable ?? [],
        macOnline: room.mac !== null,
        lastSeenAt: room.lastSeenAt,
      }))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd RelayServer && npm test`
Expected: PASS (all existing + 3 new).

- [ ] **Step 5: Commit**

```bash
git add RelayServer/src/registry.ts RelayServer/src/bridge.ts RelayServer/test/bridge.test.ts
git commit -m "feat(relay): cache + forward projects, include in welcome"
```

---

## Task 10: End-to-end wire round-trip (phone)

**Files:**
- Modify: `LumiMobile/LumiMobileKit/Tests/LumiMobileKitTests/EndToEndWireTests.swift`

**Interfaces:**
- Consumes: everything above (decode `projects` + welcome, tree assembly, `addProject` outgoing).

- [ ] **Step 1: Write the failing test**

Append to `EndToEndWireTests.swift` (reuse the file's `injectFrame(_:into:)` helper and `FakeRelayClient`):

```swift
    @MainActor
    func testProjectsWelcomeAndMessageBuildTree() async {
        let (model, client) = makeModel()   // same helper the file uses to build AppModel + FakeRelayClient
        await model.start()

        // welcome carries projects + addable + a session, exactly as the relay emits.
        injectFrame("""
        {"v":1,"type":"welcome","payload":{
          "macOnline":true,"lastSeenAt":null,
          "sessions":[{"id":"t1","repoName":"unco","status":"idle","cols":80,"rows":24,"provider":"claude","lastActivityAt":1790000000000}],
          "projects":[{"name":"unco","path":"/p/unco","checkouts":[
            {"kind":"original","title":"main","scm":"git","path":"/p/unco","agentIds":["t1"]}]}],
          "addable":[{"name":"orca","path":"/p/orca"}]
        }}
        """, into: client)

        XCTAssertEqual(model.projectTree.count, 1)
        XCTAssertEqual(model.projectTree[0].checkouts[0].agents.map(\.id), ["t1"])
        XCTAssertEqual(model.projectsSnapshot.addable.map(\.name), ["orca"])

        // A later standalone `projects` frame replaces the snapshot.
        injectFrame("""
        {"v":1,"type":"projects","payload":{"projects":[],"addable":[]}}
        """, into: client)
        XCTAssertTrue(model.projectTree.isEmpty)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd LumiMobile/LumiMobileKit && swift test --filter EndToEndWireTests`
Expected: FAIL if any wiring gap remains; otherwise it will fail to compile until `makeModel` matches. Fix the helper reference to match the file.

- [ ] **Step 3: (No new implementation)**

All behavior exists from Tasks 1–4. If the test fails on behavior (not helper names), debug with `superpowers:systematic-debugging` — do not add production code speculatively.

- [ ] **Step 4: Run the full phone suite**

Run: `cd LumiMobile/LumiMobileKit && swift test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add LumiMobile/LumiMobileKit/Tests/LumiMobileKitTests/EndToEndWireTests.swift
git commit -m "test(mobile): projects welcome + message end-to-end wire round-trip"
```

---

## Final Verification (manual — after all tasks)

Run all three suites green, then verify on real hardware (memory: prior remote bugs were stale builds, not code — always verify against a fresh build):

- [ ] `cd LumiMobile/LumiMobileKit && swift test` — green.
- [ ] `cd LumiPackages && swift test` — green.
- [ ] `cd RelayServer && npm test` — green.
- [ ] `cd LumiPackages && swift build -c release --product Lumi` — builds.
- [ ] Deploy relay (Railway service **`lumi-relay`** — this is the LIVE service the app connects to at `wss://lumi-relay-production.up.railway.app`; the orphan `lumi-relay-new` was deleted 2026-09-22, so the old two-service trap is gone), reinstall the Mac app (`Scripts/make-app.sh --install`), rebuild + install the iOS app on device.
- [ ] Device: pair; the phone home shows Projects (not the flat list). Favorited Mac projects appear; each checkout lists its agents; a waiting agent is amber with a side bar.
- [ ] Device: add a favorite on the Mac → it appears on the phone within a beat (no phone action).
- [ ] Device: tap `+` → pick a Mac-known project → it appears in the tree (Mac's `sidebarProjectPaths` gained it).
- [ ] Device: tap an agent → the existing terminal/chat view opens and mirrors live.
- [ ] Device: single-agent checkout shows the agent directly (no "N agents" toggle); zero-agent checkout shows only the row; empty favorites shows "No projects yet".

---

## Self-Review Notes (author)

- **Spec coverage:** favorites mirror (Tasks 6/8/9), tree render (Tasks 1/3/5), navigation (Task 5), attention (Task 3), `+` add-project write (Tasks 2/4/7), empty/offline/single/zero-agent states (Task 5), all test buckets (Tasks 1/3/4/6/7/8/9/10). Relay `add_project` allowlist "gap" resolved: it rides the already-forwarded `command` frame — Task 9 keeps a regression test asserting this.
- **Deviation from spec (noted):** the original checkout's real SCM branch label is omitted (nil) in v1 — the spec's example showed one; deriving it needs the git/plastic stores in `RemoteService`, deferred to keep this v1 contained. Workspace checkouts carry their branch. Agent ordering is recency-desc in v1 (attention-priority ordering is a v2 refinement). Both are behavioral choices within the approved read-only scope; flag to the user at review if fuller parity is wanted now.
