# iOS Chat Bugfixes (Stop / Multi-select / Ajan durumu / Renklendirme) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** iOS chat'teki dört saha bug'ını kapatmak: (1) Stop sonrası takılan view + gitmeyen mesaj, (2) multi-select'te görünmeyen/kaybolan seçim, (3) hangi ajanın çalıştığı/beklediğinin belli olmaması, (4) satır içi kod / kod bloklarının renklendirilmemesi.

**Architecture:** (1) Mac'te `TurnStatusReducer`/`PromptJournal` terminalin çıkarılmış kesmesini (`TerminalEvent.statusChanged` → non-working) öğrenir ve telefona `working=false` + prompt iptali yollar; telefon Stop'ta Ctrl-C yerine Esc gönderir, "Stopping…" gösterir ve yanıt gelmezse yerelde düşer. (2) Prompt seçim taslağı kart `@State`'inden `AppModel.promptDrafts`'a taşınır (saf reducer LumiMobileKit'te). (3) `sessions` meta'sına additive `awaitingDecision` alanı eklenir; telefon Mac'in `AgentActivityState` dilini (`AgentActivity`) kullanır. (4) LumiMobileKit'te saf markdown segmentleyici + inline-code tespiti; view renklendirir.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI (iOS 17), Swift Testing (LumiPackages), XCTest (LumiMobileKit), XcodeGen.

## Global Constraints

- Swift 6 strict concurrency; Combine yok; servis→store `AsyncStream`.
- Protokol değişikliği yalnız **additive**: eski telefon yeni alanı yok sayar, yeni telefon alan yoksa varsayılan kullanır. Relay'e dokunulmaz (redeploy yok).
- `~/.lumi` persistence formatı değişmez (karar 9).
- Bloklayıcı bekleme cooperative pool'da koşmaz (karar 86) — telefondaki zaman aşımı `Task.sleep` ile yapılır.
- Mac kodundaki yorumlar Türkçe, `LumiMobile/` altındaki yorumlar İngilizce (mevcut dosyalarla uyumlu).
- Bilinçli davranış/protokol değişikliği `docs/decisions.md`'ye karar olarak yazılır (son karar 103 → bu plan 104 ve 105.i ekler).
- Mac testleri: `cd LumiPackages && swift test --filter <Suite>`; tam koşu `swift build && swift test`.
- Telefon testleri: `cd LumiMobile/LumiMobileKit && swift test --filter <Class>`.
- iOS build: `cd LumiMobile && xcodegen generate && xcodebuild -project LumiMobile.xcodeproj -scheme LumiMobile -destination 'generic/platform=iOS Simulator' build | tail -20` → `** BUILD SUCCEEDED **`. Yeni `.swift` dosyası App'e eklenirse `xcodegen generate` şart (`.xcodeproj` gitignore'da).
- Commit mesajı sonu: `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`

---

## File Structure

| Dosya | Sorumluluk | Task |
|---|---|---|
| `LumiPackages/Sources/LumiKit/NativeChat/TurnStatusReducer.swift` | `interrupt()` — kesmeyi idle'a katlar | 1 |
| `LumiPackages/Sources/LumiKit/NativeChat/PromptJournal.swift` | `cancelAllPending()` | 1 |
| `LumiPackages/Sources/LumiRemote/RemoteService.swift` | statusChanged → interrupt köprüsü; awaitingDecision takibi | 1, 4 |
| `LumiPackages/Sources/LumiRemote/RemoteProtocol.swift` | `SessionMeta.awaitingDecision` | 4 |
| `LumiMobile/LumiMobileKit/Sources/LumiMobileKit/AppModel.swift` | `requestStop`, `stoppingSessions`, `promptDrafts` | 2, 3 |
| `LumiMobile/LumiMobileKit/Sources/LumiMobileKit/PromptDraft.swift` (yeni) | saf seçim taslağı reducer'ı | 3 |
| `LumiMobile/LumiMobileKit/Sources/LumiMobileKit/AgentActivity.swift` (yeni) | Mac `AgentActivityState` paritesi | 4 |
| `LumiMobile/LumiMobileKit/Sources/LumiMobileKit/Models.swift` | `SessionMeta.awaitingDecision` decode | 4 |
| `LumiMobile/LumiMobileKit/Sources/LumiMobileKit/ProjectTree.swift` | `AgentRowData.activity` | 4 |
| `LumiMobile/LumiMobileKit/Sources/LumiMobileKit/ChatMarkdown.swift` (yeni) | saf markdown segmentleyici | 6 |
| `LumiMobile/App/TurnStatusBar.swift`, `MobileChatView.swift` | Stop UI | 2 |
| `LumiMobile/App/MobileChatPromptCard.swift` | taslak binding'leri + seçim görseli | 3 |
| `LumiMobile/App/AgentActivityGlyph.swift` (yeni), `ProjectsView.swift`, `TerminalSessionView.swift` | durum glifi + etiket + chat başlığı | 5 |
| `LumiMobile/App/ChatMarkdownView.swift` (yeni), `MobileChatMessageView.swift` | renkli render | 6 |
| `docs/decisions.md`, `CLAUDE.md` | karar 104, 105 | 1, 4 |

---

### Task 1: Mac — çıkarılmış kesme telefona `working=false` + prompt iptali olarak iner

**Kök neden:** `TurnStatusReducer` yalnız `stop`/`stopFailure` hook'unda idle'a düşer; Claude Code Esc/Ctrl-C kesmesinde Stop hook'u **göndermez**. Mac terminali bunu `AgentHookStatusReducer.inferInterrupt` ile 0,5 sn sonra çıkarır ve `TerminalEvent.statusChanged(id, .waiting…)` yayınlar, ama `RemoteService` bu olayda yalnız `sessions` yayınlıyor — `turnReducers`/`promptJournals`'a dokunmuyor. Telefon `working=true`'da sonsuza kadar kalıyor.

**Files:**
- Modify: `LumiPackages/Sources/LumiKit/NativeChat/TurnStatusReducer.swift`
- Modify: `LumiPackages/Sources/LumiKit/NativeChat/PromptJournal.swift`
- Modify: `LumiPackages/Sources/LumiRemote/RemoteService.swift` (`handleTerminalEvent`, ~satır 235)
- Test: `LumiPackages/Tests/LumiKitTests/TurnStatusReducerTests.swift`, `LumiPackages/Tests/LumiKitTests/PromptJournalTests.swift`, `LumiPackages/Tests/LumiRemoteTests/RemoteServiceTurnStatusTests.swift`
- Docs: `docs/decisions.md` (karar 96), `CLAUDE.md` (Durum paragrafına bir cümle)

**Interfaces:**
- Produces: `TurnStatusReducer.interrupt() -> ChatTurnStatus?` (working ise `.idle` döner ve state'i sıfırlar, değilse `nil`); `PromptJournal.cancelAllPending() -> [ChatPrompt]` (pending item'ları cancelled + revision+1 yapar, değişenleri döndürür).

- [ ] **Step 1: Reducer/journal için failing testler**

