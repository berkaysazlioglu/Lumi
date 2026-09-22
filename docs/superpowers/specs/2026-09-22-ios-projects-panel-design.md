# iOS Projects Panel — Design Spec

**Date:** 2026-09-22
**Branch:** `feat/ios-projects-panel`
**Status:** Approved design, ready for implementation planning

## Summary

Replace the phone's flat session list (`SessionListView`) with a **Projects tree**
that mirrors the Mac's Projects panel (decisions 48–51). The tree is
`Project → Checkout → Agents`, matching the orca desktop sidebar:

- **Project** — a favorited folder (Mac `sidebarProjectPaths`).
- **Checkout** — the original repo (`main`) plus each managed workspace/worktree.
- **Agent** — a live terminal/chat session running in that checkout's path.

The Mac is the **single source of truth**. The phone reflects favorites live: add
a project on the Mac and it appears on the phone within a beat. The phone maintains
no independent favorites list.

Tapping an agent opens the **existing** `TerminalSessionView` / `MobileChatView`.
The only write the phone performs in v1 is **adding a project to favorites** via `+`,
choosing from folders the Mac already knows.

## Scope

**In scope (v1):**
- Read-only tree: projects → checkouts → agents, with expand/collapse groups.
- Navigate into existing terminal/chat session views on agent tap.
- Attention highlighting (waiting agent → amber + side bar; collapsed checkout → roll-up glyph + count).
- `+` button: pick from Mac-known-but-not-favorited projects → `add_project` command (the one write).
- Empty state, Mac-offline state.

**Out of scope (v1):**
- Removing projects from favorites, closing checkouts, deleting workspaces from the phone.
- Starting a new agent from the phone (existing New Session flow untouched, but not surfaced per-project).
- Creating workspaces from the phone.
- Persisting collapse state across launches or syncing collapse state with the Mac.

## Architecture

Three layers, mirroring the existing remote stack.

### 1. Mac (`LumiPackages/Sources/LumiRemote`)

Alongside the existing `sessions` broadcast, emit a new **`projects` snapshot**
whenever the projects structure changes (favorites list, workspaces, or the set of
agents-per-checkout). Derived from:

- `ProjectWorkspaceStore.addedProjects` (favorites) + `.workspaces(for:)` (checkouts).
- `TerminalListStore.terminals(in: checkout.path)` (agents), using the same smart
  sort as the Mac panel (attention → running → done; ties by most recent activity).
- The `addable` pool: repos the Mac knows (`repos`) minus already-favorited/managed paths.

This is a small structural message; it does not participate in PTY ack-based
backpressure (that remains per-session on the terminal data path).

The `SessionMeta` broadcast gains two **additive, optional** fields the tree needs:
- `provider` — `"claude" | "codex" | "shell"` (from `TerminalMeta.provider`) for the identity glyph.
- `lastActivityAt` — epoch ms, for the relative-time label.

New command handler: `add_project(path)` → `ProjectWorkspaceStore.addProject(repo)`,
followed by a fresh `projects` snapshot.

### 2. Relay

- Cache + forward the `projects` message to phones in the room (same treatment as `sessions`/`repos`).
- Add `add_project` to the phone→Mac command allowlist in the bridge.
  **Regression guard:** `chat_send` was once forwarded but missing from the allowlist
  (see memory `faz2-chat-loading-send-regression`). A relay isolation test MUST cover
  `add_project` forwarding so this class of bug cannot recur.

### 3. Phone (`LumiMobile`)

- **`LumiMobileKit/Models.swift`**: `ProjectNode`, `CheckoutNode`, `ProjectsSnapshot`;
  add `provider` + `lastActivityAt` to `SessionMeta`.
- **`PhoneProtocol.swift`**: decode `type:"projects"` (tolerant: unknown `kind`/`scm`,
  missing `addable` → empty); encode `add_project` command frame; add
  `CommandAction.addProject(path:)`.
- **`AppModel`**: hold the latest `ProjectsSnapshot`; expose a derived, view-ready tree
  that joins `agentIds` against the `sessions` map (skip ids not yet present — race guard),
  in `agentIds` order.
- **UI (`App/`)**: new `ProjectsView` (replaces `SessionListView` as the paired root),
  with `ProjectRow`, `CheckoutRow`, `AgentRow` sub-views and the `AddProjectSheet`.
  `RootView` shows `ProjectsView` when paired.

## Wire schema

Envelope unchanged (`{v:1, type, payload}`). Incoming decode stays tolerant — an
unknown field or enum value never breaks the stream (design §12.2).

