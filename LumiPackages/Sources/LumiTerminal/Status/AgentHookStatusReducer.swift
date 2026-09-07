import LumiKit

/// Hook olayının durum makinesine çevrilmiş etkisi. Pipeline bunları
/// `StatusStateMachine` / `DecisionTracker` çağrılarına indirir; reducer'ın
/// kendisi hiçbir durum yayınlamaz (saf, io queue'ya confine).
enum AgentHookEffect: Equatable {
    /// Lider ya da bir alt ajan çalışıyor → `working`.
    case working
    /// Turn bitti, ajan girdi bekliyor → `working` ise `waiting-*`.
    case turnEnded
    /// Oturum sınırı (`SessionStart`): ne çalışıyor ne bekliyor → `idle`.
    case sessionIdle
    /// Ajan süreci çıktı (`SessionEnd`): `idle` + sağlayıcı kimliği düşer,
    /// hook otoritesi kalkar (düz shell'e dönüş).
    case sessionEnded
    /// İzin promptu ya da soru: "karar bekliyor" bayrağı kalkar.
    case decisionRequested
    /// Karar verildi/tur ilerledi: bayrak iner.
    case decisionResolved
}

/// Claude Code / Codex hook olaylarını Lumi'nin 6 durumlu makinesine çeviren
/// saf reducer (karar 45; Orca `normalizeClaudeEvent` / `normalizeCodexEvent`
/// çekirdeği).
///
/// Model: lider turn'ü + çalışan alt ajan kadrosu. Terminal, lider turn
/// açıkken YA DA kadroda çalışan alt ajan varken `working`tir; ikisi de
/// bitince turn bitmiş sayılır. Böylece lider `Stop` verdiği hâlde arka planda
/// koşan bir alt ajan kartı erkenden "bekliyor"a düşürmez; alt ajan bitince
/// (`SubagentStop`) kart kendiliğinden düşer.
///
/// İlk olayla birlikte `isBound` açılır: bundan sonra OSC başlığı / çıktı
/// sessizliği sezgileri durumu SÜRMEZ — hook'lar otoritedir. `SessionEnd`
/// otoriteyi bırakır (ajan çıktı, geride düz shell kaldı).
final class AgentHookStatusReducer {
    private(set) var isBound = false
    private(set) var provider: AgentProvider?
    /// Lider turn'ü açık mı.
    private(set) var isLeadRunning = false
    /// Çalışan alt ajan kimlikleri (`agent_id`).
    private(set) var workingSubagents: Set<String> = []
    /// Bekleyen karar (izin/soru): hangi araç ve hangi ajan sordu.
    private var pendingDecision: (toolName: String?, agentID: String?)?

    var isRunning: Bool { isLeadRunning || !workingSubagents.isEmpty }

    /// Claude `SessionStart.source` değerlerinden idle sayılanlar (Orca
    /// allowlist'i). `compact` turn ortasında ateşler; tanınmayan kaynak
    /// fail-closed düşer — canlı turn idle'a çekilmez.
    private static let idleSessionSources: Set<String> = ["startup", "resume", "clear"]

    func reduce(_ event: AgentHookEvent) -> [AgentHookEffect] {
        isBound = true
        provider = event.provider
        switch event.kind {
        case .sessionStart:
            return reduceSessionStart(event)
        case .sessionEnd:
            guard event.isLead else { return [] }
            resetAll()
            isBound = false
            provider = nil
            return [.sessionEnded]
        case .userPromptSubmit:
            guard event.isLead else { return runningEffect() }
            if event.isCompactContinuationPrompt { return [] }
            isLeadRunning = true
            return [.decisionResolved] + runningEffect()
        case .preToolUse:
            return reducePreToolUse(event)
        case .postToolUse, .postToolUseFailure:
            return reducePostToolUse(event)
        case .permissionRequest:
            noteSubagentActivity(event)
            pendingDecision = (event.toolName, event.agentID)
            return [.decisionRequested] + runningEffect()
        case .stop, .stopFailure:
            return reduceStop(event)
        case .subagentStart:
            if let id = event.agentID { workingSubagents.insert(id) }
            return runningEffect()
        case .subagentStop:
            guard let id = event.agentID else { return runningEffect() }
            workingSubagents.remove(id)
            return resolveDecisionIfOwned(by: id) + runningEffect()
        case .teammateIdle:
            return reduceTeammateIdle(event)
        case .postCompact:
            // Manuel /compact idle prompt'ta biter ve Stop yaymaz (Orca
            // STA-2915); otomatik compact turn içinde koşar, hiçbir şey demez.
            guard event.isLead, event.trigger == "manual" else { return [] }
            isLeadRunning = false
            pendingDecision = nil
            return [.decisionResolved] + runningEffect()
        case .unknown:
            return []
        }
    }

    /// Esc/Ctrl+C sonrası hook gelmedi: lider turn'ü kesilmiş say. Çalışan
    /// alt ajan varsa çıkarım yapılmaz — Ctrl+C arka plan çocuklarını
    /// durdurmaz (Orca `inferInterrupt`).
    func inferInterrupt() -> [AgentHookEffect] {
        guard isBound, isLeadRunning, workingSubagents.isEmpty else { return [] }
        isLeadRunning = false
        pendingDecision = nil
        return [.decisionResolved, .turnEnded]
    }