`TurnStatusReducerTests.swift` içine (mevcut `event(_:)` helper'ı kullanılır):

```swift
    @Test func interruptResetsWorkingToIdle() {
        let r = TurnStatusReducer(now: { Date(timeIntervalSince1970: 1) })
        _ = r.reduce(event(.userPromptSubmit))
        _ = r.reduce(event(.preToolUse, tool: "Bash"))
        #expect(r.interrupt() == .idle)
        #expect(r.status == .idle)
    }

    @Test func interruptWhenIdleIsNoop() {
        let r = TurnStatusReducer()
        #expect(r.interrupt() == nil)
    }
```

`PromptJournalTests.swift` içine — dosyadaki mevcut soru-üreten helper'ı kullan (yoksa aşağıdaki event'i inline kur):

```swift
    @Test func cancelAllPendingCancelsOnlyPending() {
        let j = PromptJournal()
        let ev = AgentHookEvent(provider: .claude, terminalID: TerminalID(), kind: .permissionRequest,
                                agentID: nil, teammateName: nil, toolName: "Bash", source: nil,
                                trigger: nil, isInterrupt: false, promptHead: nil,
                                runningBackgroundAgentIDs: nil, toolInput: "{\"command\":\"ls\"}", toolUseID: "t1")
        #expect(j.reduce(ev).count == 1)
        let cancelled = j.cancelAllPending()
        #expect(cancelled.map(\.itemId) == ["t1"])
        #expect(cancelled.first?.state == .cancelled)
        #expect(j.cancelAllPending().isEmpty)   // idempotent
    }
```

- [ ] **Step 2: Fail doğrula** — `cd LumiPackages && swift test --filter "TurnStatusReducerTests|PromptJournalTests"` → derleme hatası (`interrupt`/`cancelAllPending` yok).

- [ ] **Step 3: Implement**

`TurnStatusReducer.swift`, `reduce`'tan sonra:

```swift
    /// Karar 96: Esc/Ctrl+C kesmesinde Claude Stop hook'u göndermez. Terminal
    /// kesmeyi çıkardığında (`inferInterrupt` → status non-working) çağrılır.
    /// Çalışıyorsa `.idle` döner, değilse `nil` (idempotent).
    public func interrupt() -> ChatTurnStatus? {
        guard status.working else { return nil }
        status = .idle
        return .idle
    }
```

`PromptJournal.swift`, `resolve`'dan önce:

```swift
    /// Karar 96: kesilen turn'ün bekleyen kartları düşer (Stop hook gelmez).
    public func cancelAllPending() -> [ChatPrompt] {
        cancel(where: { _ in true })
    }
```

- [ ] **Step 4: Pass doğrula** — aynı filtre → PASS.

- [ ] **Step 5: RemoteService için failing test**

`RemoteServiceTurnStatusTests` suite'ine (FakeTerminalServicing `emit(_:)` ve `metas` destekler; `metas` mutable `var`):

```swift
    /// Karar 96: Stop hook'u gelmeyen kesmede terminal status'ü non-working'e
    /// düşünce telefona working=false ve prompt iptali gider.
    @Test func inferredInterruptEmitsIdleAndCancelsPrompts() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()
        let hooks = FakeAgentHookServer()
        let uuid = UUID()
        var meta = TerminalMeta(id: TerminalID(raw: uuid), name: "T", repoPath: "/repo",
                                createdAt: Date(), claudeSessionID: uuid.uuidString)
        term.metas.append(meta)
        let sid = meta.id.description
        let id = TerminalID(raw: uuid)
        let svc = RemoteService(
            paths: .testDefaults(), terminal: term, repos: FakeRepoService(),
            connection: conn, chatSource: FakeChatTranscriptSource(events: []),
            hookEvents: { hooks.events() },
            turnClock: { Date(timeIntervalSince1970: 100) },
            config: FakeConfigService())
        await svc.start()
        await conn.injectInbound(type: "subscribe", payload: ["sessionId": sid, "mode": "chat"])
        try await conn.waitForCount(type: "chat_status", atLeast: 1)

        hooks.emit(hookEvent(.userPromptSubmit, terminalID: id))
        try await conn.waitForCount(type: "chat_status", atLeast: 2)
        hooks.emit(AgentHookEvent(provider: .claude, terminalID: id, kind: .permissionRequest,
                                  agentID: nil, teammateName: nil, toolName: "Bash", source: nil,
                                  trigger: nil, isInterrupt: false, promptHead: nil,
                                  runningBackgroundAgentIDs: nil, toolInput: "{}", toolUseID: "p1"))
        try await conn.waitForCount(type: "prompt", atLeast: 1)

        // Kesme çıkarıldı: terminal status working değil, Stop hook'u YOK.
        meta.status = .waitingFocused
        term.metas = [meta]
        term.emit(.statusChanged(id, .waitingFocused))
        try await conn.waitForCount(type: "chat_status", atLeast: 3)
        #expect(await conn.lastBool(type: "chat_status", key: "working") == false)
        try await conn.waitForCount(type: "prompt", atLeast: 2)
        #expect(await conn.lastString(type: "prompt", key: "state") == "cancelled")
        svc.stop()
    }

    /// Yeni turn başlamışken gelen gecikmiş non-working olayı turn'ü düşürmez:
    /// otorite terminalin CANLI status'üdür.
    @Test func staleNonWorkingEventIgnoredWhileTerminalWorking() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()
        let hooks = FakeAgentHookServer()
        let uuid = UUID()
        var meta = TerminalMeta(id: TerminalID(raw: uuid), name: "T", repoPath: "/repo",
                                createdAt: Date(), claudeSessionID: uuid.uuidString)
        meta.status = .working
        term.metas.append(meta)
        let sid = meta.id.description
        let id = TerminalID(raw: uuid)
        let svc = RemoteService(
            paths: .testDefaults(), terminal: term, repos: FakeRepoService(),
            connection: conn, chatSource: FakeChatTranscriptSource(events: []),
            hookEvents: { hooks.events() },
            config: FakeConfigService())
        await svc.start()
        await conn.injectInbound(type: "subscribe", payload: ["sessionId": sid, "mode": "chat"])
        try await conn.waitForCount(type: "chat_status", atLeast: 1)
        hooks.emit(hookEvent(.userPromptSubmit, terminalID: id))
        try await conn.waitForCount(type: "chat_status", atLeast: 2)

        term.emit(.statusChanged(id, .waitingSeen))   // bayat olay; canlı meta hâlâ .working
        try await conn.waitForNoSent(type: "chat_status", after: 2, for: .milliseconds(200))
        #expect(await conn.lastBool(type: "chat_status", key: "working") == true)
        svc.stop()
    }
```

Not: `TerminalMeta.status` `var` değilse ya da `prompt` payload'unda `state` anahtarı farklıysa (`RemoteProtocol.promptPayload` / `ChatPrompt.toDict`'e bak) test kurulumunu ona göre uyarla — davranış iddiası aynı kalır. `FakeRelayConnection.waitForNoSent(type:after:for:)`'un `after` parametresi o tipten önceden gönderilmiş sayıdır.

