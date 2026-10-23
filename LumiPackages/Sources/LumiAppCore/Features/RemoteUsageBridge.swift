import Foundation
import Observation
import LumiKit
import LumiRemote
import LumiState

/// Kota store'larını (karar 32/75) telefona taşır (karar 128): store'lar her
/// değiştiğinde yeni bir `RemoteUsageReport` üretilir ve sırayla yayınlanır.
/// Yalnız Mac'te açık göstergeler rapora girer.
@MainActor
final class RemoteUsageBridge {
    private let usage: UsageFeatureAssembly
    private let reports: AsyncStream<RemoteUsageReport>
    private let sink: AsyncStream<RemoteUsageReport>.Continuation
    private var publishTask: Task<Void, Never>?
    private var isObserving = false

    init(usage: UsageFeatureAssembly) {
        self.usage = usage
        (reports, sink) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    func start(publish: @escaping @Sendable (RemoteUsageReport) async -> Void) {
        guard publishTask == nil else { return }
        let reports = reports
        publishTask = Task {
            for await report in reports { await publish(report) }
        }
        isObserving = true
        observe()
    }

    func stop() {
        isObserving = false
        sink.finish()
        publishTask?.cancel()
        publishTask = nil
    }

    private func observe() {
        guard isObserving else { return }
        let report = withObservationTracking {
            Self.makeReport(stores: usage.usageStores, deepSeek: usage.deepSeekBalance)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe() }
        }
        sink.yield(report)
    }

    static func makeReport(
        stores: [AgentProvider: UsageStore], deepSeek: DeepSeekBalanceStore?
    ) -> RemoteUsageReport {
        let providers = AgentProvider.allCases.compactMap { provider -> RemoteUsageReport.Provider? in
            guard let store = stores[provider], store.isEnabled else { return nil }
            return .init(provider: provider, snapshot: store.snapshot, errorMessage: store.errorMessage)
        }
        let entry = deepSeek.flatMap { store in
            store.isEnabled
                ? RemoteUsageReport.DeepSeekEntry(balance: store.balance, errorMessage: store.errorMessage)
                : nil
        }
        return RemoteUsageReport(providers: providers, deepSeek: entry)
    }
}
