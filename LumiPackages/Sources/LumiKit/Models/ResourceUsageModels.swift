import Foundation

/// Bir process'in tek örneklemi (`ps -eo pid=,ppid=,pcpu=,rss=` satırı).
public struct ProcessSample: Sendable, Equatable {
    public let pid: Int32
    public let parentPID: Int32
    /// Yüzde; birden fazla çekirdek 100'ü aşabilir.
    public let cpuPercent: Double
    public let residentBytes: UInt64

    public init(pid: Int32, parentPID: Int32, cpuPercent: Double, residentBytes: UInt64) {
        self.pid = pid
        self.parentPID = parentPID
        self.cpuPercent = cpuPercent
        self.residentBytes = residentBytes
    }
}

/// CPU + RSS toplamı — satır, grup ve özet aynı tipi taşır.
public struct ResourceMetrics: Sendable, Equatable {
    public var cpuPercent: Double
    public var residentBytes: UInt64

    public init(cpuPercent: Double = 0, residentBytes: UInt64 = 0) {
        self.cpuPercent = cpuPercent
        self.residentBytes = residentBytes
    }

    public static let zero = ResourceMetrics()

    public static func + (lhs: ResourceMetrics, rhs: ResourceMetrics) -> ResourceMetrics {
        ResourceMetrics(
            cpuPercent: lhs.cpuPercent + rhs.cpuPercent,
            residentBytes: lhs.residentBytes + rhs.residentBytes
        )
    }
}

/// Tüm sistemin process tablosu; kök pid'den alt ağaç toplamı çıkarır.
///
/// Orca `collector.ts` ile aynı yaklaşım: tek `ps` çağrısı, ppid → children
/// indeksi, terminal başına PTY çocuk sürecinin alt ağacı toplanır.
public struct ProcessTable: Sendable, Equatable {
    public let samples: [Int32: ProcessSample]
    public let children: [Int32: [Int32]]

    public init(samples: [ProcessSample]) {
        var byPID: [Int32: ProcessSample] = [:]
        var children: [Int32: [Int32]] = [:]
        for sample in samples {
            byPID[sample.pid] = sample
            children[sample.parentPID, default: []].append(sample.pid)
        }
        self.samples = byPID
        self.children = children
    }

    public static let empty = ProcessTable(samples: [])

    /// Kök + tüm torunlarının toplamı. Kök tabloda yoksa `nil` (süreç bitmiş).
    /// Ziyaret kümesi, `ps` yarış koşullarında oluşabilecek döngülere karşı korur.
    public func subtreeMetrics(root: Int32) -> ResourceMetrics? {
        guard samples[root] != nil else { return nil }
        var total = ResourceMetrics.zero
        var visited: Set<Int32> = []
        var stack = [root]
        while let pid = stack.popLast() {
            guard visited.insert(pid).inserted, let sample = samples[pid] else { continue }
            total = total + ResourceMetrics(cpuPercent: sample.cpuPercent, residentBytes: sample.residentBytes)
            stack.append(contentsOf: children[pid] ?? [])
        }
        return total
    }

    /// Alt ağaçtaki tüm pid'ler (kök dahil).
    public func subtreePIDs(root: Int32) -> Set<Int32> {
        var visited: Set<Int32> = []
        var stack = [root]
        while let pid = stack.popLast() {
            guard samples[pid] != nil, visited.insert(pid).inserted else { continue }
            stack.append(contentsOf: children[pid] ?? [])
        }
        return visited
    }

    /// `ps -eo pid=,ppid=,pcpu=,rss=` çıktısını ayrıştırır. Yerel ayara bağlı
    /// ondalık virgül (`0,5`) noktaya çevrilir; bozuk satırlar atlanır.
    public static func parse(psOutput: String) -> ProcessTable {
        let samples = psOutput.split(whereSeparator: \.isNewline).compactMap { line -> ProcessSample? in
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 4,
                  let pid = Int32(fields[0]),
                  let ppid = Int32(fields[1]) else { return nil }
            let cpu = Double(fields[2].replacingOccurrences(of: ",", with: ".")) ?? 0
            let rssKB = UInt64(fields[3]) ?? 0
            return ProcessSample(
                pid: pid, parentPID: ppid,
                cpuPercent: cpu.isFinite && cpu > 0 ? cpu : 0,
                residentBytes: rssKB * 1024
            )
        }
        return ProcessTable(samples: samples)
    }
}