- [ ] **Step 6: Fail doğrula** — `swift test --filter RemoteServiceTurnStatusTests` → ilk test FAIL (3. chat_status hiç gelmez, timeout).

- [ ] **Step 7: Implement** — `RemoteService.handleTerminalEvent`'te `case .spawned, .exited, .statusChanged:` bloğunun başına:

```swift
            if case let .statusChanged(id, status) = event, status != .working {
                await settleInterruptIfNeeded(id: id)
            }
```

ve `// MARK: - Turn status (Faz 2)` bölümüne:

```swift
    /// Karar 96: Claude Esc/Ctrl+C kesmesinde Stop hook'u göndermez; terminal
    /// kesmeyi çıkarıp status'ü non-working'e düşürünce turn burada kapanır.
    /// Otorite terminalin CANLI status'üdür — hook ve terminal akışları ayrı
    /// stream'ler olduğundan yeni turn başlamışken gelen bayat olay yok sayılır.
    private func settleInterruptIfNeeded(id: TerminalID) async {
        guard terminal.terminals.first(where: { $0.id == id })?.status != .working else { return }
        let status = turnReducers[id]?.interrupt()
        let cancelled = promptJournals[id]?.cancelAllPending() ?? []
        guard chatModeTerminals.contains(id) else { return }
        if let status {
            rlog("turn: inferred interrupt sid=\(id.description.prefix(8)) → idle")
            await emitTurnStatus(id: id, status: status)
        }
        for item in cancelled { await emitPrompt(id: id, prompt: item) }
    }
```

- [ ] **Step 8: Pass doğrula** — `swift test --filter "RemoteServiceTurnStatusTests|RemoteServicePromptTests|TurnStatusReducerTests|PromptJournalTests"` → PASS.

- [ ] **Step 9: Karar kaydı** — `docs/decisions.md` sonuna:

```markdown
### 96. Kesilen turn telefonda kapanır; telefon Stop'u Esc gönderir (2026-10-02)

Saha bulgusu: iOS'tan Stop'a basınca Claude duruyordu ama telefonda "Running" barı ve streaming balonu kalıyor, ardından mesaj gitmiyordu. Kök: telefonun turn-status'ü Mac'teki `TurnStatusReducer`'dan gelir ve yalnız `Stop`/`StopFailure` hook'unda kapanır; Claude Code Esc/Ctrl-C kesmesinde Stop hook'u göndermez. Terminal kesmeyi 0,5 sn'lik çıkarımla (karar 45) biliyordu ama remote katmanı bunu duymuyordu. Takılı bar yüzünden ikinci kez Stop'a basmak ikinci bir Ctrl-C demekti ve boştaki Claude'da bu çıkış isteğidir.

- **Mac:** `RemoteService`, bir terminalin `statusChanged` olayı non-working olduğunda ve terminalin CANLI status'ü de working değilse `TurnStatusReducer.interrupt()` + `PromptJournal.cancelAllPending()` uygular; chat modundaki terminal için `chat_status working=false` ve iptal edilmiş `prompt` frame'leri yollanır. Canlı status kapısı, hook ve terminal akışları arasındaki sıra yarışında yeni turn'ün düşürülmesini engeller.
- **Telefon:** Stop artık `0x03` değil `0x1B` (Esc) gönderir — Claude'un kesme tuşu, çıkış riski yok. Basınca bar "Stopping…" olur ve tekrar basılamaz; 5 sn içinde `working=false` gelmezse turn yerelde kapatılır (bekleyen kart düşer).
- Protokol değişmez.
```

`CLAUDE.md` "Durum" paragrafının sonuna (karar 95 cümlesinden sonra) ekle: `iOS'tan Stop: Claude kesmede Stop hook'u göndermediği için remote katmanı terminalin çıkarılmış kesmesini (non-working statusChanged + canlı status kapısı) turn-status/prompt iptaline çevirir; telefon Stop'u Esc gönderir, "Stopping…" + 5 sn yerel düşüş (karar 96, 2026-10-02).`

- [ ] **Step 10: Commit**

```bash
git add LumiPackages docs/decisions.md CLAUDE.md
git commit -m "fix(remote): kesilen turn telefonda kapanır — çıkarılmış kesme chat_status/prompt iptaline iner (karar 96)"
```

---

### Task 2: Telefon — Stop Esc gönderir, "Stopping…" + yerel zaman aşımı

**Files:**
- Modify: `LumiMobile/LumiMobileKit/Sources/LumiMobileKit/AppModel.swift`
- Modify: `LumiMobile/App/TurnStatusBar.swift`, `LumiMobile/App/MobileChatView.swift`
- Test: `LumiMobile/LumiMobileKit/Tests/LumiMobileKitTests/AppModelTurnStatusTests.swift`

**Interfaces:**
- Consumes: Mac'in (Task 1) kesmede `chat_status working=false` yollaması.
- Produces: `AppModel.requestStop(_ sessionId: String)`, `AppModel.stoppingSessions: Set<String>` (public private(set)), `AppModel.stopFallbackDelay: Duration` (public var, varsayılan `.seconds(5)`).

- [ ] **Step 1: Failing testler** — `AppModelTurnStatusTests`'e. Önce `FakeRelayClient`'ın gönderilen frame'leri nasıl tuttuğuna bak (`Tests/LumiMobileKitTests/` altında `FakeRelayClient` tanımı; ör. `sentFrames`). Aşağıdaki `lastInputBytes` helper'ını o API'ye göre yaz (input frame'i `PhoneProtocol.inputFrame` ile üretilir; base64 `data` alanını çöz):

```swift
    func testRequestStopSendsEscAndMarksStopping() async throws {
        let client = FakeRelayClient()
        let store = InMemorySecureStore()
        store.write(PairingInfo(relayUrl: "wss://r.example", token: "0123456789abcdef"))
        let model = AppModel(client: client, store: store)
        model.handle(.chatStatus(sessionId: "s1", status: ChatTurnStatus(working: true, startedAtMs: 1, tool: nil)))
        model.requestStop("s1")
        XCTAssertTrue(model.stoppingSessions.contains("s1"))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(await lastInputBytes(client), Data([0x1B]))
    }

    func testIdleStatusClearsStopping() {
        let model = makeModel()
        model.handle(.chatStatus(sessionId: "s1", status: ChatTurnStatus(working: true, startedAtMs: 1, tool: nil)))
        model.requestStop("s1")
        model.handle(.chatStatus(sessionId: "s1", status: .idle))
        XCTAssertFalse(model.stoppingSessions.contains("s1"))
    }

    func testStopFallbackClosesTurnLocally() async throws {
        let model = makeModel()
        model.stopFallbackDelay = .milliseconds(20)
        model.handle(.chatStatus(sessionId: "s1", status: ChatTurnStatus(working: true, startedAtMs: 1, tool: nil)))
        model.handle(.prompt(sessionId: "s1", ChatPrompt.testApproval(itemId: "p1")))
        model.requestStop("s1")
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(model.turnStatus["s1"]?.working, false)
        XCTAssertFalse(model.stoppingSessions.contains("s1"))
        XCTAssertTrue(model.prompts["s1"]?.isEmpty ?? true)
    }

    func testNewTurnDuringStoppingIsNotClobberedByFallback() async throws {
        let model = makeModel()
        model.stopFallbackDelay = .milliseconds(20)
        model.handle(.chatStatus(sessionId: "s1", status: ChatTurnStatus(working: true, startedAtMs: 1, tool: nil)))
        model.requestStop("s1")
        model.handle(.chatStatus(sessionId: "s1", status: .idle))
        model.handle(.chatStatus(sessionId: "s1", status: ChatTurnStatus(working: true, startedAtMs: 2, tool: nil)))
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(model.turnStatus["s1"]?.working, true)
    }
```

