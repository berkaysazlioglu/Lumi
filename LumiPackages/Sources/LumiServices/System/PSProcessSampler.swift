import Foundation
import LumiKit

/// Tek `ps` çağrısıyla tüm process tablosunu örnekler (Orca `collector.ts`
/// paritesi: `ps -eo pid=,ppid=,pcpu=,rss=`). Process I/O `ProcessRunning`
/// enjeksiyonundan geçer; başarısızlıkta `nil`, store bunu "örnek yok" sayar.
public struct PSProcessSampler: ProcessSampling {
    public static let executable = "/bin/ps"
    public static let arguments = ["-eo", "pid=,ppid=,pcpu=,rss="]
    public static let timeout: TimeInterval = 5

    private let runner: any ProcessRunning

    public init(runner: any ProcessRunning = SystemProcessRunner()) {
        self.runner = runner
    }

    public func sampleProcessTable() async -> ProcessTable? {
        guard let output = await runner.run(Self.executable, arguments: Self.arguments, timeout: Self.timeout),
              output.exitCode == 0 else { return nil }
        return ProcessTable.parse(psOutput: output.stdout)
    }
}