    /// PTY exit: her şey sıfırlanır, otorite düşer.
    func reset() {
        resetAll()
        isBound = false
        provider = nil
    }

    // MARK: - Olay grupları

    private func reduceSessionStart(_ event: AgentHookEvent) -> [AgentHookEffect] {
        guard event.isLead else { return [] }
        if event.provider == .claude, let source = event.source,
           !Self.idleSessionSources.contains(source) {
            return []
        }
        // Yeni süreç paneli devraldı: eski kadro/karar yeni oturumu working'e
        // çekemez (Orca: Codex ile aynı sıfırlama).
        resetAll()
        return [.decisionResolved, .sessionIdle]
    }

    private func reducePreToolUse(_ event: AgentHookEvent) -> [AgentHookEffect] {
        noteSubagentActivity(event)
        if event.isUserQuestionTool {
            // AskUserQuestion / request_user_input: araç "çalışırken" ajan
            // aslında insan cevabı bekliyor.
            pendingDecision = (event.toolName, event.agentID)
            return [.decisionRequested] + runningEffect()
        }
        if event.isLead { isLeadRunning = true }
        // Model yeni bir araca geçti: bekleyen izin cevaplanmış (ya da
        // reddedilip devam edilmiş) demektir.
        return resolveDecisionIfSameActor(event) + runningEffect()
    }

    private func reducePostToolUse(_ event: AgentHookEvent) -> [AgentHookEffect] {
        noteSubagentActivity(event)
        if event.isLead { isLeadRunning = true }
        return resolveDecisionIfMatchingTool(event) + runningEffect()
    }

    private func reduceStop(_ event: AgentHookEvent) -> [AgentHookEffect] {
        guard event.isLead else {
            // Alt ajanın kendi Stop'u (bazı Claude sürümleri): kadrodan düş.
            if let id = event.agentID { workingSubagents.remove(id) }
            return runningEffect()
        }
        isLeadRunning = false
        pendingDecision = nil
        if event.isInterrupt {
            // Kesme her şeyi durdurur; kadro kanıtı geçersiz.
            workingSubagents.removeAll()
        } else if let running = event.runningBackgroundAgentIDs {
            // Claude `background_tasks` envanteri kadronun tek otoritesidir:
            // listede olmayan çocuk bitmiş demektir (kaçırılmış SubagentStop
            // paneli sonsuza dek working'de bırakmasın).
            workingSubagents = Set(running)
        }
        return [.decisionResolved] + runningEffect()
    }

    private func reduceTeammateIdle(_ event: AgentHookEvent) -> [AgentHookEffect] {
        guard let name = event.teammateName else { return runningEffect() }
        // Adlandırılmış teammate'lerin `agent_id`si `a<name>-<hex>` biçimindedir
        // (Orca `claudeTeammateIdMatchesName`); yalnız bu eşleşme güvenlidir.
        let prefix = "a\(name)-"
        let idle = workingSubagents.filter { id in
            id.hasPrefix(prefix) && !id.dropFirst(prefix.count).contains("-")
        }
        workingSubagents.subtract(idle)
        var effects: [AgentHookEffect] = []
        for id in idle { effects += resolveDecisionIfOwned(by: id) }
        return effects + runningEffect()
    }

    // MARK: - Yardımcılar

    private func runningEffect() -> [AgentHookEffect] {
        [isRunning ? .working : .turnEnded]
    }

    /// Alt ajanın araç trafiği, kaçırılmış bir `SubagentStart`'ı telafi eder:
    /// çocuk çalışıyor demektir.
    private func noteSubagentActivity(_ event: AgentHookEvent) {
        if let id = event.agentID { workingSubagents.insert(id) }
    }

    private func resolveDecisionIfOwned(by agentID: String) -> [AgentHookEffect] {
        guard pendingDecision?.agentID == agentID else { return [] }
        pendingDecision = nil
        return [.decisionResolved]
    }

    /// Aynı aktör (lider ya da aynı alt ajan) yeni araca geçti → karar bitti.
    private func resolveDecisionIfSameActor(_ event: AgentHookEvent) -> [AgentHookEffect] {
        guard let pending = pendingDecision, pending.agentID == event.agentID else { return [] }
        pendingDecision = nil
        return [.decisionResolved]
    }

    /// PostToolUse: paralel araçlardan yalnız bekleyen aracın bitişi kararı
    /// kapatır (araç adı bilinmiyorsa aktör eşleşmesi yeter).
    private func resolveDecisionIfMatchingTool(_ event: AgentHookEvent) -> [AgentHookEffect] {
        guard let pending = pendingDecision, pending.agentID == event.agentID else { return [] }
        if let tool = pending.toolName, let done = event.toolName, tool != done { return [] }
        pendingDecision = nil
        return [.decisionResolved]
    }

    private func resetAll() {
        isLeadRunning = false
        workingSubagents.removeAll()
        pendingDecision = nil
    }
}