`ChatPrompt.testApproval(itemId:)` yoksa `AppModelPromptTests.swift`'te prompt nasıl kuruluyorsa aynı şekilde inline kur (`.prompt(sessionId:, p)` case'inin etiketlerini `AppModel.handle` switch'inden doğrula).

- [ ] **Step 2: Fail doğrula** — `cd LumiMobile/LumiMobileKit && swift test --filter AppModelTurnStatusTests` → derleme hatası.

- [ ] **Step 3: Implement** — `AppModel.swift`:

`turnStatus` tanımının yanına:

```swift
    /// Decision 96: sessions whose Stop was pressed and whose idle status has not
    /// arrived yet — the bar shows "Stopping…" and the button is disabled.
    public private(set) var stoppingSessions: Set<String> = []
    /// Decision 96: if the Mac never reports idle after a Stop, close the turn locally.
    public var stopFallbackDelay: Duration = .seconds(5)
```

`sendInput`'un altına:

```swift
    /// Decision 96: interrupt the running turn. Esc (0x1B), not Ctrl-C — Esc is
    /// Claude's interrupt key; a second Ctrl-C on an idle Claude asks it to exit.
    public func requestStop(_ sessionId: String) {
        guard !stoppingSessions.contains(sessionId) else { return }
        stoppingSessions.insert(sessionId)
        sendInput(sessionId, Data([0x1B]))
        let startedAt = turnStatus[sessionId]?.startedAtMs
        let delay = stopFallbackDelay
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            self?.applyStopFallback(sessionId, startedAt: startedAt)
        }
    }

    private func applyStopFallback(_ sessionId: String, startedAt: Int?) {
        guard stoppingSessions.contains(sessionId) else { return }
        stoppingSessions.remove(sessionId)
        // Only close the SAME turn — a new turn started meanwhile stays live.
        guard let status = turnStatus[sessionId], status.working, status.startedAtMs == startedAt else { return }
        DiagLog.shared.log("model", "stop fallback sid=\(sessionId.prefix(8)) → local idle")
        turnStatus[sessionId] = .idle
        prompts[sessionId] = []
        recomputeStreaming(sessionId)
    }
```

`handle` içindeki `case .chatStatus` dalını değiştir:

```swift
        case .chatStatus(let sessionId, let status):
            macOnline = true
            turnStatus[sessionId] = status
            if !status.working { stoppingSessions.remove(sessionId) }
            recomputeStreaming(sessionId)
```

`removeSessionLocally` ve `applySessions`'taki aktif-oturum temizliğine `stoppingSessions.remove(id)` / `stoppingSessions.remove(active)` ekle; `turnStatus = [:]` yapılan yere (≈satır 174) `stoppingSessions = []` ekle.

Not: `AppModel` `@MainActor` değilse `Task { [weak self] in ... }` içinde `await MainActor.run` gerekebilir — dosyadaki diğer `Task` kullanımlarının izolasyon kalıbını taklit et. Weak capture sınıf değilse kaldır.

- [ ] **Step 4: Pass doğrula** — aynı komut → PASS.

- [ ] **Step 5: UI** — `TurnStatusBar.swift`: `let isStopping: Bool` ekle; buton:

```swift
                Button(isStopping ? "Stopping…" : "Stop", role: .destructive) { onStop() }
                    .font(.footnote.bold())
                    .disabled(isStopping)
```

Dosya üst yorumundaki "Stop → Ctrl-C (0x03)" ifadesini "Stop → Esc (0x1B), decision 96" yap. `MobileChatView.swift`:

```swift
                if let status = model.turnStatus[sessionId], status.working {
                    TurnStatusBar(status: status,
                                  isStopping: model.stoppingSessions.contains(sessionId)) {
                        model.requestStop(sessionId)
                    }
                }
```

- [ ] **Step 6: iOS build** — Global Constraints'teki komut → `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add LumiMobile
git commit -m "fix(mobile): Stop Esc gönderir, Stopping… + 5 sn yerel düşüş (karar 96)"
```

---

### Task 3: Telefon — prompt seçim taslağı AppModel'de, seçim görünür

**Kök neden:** (a) Gruplu sorularda tek seçimli soruya `optionButton(..., checked: nil)` geçiliyor — seçim alınıyor ama satırda hiçbir şey değişmiyor. Multi-select'te yalnız küçük kutu ikonu değişiyor. (b) Seçimler kartın `@State`'inde; chat'ten çıkıp dönünce/kart yeniden kurulunca sıfırlanıyor.

**Files:**
- Create: `LumiMobile/LumiMobileKit/Sources/LumiMobileKit/PromptDraft.swift`
- Modify: `LumiMobile/LumiMobileKit/Sources/LumiMobileKit/AppModel.swift`
- Modify: `LumiMobile/App/MobileChatPromptCard.swift`, `LumiMobile/App/MobileChatView.swift`
- Test: `LumiMobile/LumiMobileKit/Tests/LumiMobileKitTests/PromptDraftTests.swift` (yeni), `AppModelPromptTests.swift`

**Interfaces:**
- Produces:
  - `public struct PromptDraft: Sendable, Equatable { public var selections: [Int: [Int]]; public var texts: [Int: String]; public init() }`
  - `public func toggling(question: Int, option: Int, multiSelect: Bool) -> PromptDraft` (PromptDraft metodu)
  - `public func isSelected(question: Int, option: Int) -> Bool`
  - `public func withText(_ text: String, question: Int) -> PromptDraft`
  - `AppModel.promptDraft(_ sessionId: String, itemId: String) -> PromptDraft`, `AppModel.updatePromptDraft(_ sessionId: String, itemId: String, _ draft: PromptDraft)`

- [ ] **Step 1: Failing test** — `PromptDraftTests.swift`:

```swift
import XCTest
@testable import LumiMobileKit

final class PromptDraftTests: XCTestCase {
    func testMultiSelectTogglesAndKeepsOrder() {
        var d = PromptDraft()
        d = d.toggling(question: 0, option: 2, multiSelect: true)
        d = d.toggling(question: 0, option: 0, multiSelect: true)
        XCTAssertEqual(d.selections[0], [2, 0])
        d = d.toggling(question: 0, option: 2, multiSelect: true)
        XCTAssertEqual(d.selections[0], [0])
        XCTAssertTrue(d.isSelected(question: 0, option: 0))
        XCTAssertFalse(d.isSelected(question: 0, option: 2))
    }

