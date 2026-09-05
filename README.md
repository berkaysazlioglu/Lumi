# Lumi

A native macOS dashboard for running and watching many **Claude Code** (or **Codex**) CLI sessions at once.

Open your repositories as tabs, spawn as many terminals as you need inside each one, and see at a glance which agent is working, which one is waiting for your input, and which one hit an error. Written in Swift (AppKit shell + SwiftUI content) with [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) as the terminal emulator — it replaces an earlier Electron version.

## Features

- **Repo tabs** — discover projects under a root folder, or add individual paths; non-git folders work too
- **Multiple terminals per repo** — each one a real login-shell PTY, with a live status indicator (`idle / working / waiting / error`) driven by terminal title and notification escape sequences
- **Native notifications** when an agent finishes a turn or needs input
- **Git panel** — status, commit log and a file tree with an integrated viewer (syntax highlighting + unified diff)
- **Usage indicator**, **focus mode**, and an optional **scheduled session trigger**

## Requirements

| | |
|---|---|
| macOS | 14 (Sonoma) or newer |
| Toolchain | Xcode 16+ (or a Swift 6.0 toolchain) — check with `swift --version` |
| Git | any recent version, for the repo/VCS features |
| Agent CLI | [Claude Code](https://docs.claude.com/en/docs/claude-code) (`claude`) and/or Codex (`codex`) on your `PATH` |

Install the Claude Code CLI if you don't have it yet:

```bash
npm install -g @anthropic-ai/claude-code
claude --version
```

Lumi launches `claude` / `codex` through your login shell, so anything that works in your terminal works here. There is no separate API key to configure in Lumi.

## Run from source

```bash
git clone https://github.com/berkaysazlioglu/Lumi.git
cd Lumi/LumiPackages
swift run Lumi
```

That's all you need — SwiftPM fetches and builds the dependencies (SwiftTerm, Highlightr) itself, so the first build needs a network connection and takes a minute or two. Later builds are incremental.

Debug builds intentionally keep their data in `~/.lumi-dev` so you can develop without touching your real configuration.

## Build a Lumi.app bundle

```bash
Scripts/make-app.sh          # release build, ad-hoc signed → dist/Lumi.app
```

Ad-hoc signing is fine on your own machine. For distribution, sign with a Developer ID and notarize:

```bash
IDENTITY="Developer ID Application: Your Name (TEAMID)" Scripts/make-app.sh
ditto -c -k --keepParent dist/Lumi.app dist/Lumi.zip
xcrun notarytool submit dist/Lumi.zip --keychain-profile <your-profile> --wait
xcrun stapler staple dist/Lumi.app
```

## First launch

1. A setup screen checks your shell, PTY support and agent CLIs, and offers to fix what it can.
2. Point **Projects root** at the folder that holds your repositories (e.g. `~/Developer`), or add individual paths.
3. Open a repo tab and press the new-terminal button to start an agent session.

Release builds store everything under `~/.lumi`:

```
~/.lumi/config.json       settings (projects root, provider, theme, notifications…)
~/.lumi/ui-state.json     window bounds, open tabs, layout
```

## Tests

```bash
cd LumiPackages
swift test
```

## Project layout

```
LumiPackages/Sources/
  LumiKit/        models, protocols, shared support (no dependencies)
  LumiTerminal/   PTY process, terminal sessions, SwiftTerm integration
  LumiServices/   config, git/repo, notifications, system checks
  LumiState/      observable stores + feature assemblies (service → store → UI)
  LumiUI/         SwiftUI views, the design system, and the shell registries
  LumiAppCore/    composition root: service registry, window, menus, shell composition
  LumiApp/        the executable itself (a thin main.swift)
LumiPackages/Tests/
  LumiTestSupport/  shared fakes, used by every test target
docs/decisions.md  binding decision log
docs/design/       binding design record for the native implementation
Scripts/           make-app.sh (bundle + sign + notarize + release artifacts)
```

Dependencies flow one way: `LumiKit ← LumiTerminal / LumiServices / LumiState ← LumiUI ← LumiAppCore`. The UI layer holds no business logic, and everything is wired manually — services through a `ServiceRegistry`, features through `FeatureAssembly`.

The shell is composed rather than hand-written: panels, centre routes, toolbar items and overlays are registered as descriptors, so a new view is a single assembly file plus its registration lines — no edits to `RootView`, `HeaderBarView` or the panel host.

## Design notes

Three requirements were baked into the architecture from day one, after root-causing two serious bugs in the Electron version (a black screen on reattach, and an out-of-memory crash on heavy terminal output):

- **Ack-based backpressure** from PTY to UI, so heavy output can never grow an unbounded buffer
- **Render-crash isolation** — PTY sessions live independently of the UI
- **Replay safety** — sequence-safe truncation and filtering of terminal auto-responses, so replayed output can't be typed back into a live session

Full context: [docs/design/00-architecture.md](docs/design/00-architecture.md) (Appendix A) and [docs/decisions.md](docs/decisions.md).

## Status

Working macOS app; notarized Developer ID builds are produced by the release workflow (v0.6.0 Gatekeeper-verified). Some verification is still manual (long-run performance profiling, microphone permission chain for voice mode, visual parity after the 2026-09 refactor).

## License

[MIT](LICENSE).

Third-party components keep their own licenses: [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) and [Highlightr](https://github.com/raspu/Highlightr) are MIT; the bundled JetBrains Mono font is under the SIL Open Font License 1.1 ([OFL.txt](LumiPackages/Sources/LumiUI/Resources/Fonts/OFL.txt)).
