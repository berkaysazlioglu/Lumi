import Foundation
import LumiKit
import Observation

/// Onboarding sihirbazının adımları (design/03 §4 bootstrap zinciri).
/// Sıra `allCases` ile tanımlıdır — `advance()`/`back()` indeksle değil bu
/// listeyle yürür, yeni adım eklemek tek satırdır.
public enum OnboardingStep: Int, CaseIterable, Sendable, Equatable {
    case welcome
    case checks
    case projectsRoot
    case done
}

/// Onboarding akışının state'i (refactor 5.8): adım, seçimler, sistem
/// kontrolleri ve tamamlama yan etkisi. View saf render'a iner.
///
/// **Bağlayıcı kural (design/03 §4): fail bloklar, warn bloklamaz.**
@Observable
@MainActor
public final class OnboardingStore {
    public private(set) var step: OnboardingStep = .welcome
    public private(set) var checks: [SystemCheckResult] = []
    public private(set) var isRunningChecks = false
    /// Welcome adımındaki sağlayıcı seçimi; `complete()` config'e yazar.
    public var provider: AgentProvider = .claude
    /// Projects root adımında seçilen klasör (boşken ilerlenemez).
    public private(set) var projectsRoot = ""

    @ObservationIgnored private let system: any SystemServicing
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let toasts: ToastStore
    /// Sihirbaz kapanınca `WorkspaceStore.isOnboardingActive`'i düşüren kanca.
    @ObservationIgnored private let onComplete: @MainActor () -> Void

    public init(
        system: any SystemServicing,
        settings: SettingsStore,
        toasts: ToastStore,
        onComplete: @escaping @MainActor () -> Void
    ) {
        self.system = system
        self.settings = settings
        self.toasts = toasts
        self.onComplete = onComplete
    }

    // MARK: - Türev okumalar

    public var isFirstStep: Bool { step == OnboardingStep.allCases.first }
    public var isLastStep: Bool { step == OnboardingStep.allCases.last }

    /// Sonraki adıma geçiş (ya da son adımda tamamlama) mümkün mü?
    /// - `.checks`: kontroller koşarken ve bir `fail` varken bloke; `warn` serbest.
    /// - `.projectsRoot`: klasör seçilmeden bloke.
    public var canAdvance: Bool {
        switch step {
        case .checks:
            return !isRunningChecks && !checks.contains { $0.status == .fail }
        case .projectsRoot:
            return !projectsRoot.isEmpty
        case .welcome, .done:
            return true
        }
    }

    // MARK: - Akış

    public func advance() {
        guard canAdvance else { return }
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    public func back() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    // MARK: - Sistem kontrolleri

    /// Checks adımına ilk girişte otomatik koşar; "Re-run" aynı yolu kullanır.
    public func runChecksIfNeeded() async {
        guard checks.isEmpty, !isRunningChecks else { return }
        await runChecks()
    }

    public func runChecks() async {
        guard !isRunningChecks else { return }
        isRunningChecks = true
        checks = await system.runChecks(selectedProvider: provider)
        isRunningChecks = false
    }

    /// Düzeltilebilir bir kontrolün kurulum sayfasını açar (karar 5: engellenen
    /// URL görünür hatadır).
    public func fix(_ check: SystemCheckResult) {
        guard let url = check.fixURL else { return }
        toasts.reporting {
            try system.openExternal(url)
        }
    }

    // MARK: - Projects root

    public func chooseProjectsRoot() async {
        guard let path = await system.chooseFolder() else { return }
        projectsRoot = path
    }

    // MARK: - Tamamlama

    /// Anlık-uygulama modeli (karar 3) sayesinde tek config yazımı yeterli:
    /// koordinatör repo taramasını ve diğer yan etkileri kendisi tetikler.
    public func complete() {
        let selectedProvider = provider
        let selectedRoot = projectsRoot
        settings.apply {
            $0.aiProvider = selectedProvider
            $0.projectsRoot = selectedRoot
        }
        onComplete()
    }
}