    func testSingleSelectReplaces() {
        var d = PromptDraft()
        d = d.toggling(question: 1, option: 0, multiSelect: false)
        d = d.toggling(question: 1, option: 3, multiSelect: false)
        XCTAssertEqual(d.selections[1], [3])
    }

    func testQuestionsAreIndependent() {
        let d = PromptDraft()
            .toggling(question: 0, option: 1, multiSelect: false)
            .toggling(question: 1, option: 1, multiSelect: true)
            .withText("hi", question: 1)
        XCTAssertEqual(d.selections[0], [1])
        XCTAssertEqual(d.selections[1], [1])
        XCTAssertEqual(d.texts[1], "hi")
        XCTAssertNil(d.texts[0])
    }
}
```

`AppModelPromptTests.swift`'e (dosyadaki mevcut prompt kurulum helper'ını kullan; burada `pendingPrompt(itemId:)` ve `resolved(_:)` diye anıldı — dosyadaki gerçek adlarla değiştir):

```swift
    func testPromptDraftSurvivesAndIsDroppedOnResolve() {
        let model = makeModel()
        model.handle(.prompt(sessionId: "s1", pendingPrompt(itemId: "q1")))
        model.updatePromptDraft("s1", itemId: "q1",
                                PromptDraft().toggling(question: 0, option: 1, multiSelect: true))
        XCTAssertEqual(model.promptDraft("s1", itemId: "q1").selections[0], [1])
        model.handle(.prompt(sessionId: "s1", resolved(pendingPrompt(itemId: "q1"))))
        XCTAssertEqual(model.promptDraft("s1", itemId: "q1"), PromptDraft())
    }
```

- [ ] **Step 2: Fail doğrula** — `swift test --filter "PromptDraftTests|AppModelPromptTests"` → derleme hatası.

- [ ] **Step 3: Implement** — `PromptDraft.swift`:

```swift
import Foundation

/// The user's in-progress answer to a pending prompt card, keyed by question index.
/// Lives in AppModel (not the card's @State) so it survives leaving the chat
/// and card re-creation.
public struct PromptDraft: Sendable, Equatable {
    public var selections: [Int: [Int]] = [:]
    public var texts: [Int: String] = [:]

    public init() {}

    /// multiSelect toggles the option (tap order kept); single-select replaces.
    public func toggling(question: Int, option: Int, multiSelect: Bool) -> PromptDraft {
        var copy = self
        if multiSelect {
            var sel = copy.selections[question] ?? []
            if let at = sel.firstIndex(of: option) { sel.remove(at: at) } else { sel.append(option) }
            copy.selections[question] = sel
        } else {
            copy.selections[question] = [option]
        }
        return copy
    }

    public func isSelected(question: Int, option: Int) -> Bool {
        selections[question]?.contains(option) ?? false
    }

    public func withText(_ text: String, question: Int) -> PromptDraft {
        var copy = self
        copy.texts[question] = text
        return copy
    }
}
```

`AppModel.swift` — `prompts` tanımının yanına `private var promptDrafts: [String: PromptDraft] = [:]` (anahtar `"\(sessionId)\u{0}\(itemId)"`). Gözlemlenebilirlik: `AppModel` `@Observable` ise property gözlenir; `private` gözlemi engellemez. Metotlar:

```swift
    public func promptDraft(_ sessionId: String, itemId: String) -> PromptDraft {
        promptDrafts[sessionId + "\u{0}" + itemId] ?? PromptDraft()
    }

    public func updatePromptDraft(_ sessionId: String, itemId: String, _ draft: PromptDraft) {
        promptDrafts[sessionId + "\u{0}" + itemId] = draft
    }
```

`case .prompt` dalında `if p.state == .pending { list.append(p) }` satırından sonra: `if p.state != .pending { promptDrafts[sessionId + "\u{0}" + p.itemId] = nil }`. `removeSessionLocally`'de `promptDrafts = promptDrafts.filter { !$0.key.hasPrefix(id + "\u{0}") }`.

- [ ] **Step 4: Pass doğrula** — aynı komut → PASS.

- [ ] **Step 5: Kart** — `MobileChatPromptCard.swift`:
  - `@State selected`, `freeText`, `groupSel`, `groupText` kaldırılır; yerine `let draft: PromptDraft` ve `let onDraftChange: (PromptDraft) -> Void`. `sending` `@State` olarak kalır.
  - Tek soru gövdesi soru indeksi `0` ile çalışır: seçim `draft.selections[0] ?? []`, serbest metin `draft.texts[0] ?? ""`.
  - Satır görseli: `optionButton`'a `checked: Bool?` yerine `selection: SelectionMark` geçilir:

```swift
    private enum SelectionMark { case none, radio(Bool), checkbox(Bool) }
```

  ikon: `.radio(true)` → `"largecircle.fill.circle"`, `.radio(false)` → `"circle"`, `.checkbox(true)` → `"checkmark.square.fill"`, `.checkbox(false)` → `"square"`; seçiliyken ikon `Color.accentColor`, satır zemini `Color.accentColor.opacity(0.22)` ve `.overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 1.5))`.
  - Gruplu gövde: tek seçimli soru `.radio(draft.isSelected(question: qi, option: oi))`, multi `.checkbox(...)`; tap → `onDraftChange(draft.toggling(question: qi, option: oi, multiSelect: q.multiSelect))`.
  - Tek-soru tek-seçim tap'i hemen gönderir (mevcut davranış); göndermeden önce `onDraftChange(draft.toggling(question: 0, option: idx, multiSelect: false))` çağrılır ki gönderim sürerken seçili satır vurgulu kalsın.
  - TextField binding'leri: `Binding(get: { draft.texts[qi] ?? "" }, set: { onDraftChange(draft.withText($0, question: qi)) })`.
  - Gönderim yükleri aynı kalır (indeksler `sorted()`, `other` trim'li).
  - Dosya üst yorumuna: "Draft state lives in AppModel.promptDrafts so selections survive leaving the chat."

`MobileChatView.swift`'teki `MobileChatPromptCard(...)` çağrısına:

```swift
                        draft: model.promptDraft(sessionId, itemId: pending.itemId),
                        onDraftChange: { model.updatePromptDraft(sessionId, itemId: pending.itemId, $0) },