/// Uygulamanın kendi kullanımı: ana süreç + yardımcı süreçler (terminal PTY
/// ağaçları hariç torunlar).
public struct AppResourceUsage: Sendable, Equatable {
    public let main: ResourceMetrics
    public let helpers: ResourceMetrics

    public init(main: ResourceMetrics, helpers: ResourceMetrics) {
        self.main = main
        self.helpers = helpers
    }

    public var total: ResourceMetrics { main + helpers }
}

/// Bir örnekleme turunun sonucu.
public struct ResourceUsageSnapshot: Sendable, Equatable {
    public let sampledAt: Date
    /// Terminal → PTY alt ağacı toplamı. Süreci bitmiş terminal listede yoktur.
    public let terminals: [TerminalID: ResourceMetrics]
    public let app: AppResourceUsage
    public let hostMemoryBytes: UInt64

    public init(
        sampledAt: Date,
        terminals: [TerminalID: ResourceMetrics],
        app: AppResourceUsage,
        hostMemoryBytes: UInt64
    ) {
        self.sampledAt = sampledAt
        self.terminals = terminals
        self.app = app
        self.hostMemoryBytes = hostMemoryBytes
    }

    /// Terminal toplamları (alt bar rozeti: Σ RSS).
    public var terminalTotal: ResourceMetrics {
        terminals.values.reduce(.zero, +)
    }

    /// Tablodan snapshot üretir: her terminalin kök pid'inden alt ağaç toplanır,
    /// uygulamanın torunlarından terminal ağaçları düşülür → `helpers`.
    public static func make(
        table: ProcessTable,
        appPID: Int32,
        terminalRoots: [TerminalID: Int32],
        hostMemoryBytes: UInt64,
        sampledAt: Date
    ) -> ResourceUsageSnapshot {
        var terminals: [TerminalID: ResourceMetrics] = [:]
        var terminalPIDs: Set<Int32> = []
        for (id, root) in terminalRoots {
            guard let metrics = table.subtreeMetrics(root: root) else { continue }
            terminals[id] = metrics
            terminalPIDs.formUnion(table.subtreePIDs(root: root))
        }
        let main = table.samples[appPID].map {
            ResourceMetrics(cpuPercent: $0.cpuPercent, residentBytes: $0.residentBytes)
        } ?? .zero
        let helpers = table.subtreePIDs(root: appPID)
            .subtracting(terminalPIDs)
            .subtracting([appPID])
            .compactMap { table.samples[$0] }
            .reduce(ResourceMetrics.zero) {
                $0 + ResourceMetrics(cpuPercent: $1.cpuPercent, residentBytes: $1.residentBytes)
            }
        return ResourceUsageSnapshot(
            sampledAt: sampledAt,
            terminals: terminals,
            app: AppResourceUsage(main: main, helpers: helpers),
            hostMemoryBytes: hostMemoryBytes
        )
    }
}

/// Orca `formatMemory` / `formatCpu` paritesi.
public enum ResourceUsageFormat {
    private static let kilobyte: Double = 1024
    private static let megabyte: Double = 1024 * 1024
    private static let gigabyte: Double = 1024 * 1024 * 1024

    public static func memory(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        if value < megabyte { return "\(Int((value / kilobyte).rounded())) KB" }
        if value < gigabyte { return String(format: "%.1f MB", value / megabyte) }
        return String(format: "%.2f GB", value / gigabyte)
    }

    public static func cpu(_ percent: Double) -> String {
        String(format: "%.1f%%", percent)
    }
}