```jsonc
{ "v":1, "type":"projects", "payload":{
  "projects":[
    { "name":"unco-forge", "path":"/Users/.../unco-forge",
      "checkouts":[
        { "kind":"original",  "title":"main", "branch":"fix/crashly...", "scm":"git",
          "path":"/Users/.../unco-forge", "agentIds":["t-12","t-9","t-3"] },
        { "kind":"workspace", "title":"review", "branch":"feat/review", "scm":"git",
          "path":"/Users/.../wt/review", "agentIds":["t-20"] }
      ] }
  ],
  "addable":[ { "name":"orca", "path":"/Users/.../orca" } ]
} }
```

`add_project` command (phone → Mac), carried in the existing `command` frame:

```jsonc
{ "v":1, "type":"command", "payload":{ "commandId":"…", "action":"add_project", "path":"/Users/.../orca" } }
```

`SessionMeta` additive fields (both optional; old Mac → nil → generic glyph, hidden time):

```jsonc
{ "id":"t-12", "repoName":"unco-forge", "status":"waiting-unseen", "cols":80, "rows":24,
  "provider":"claude", "lastActivityAt":1790000000000 }
```

## Phone data model

```swift
struct ProjectNode  { let name, path: String; let checkouts: [CheckoutNode] }
struct CheckoutNode { let kind: String        // "original" | "workspace"
                      let title: String        // "main" or workspace name
                      let branch: String?       // real SCM branch label
                      let scm: String           // "git" | "plastic" | "none"
                      let path: String
                      let agentIds: [String] }
struct ProjectsSnapshot { let projects: [ProjectNode]; let addable: [Repo] }
```

The view-ready agent row is built in `AppModel` by resolving each `agentId` against the
`sessions` map (which now carries `provider` + `lastActivityAt`). Order comes from
`agentIds` (Mac already sorted). Ids not present in `sessions` are skipped.

## UI behavior

- **Tree layout** — matches the orca screenshot: `PROJECTS` header + count + search + `+`;
  project rows (folder glyph, collapsible); checkout rows (home glyph for original,
  branch glyph for workspace; `title` + real `branch` label); a `N agents` toggle when a
  checkout has >1 agent; agent rows (activity glyph + provider glyph + title + relative time).
- **Single agent** — no `N agents` toggle; the agent shows directly (Mac parity).
- **Zero agents** — checkout row only.
- **Attention** (`TerminalAttention` rule, pure fn in LumiMobileKit): a `waiting` agent that
  isn't selected turns amber with a leading side bar. A collapsed checkout surfaces a roll-up
  glyph + agent count so attention reads without expanding.
- **Collapse** — phone-local state, not persisted, not synced with the Mac.
- **Navigation** — agent tap pushes `TerminalSessionView` (or `MobileChatView` when
  `SessionMeta.kind == "chat"`) via the existing `NavigationStack` value routing.
- **Empty favorites** — "No projects yet" + hint to use `+`.
- **Mac offline** — existing offline banner sits above the tree; the tree freezes on the
  last snapshot; `+` disabled.
- **`+` (Add project)** — sheet lists `addable` repos (Mac-known, not yet favorited);
  selecting one sends `add_project`; the sheet dismisses; the Mac's next `projects`
  snapshot reflects the addition (not optimistic). Failure → error surfaced (toast/inline).

## Testing

Pure unit tests in `LumiMobileKit` unless noted.

- `projects` decode: happy path + tolerance (unknown `kind`, unknown `scm`, missing `addable`).
- Tree assembly: `agentIds` → `sessions` join preserves order; missing ids skipped.
- `SessionMeta` decode with and without `provider` / `lastActivityAt`.
- `TerminalAttention` parity: `waiting` → amber; collapsed checkout roll-up count.
- Group states: empty favorites, single-agent (no toggle), zero-agent, collapse/expand.
- `add_project` frame encode; round-trip in `EndToEndWireTests` (Mac ↔ phone shared wire).
- Mac side: `projects` snapshot derived correctly from `ProjectWorkspaceStore` +
  `TerminalListStore` (`RemoteService` / `RemoteCommandHandler` tests); `add_project`
  handler adds to favorites and re-broadcasts.
- Relay: `add_project` forwarded (isolation test — closes the `chat_send`-class gap);
  `projects` cached + forwarded to room.

## Non-goals / risks

- **Join races** — the join approach (vs. embedding agents in the snapshot) risks a
  transient empty row when a snapshot references an id not yet in `sessions`. Mitigation:
  skip unresolved ids; the next `sessions`/`projects` tick fills them.
- **Stale build confusion** — prior remote bugs traced to stale builds, not code
  (memory `mobile-transcript-tracking-diagnosis`). Verify against a fresh build on both
  Mac and device before concluding behavior.
- **Deploy footgun** — relay lives at Railway service `lumi-relay` (the LIVE one, serving
  `wss://lumi-relay-production.up.railway.app`; the orphan `lumi-relay-new` was deleted
  2026-09-22); the Mac is installed via `make-app.sh --install`. Both must be redeployed
  for the wire change to take effect end-to-end.