```

- [ ] **Step 6: iOS build** → `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add LumiMobile
git commit -m "fix(mobile): prompt seçimi görünür ve chat'ten çıkınca korunur (AppModel.promptDrafts)"
```

---

### Task 4: Mac + telefon modeli — `awaitingDecision` additive alanı ve `AgentActivity`

**Files:**
- Modify: `LumiPackages/Sources/LumiRemote/RemoteProtocol.swift` (`SessionMeta`)
- Modify: `LumiPackages/Sources/LumiRemote/RemoteService.swift` (`handleTerminalEvent`, `sendSessions`, `shutdown` temizliği)
- Modify: `LumiMobile/LumiMobileKit/Sources/LumiMobileKit/Models.swift` (`SessionMeta`)
- Create: `LumiMobile/LumiMobileKit/Sources/LumiMobileKit/AgentActivity.swift`
- Modify: `LumiMobile/LumiMobileKit/Sources/LumiMobileKit/ProjectTree.swift`
- Test: `LumiPackages/Tests/LumiRemoteTests/RemoteProtocolTests.swift`, `RemoteServiceTests.swift`; `LumiMobile/LumiMobileKit/Tests/LumiMobileKitTests/ProtocolTests.swift`, `ProjectTreeTests.swift`, `AgentActivityTests.swift` (yeni)
- Docs: `docs/decisions.md` (karar 97), `CLAUDE.md`

**Interfaces:**
- Produces (Mac): `SessionMeta.awaitingDecision: Bool` → dict'te her zaman `"awaitingDecision": Bool`.
- Produces (telefon): `SessionMeta.awaitingDecision: Bool` (eksikse `false`); `public enum AgentActivity: Sendable, Equatable { case running, awaitingDecision, done, failed, idle }` + `init(status: String, awaitingDecision: Bool)` + `title: String` + `sortRank: Int`; `AgentRowData.activity: AgentActivity`; `SessionMeta.activity: AgentActivity`.

- [ ] **Step 1: Mac failing testler** — `RemoteProtocolTests.swift`:

```swift
    @Test func sessionMetaCarriesAwaitingDecision() {
        let d = SessionMeta(id: "a", repoName: "r", status: "working", cols: 80, rows: 24,
                            awaitingDecision: true).toDict()
        #expect(d["awaitingDecision"] as? Bool == true)
        let d2 = SessionMeta(id: "a", repoName: "r", status: "idle", cols: 80, rows: 24).toDict()
        #expect(d2["awaitingDecision"] as? Bool == false)
    }
```

`RemoteServiceTests.swift`'e (dosyadaki RemoteService kurulumunu ve `sessions` payload'unu okuyan yardımcıları kullan; yoksa `conn.sent.last { $0.type == "sessions" }?.payload["sessions"] as? [[String: Any]]`):

```swift
    @Test func awaitingDecisionChangeRebroadcastsSessions() async throws {
        // kurulum: tek terminal meta, svc.start()
        term.emit(.awaitingDecisionChanged(tid, true))
        // bekle: sessions payload'unda bu id için awaitingDecision == true
        term.emit(.awaitingDecisionChanged(tid, false))
        // bekle: awaitingDecision == false
    }
```

(Yorum satırlarını dosyadaki diğer testlerin kalıbıyla gerçek koda çevir; bekleme için `waitForCount(type: "sessions", atLeast:)` kullan.)

- [ ] **Step 2: Fail doğrula** — `cd LumiPackages && swift test --filter "RemoteProtocolTests|RemoteServiceTests"`.

- [ ] **Step 3: Mac implement**
  - `SessionMeta`: `let awaitingDecision: Bool`, init parametresi `awaitingDecision: Bool = false` (sonda), `toDict`'te `"awaitingDecision": awaitingDecision`.
  - `RemoteService`: `private var awaitingDecision: Set<TerminalID> = []`. `handleTerminalEvent`'te `.awaitingDecisionChanged` mevcut `break` listesinden çıkarılır:

```swift
        case .awaitingDecisionChanged(let id, let awaiting):
            // Karar 97: telefon "karar bekliyor"u "bitti"den ayırır.
            let changed = awaiting ? awaitingDecision.insert(id).inserted : awaitingDecision.remove(id) != nil
            if changed { await sendSessions() }
```

  - `.exited` temizliğine `awaitingDecision.remove(id)`, `shutdown` toplu temizliğine `awaitingDecision.removeAll()`.
  - `sendSessions` terminal meta'sında `awaitingDecision: awaitingDecision.contains(meta.id)`.

- [ ] **Step 4: Pass doğrula** — aynı filtre + `swift test --filter LumiRemoteTests` → PASS.

- [ ] **Step 5: Telefon failing testler** — `AgentActivityTests.swift`:

```swift
import XCTest
@testable import LumiMobileKit

final class AgentActivityTests: XCTestCase {
    func testMappingMatchesMacAgentActivityState() {
        XCTAssertEqual(AgentActivity(status: "working", awaitingDecision: false), .running)
        XCTAssertEqual(AgentActivity(status: "working", awaitingDecision: true), .awaitingDecision)
        XCTAssertEqual(AgentActivity(status: "waiting-unseen", awaitingDecision: false), .done)
        XCTAssertEqual(AgentActivity(status: "waiting-seen", awaitingDecision: false), .done)
        XCTAssertEqual(AgentActivity(status: "error", awaitingDecision: false), .failed)
        XCTAssertEqual(AgentActivity(status: "idle", awaitingDecision: false), .idle)
        XCTAssertEqual(AgentActivity(status: "future-thing", awaitingDecision: false), .idle)
    }

    func testTitles() {
        XCTAssertEqual(AgentActivity.running.title, "Running")
        XCTAssertEqual(AgentActivity.awaitingDecision.title, "Needs input")
        XCTAssertEqual(AgentActivity.done.title, "Done")
    }
}
```

`ProtocolTests.swift`'e (dosyadaki `SessionMeta` decode kalıbıyla):

```swift
    func testSessionMetaDecodesAwaitingDecisionAndDefaultsFalse() throws {
        let withField = #"{"id":"a","repoName":"r","status":"working","cols":80,"rows":24,"awaitingDecision":true}"#
        let without = #"{"id":"a","repoName":"r","status":"working","cols":80,"rows":24}"#
        XCTAssertTrue(try JSONDecoder().decode(SessionMeta.self, from: Data(withField.utf8)).awaitingDecision)
        XCTAssertFalse(try JSONDecoder().decode(SessionMeta.self, from: Data(without.utf8)).awaitingDecision)
    }
```

`ProjectTreeTests.swift`'teki ilk teste: `XCTAssertEqual(agents[0].activity, .running)`.

- [ ] **Step 6: Fail doğrula** — `cd LumiMobile/LumiMobileKit && swift test --filter "AgentActivityTests|ProtocolTests|ProjectTreeTests"`.

- [ ] **Step 7: Telefon implement** — `AgentActivity.swift`:

```swift
import Foundation

/// Agent row status glyph semantics — mirrors the Mac's `AgentActivityState`
/// (decisions 51/81): running → spinner, needs input → bell, done → check,
/// failed → x, idle → muted dot. `waiting-*` (turn closed) is "done", so a
/// finished agent no longer looks like one awaiting a decision (decision 97).
public enum AgentActivity: Sendable, Equatable {
    case running, awaitingDecision, done, failed, idle

    public init(status: String, awaitingDecision: Bool) {
        if awaitingDecision { self = .awaitingDecision; return }
        switch SessionStatus(rawValue: status) ?? .idle {
        case .working: self = .running
        case .waitingUnseen, .waitingFocused, .waitingSeen: self = .done
        case .error: self = .failed
        case .idle: self = .idle
        }
    }

    public var title: String {
        switch self {
        case .running: "Running"
        case .awaitingDecision: "Needs input"
        case .done: "Done"
        case .failed: "Failed"
        case .idle: "Idle"
        }
    }

    public var sortRank: Int {
        switch self {
        case .awaitingDecision: 0
        case .failed: 1
        case .running: 2
        case .done: 3
        case .idle: 4
        }
    }
}
```

`Models.swift` `SessionMeta`: `public let awaitingDecision: Bool`, init parametresi `awaitingDecision: Bool = false` (sonda), CodingKeys'e `awaitingDecision`, decode `try c.decodeIfPresent(Bool.self, forKey: .awaitingDecision) ?? false`, ve:

```swift
    public var activity: AgentActivity { AgentActivity(status: status, awaitingDecision: awaitingDecision) }
```

`ProjectTree.swift` `AgentRowData`'ya `public let activity: AgentActivity` (badge'den sonra), `assembleProjectTree`'de `activity: s.activity`. `AgentRowData`'yı kuran başka yer varsa (grep `AgentRowData(`) güncelle.

- [ ] **Step 8: Pass doğrula** — `swift test` (LumiMobileKit tamamı) → PASS.

- [ ] **Step 9: Karar kaydı** — `docs/decisions.md`:

```markdown
### 97. Telefonda ajan durumu Mac'in durum dilini kullanır; `sessions`'a additive `awaitingDecision` (2026-10-02)

Saha bulgusu: telefonda hangi ajanın çalıştığı, hangisinin beklediği belli değildi. Satırda yalnız 10pt'lik renkli bir nokta vardı ve tüm `waiting-*` durumları (bitmiş-görülmüş dahil) aynı turuncuydu; izin/soru bekleyen ajan bitmiş ajandan ayırt edilemiyordu, chat ekranında durum hiç yoktu.

- **Protokol (additive):** `sessions` içindeki her `SessionMeta` artık `awaitingDecision: Bool` taşır. Kaynak `TerminalEvent.awaitingDecisionChanged`; `RemoteService` değişince `sessions`'ı yeniden yayınlar. Eski telefon alanı yok sayar, yeni telefon alan yoksa `false` kabul eder. Relay değişmez.
- **Telefon:** YENİ `LumiMobileKit/AgentActivity` — Mac `AgentActivityState` eşlemesinin aynısı (çalışıyor → spinner, karar bekliyor → zil "Needs input", bitti → yeşil tik, hata → kırmızı çarpı, boşta → soluk nokta). Projects ajan satırı glif + çalışırken/karar beklerken kısa etiket gösterir; chat ekranının başlığı aynı glifi taşır. Dikkat vurgusu (karar 77) aynen kalır.
```

`CLAUDE.md` Durum paragrafına: `Telefonda ajan durumu Mac'in AgentActivityState dilini kullanır (spinner / zil "Needs input" / tik / çarpı) ve sessions meta'sına additive awaitingDecision eklendi (karar 97, 2026-10-02).`

- [ ] **Step 10: Commit**

```bash
git add LumiPackages LumiMobile docs/decisions.md CLAUDE.md
git commit -m "feat(remote): sessions'a additive awaitingDecision + telefonda AgentActivity (karar 97)"
```

---

### Task 5: Telefon UI — durum glifi, etiket ve chat başlığı

**Files:**
- Create: `LumiMobile/App/AgentActivityGlyph.swift`
- Modify: `LumiMobile/App/ProjectsView.swift` (`agentRow`, `Color(badge:)` uzantısı), `LumiMobile/App/TerminalSessionView.swift`, `LumiMobile/App/SessionListView.swift` (`StatusBadge` kullanımı varsa)

**Interfaces:**
- Consumes: `AgentActivity` (Task 4), `AgentRowData.activity`, `SessionMeta.activity`.
- Produces: `struct AgentActivityGlyph: View { let activity: AgentActivity }`.

- [ ] **Step 1: Glif** — `AgentActivityGlyph.swift`:

```swift
import SwiftUI
import LumiMobileKit

/// Agent status glyph (Mac `AgentActivityIcon` parity, decisions 81/97).
struct AgentActivityGlyph: View {
    let activity: AgentActivity

    var body: some View {
        glyph
            .frame(width: 16, height: 16)
            .accessibilityLabel(activity.title)
    }

    @ViewBuilder private var glyph: some View {
        switch activity {
        case .running:
            ProgressView().controlSize(.mini).tint(.orange)
        case .awaitingDecision:
            Image(systemName: "bell.fill").font(.caption).foregroundStyle(.orange)
        case .done:
            Image(systemName: "checkmark.circle").font(.caption).foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle").font(.caption).foregroundStyle(.red)
        case .idle:
            Circle().fill(Color.secondary.opacity(0.5)).frame(width: 7, height: 7)
        }
    }
}
```

- [ ] **Step 2: Ajan satırı** — `ProjectsView.agentRow`'da `Circle().fill(Color(badge: agent.badge)).frame(width: 10, height: 10)` → `AgentActivityGlyph(activity: agent.activity)`. Zaman etiketinin önüne, yalnız `.running` / `.awaitingDecision` için:

```swift
                if agent.activity == .running || agent.activity == .awaitingDecision {
                    Text(agent.activity.title)
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                }
```

`Color(badge:)` başka yerde kullanılmıyorsa sil (grep `Color(badge:`).

- [ ] **Step 3: Chat başlığı** — `TerminalSessionView`: `.navigationTitle(...)` yerine:

```swift
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    if let s = model.session(sessionId) { AgentActivityGlyph(activity: s.activity) }
                    Text(model.session(sessionId)?.repoName ?? "Session")
                        .font(.headline).lineLimit(1)
                }
            }
            // mevcut topBarTrailing öğeleri aynen kalır
        }
```

(`.navigationTitle` erişilebilirlik/geri butonu metni için kalabilir; principal öğesi görseli verir.)

- [ ] **Step 4: SessionListView** — `StatusBadge` hâlâ kullanılıyorsa aynı glif + `activity.title` metnine geçir (rengi `Badge`'e değil `AgentActivity`'ye bağla). Kullanılmıyorsa dokunma.

- [ ] **Step 5: iOS build** — `cd LumiMobile && xcodegen generate && xcodebuild ...` → `** BUILD SUCCEEDED **`. LumiMobileKit `swift test` → PASS.

- [ ] **Step 6: Commit**

```bash
git add LumiMobile
git commit -m "feat(mobile): ajan satırı ve chat başlığında Mac durum glifi + etiket (karar 97)"
```

---

### Task 6: Telefon — chat'te satır içi kod ve kod bloklarının renklendirilmesi

**Mevcut durum:** `MobileChatMessageView` metni `Text(LocalizedStringKey(text))` ile çiziyor: satır içi markdown'da `` `Foo` `` yalnız monospace, renk yok; ```` ``` ```` blokları ham metin olarak görünüyor.

**Files:**
- Create: `LumiMobile/LumiMobileKit/Sources/LumiMobileKit/ChatMarkdown.swift`
- Create: `LumiMobile/App/ChatMarkdownView.swift`
- Modify: `LumiMobile/App/MobileChatMessageView.swift`
- Test: `LumiMobile/LumiMobileKit/Tests/LumiMobileKitTests/ChatMarkdownTests.swift`

**Interfaces:**
- Produces:
  - `public enum ChatMarkdownSegment: Sendable, Equatable { case prose(String); case code(language: String?, body: String) }`
  - `public func chatMarkdownSegments(_ text: String) -> [ChatMarkdownSegment]`
  - `public func chatInlineAttributed(_ prose: String) -> AttributedString` — inline markdown ayrıştırılmış; satır içi kod run'ları `inlinePresentationIntent` `.code` içerir (view renklendirir). Ayrıştırma başarısızsa düz metin.
  - `struct ChatMarkdownView: View { let text: String }` (App)

- [ ] **Step 1: Failing test** — `ChatMarkdownTests.swift`:

```swift
import XCTest
@testable import LumiMobileKit

final class ChatMarkdownTests: XCTestCase {
    func testSplitsFencedCodeBlocks() {
        let text = "Intro `Foo`\n```swift\nlet x = 1\n```\nAfter"
        XCTAssertEqual(chatMarkdownSegments(text), [
            .prose("Intro `Foo`"),
            .code(language: "swift", body: "let x = 1"),
            .prose("After"),
        ])
    }

    func testUnterminatedFenceStillRendersAsCode() {   // streaming mid-block
        XCTAssertEqual(chatMarkdownSegments("a\n```\nb"), [.prose("a"), .code(language: nil, body: "b")])
    }

    func testPlainTextIsSingleProse() {
        XCTAssertEqual(chatMarkdownSegments("hello\nworld"), [.prose("hello\nworld")])
    }

    func testInlineCodeRunsAreMarked() {
        let attr = chatInlineAttributed("Use `AppModel` and **bold**")
        let codeRuns = attr.runs.filter { $0.inlinePresentationIntent?.contains(.code) == true }
        XCTAssertEqual(codeRuns.map { String(attr[$0.range].characters) }, ["AppModel"])
        XCTAssertEqual(String(attr.characters), "Use AppModel and bold")
    }

    func testInlinePreservesNewlines() {
        XCTAssertEqual(String(chatInlineAttributed("a\nb").characters), "a\nb")
    }
}
```

- [ ] **Step 2: Fail doğrula** — `swift test --filter ChatMarkdownTests` → derleme hatası.

- [ ] **Step 3: Implement** — `ChatMarkdown.swift`:

```swift
import Foundation

/// Chat text split into prose and fenced code blocks (``` … ```).
public enum ChatMarkdownSegment: Sendable, Equatable {
    case prose(String)
    case code(language: String?, body: String)
}

/// Splits on lines starting with ```. An unterminated fence (streaming) is
/// still a code block. Empty prose between blocks is dropped.
public func chatMarkdownSegments(_ text: String) -> [ChatMarkdownSegment] {
    var result: [ChatMarkdownSegment] = []
    var prose: [Substring] = []
    var code: [Substring]? = nil
    var language: String? = nil

    func flushProse() {
        let joined = prose.joined(separator: "\n")
        if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(.prose(joined)) }
        prose.removeAll()
    }

    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let trimmed = line.drop(while: { $0 == " " })
        if trimmed.hasPrefix("```") {
            if let body = code {
                result.append(.code(language: language, body: body.joined(separator: "\n")))
                code = nil; language = nil
            } else {
                flushProse()
                let lang = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                language = lang.isEmpty ? nil : lang
                code = []
            }
        } else if code != nil {
            code!.append(line)
        } else {
            prose.append(line)
        }
    }
    if let body = code { result.append(.code(language: language, body: body.joined(separator: "\n"))) }
    flushProse()
    return result
}

/// Inline markdown (bold/italic/`code`/links) with whitespace preserved. Inline
/// code runs keep `.code` in `inlinePresentationIntent` for the view to tint.
public func chatInlineAttributed(_ prose: String) -> AttributedString {
    let options = AttributedString.MarkdownParsingOptions(
        interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: prose, options: options)) ?? AttributedString(prose)
}
```

- [ ] **Step 4: Pass doğrula** — `swift test --filter ChatMarkdownTests` → PASS.

- [ ] **Step 5: View** — `ChatMarkdownView.swift`:

```swift
import SwiftUI
import LumiMobileKit

/// Assistant prose with Claude-TUI-style tinting: inline `code` (class names,
/// paths) in the accent color on a subtle background; fenced blocks in a
/// horizontally scrolling monospace card.
struct ChatMarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(chatMarkdownSegments(text).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case let .prose(prose):
                    Text(tinted(prose))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case let .code(language, body):
                    codeBlock(language: language, body: body)
                }
            }
        }
    }

    private func tinted(_ prose: String) -> AttributedString {
        var attr = chatInlineAttributed(prose)
        for run in attr.runs where run.inlinePresentationIntent?.contains(.code) == true {
            attr[run.range].foregroundColor = Color.accentColor
            attr[run.range].backgroundColor = Color.accentColor.opacity(0.12)
            attr[run.range].font = .system(.callout, design: .monospaced)
        }
        return attr
    }

    private func codeBlock(language: String?, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let language {
                Text(language).font(.caption2).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(body)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Color.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}
```

`MobileChatMessageView.blockView` assistant dalı:

```swift
                // Assistant: plain prose without a bubble (orca style; spec 2026-09-17),
                // inline code / fenced blocks tinted like the Claude TUI.
                ChatMarkdownView(text: text)
                    .frame(maxWidth: .infinity, alignment: .leading)
```

Kullanıcı balonu değişmez (beyaz yazı + accent zemin; accent renkli kod orada okunmaz).

- [ ] **Step 6: iOS build** — `xcodegen generate` (yeni dosya!) + xcodebuild → `** BUILD SUCCEEDED **`; LumiMobileKit `swift test` → PASS.

- [ ] **Step 7: Commit**

```bash
git add LumiMobile
git commit -m "feat(mobile): chat'te satır içi kod ve kod blokları renkli (Claude TUI paritesi)"
```

---

## Son doğrulama (tüm task'lardan sonra)

- `cd LumiPackages && swift build && swift test && swift build -c release --product Lumi`
- `cd LumiMobile/LumiMobileKit && swift test`
- iOS build komutu
- Manuel (cihaz, kullanıcı): Stop → bar 1 sn içinde kapanır, yeni mesaj gider; multi-select seçimi chat'ten çıkıp dönünce durur; Projects'te çalışan ajan spinner + "Running", izin bekleyen zil + "Needs input"; kod renkli.
- Kurulum: Mac `Scripts/make-app.sh --install` (veya Lumi açıksa `Scripts/install-on-quit.sh`), iOS cihaza build. Relay deploy gerekmez.
