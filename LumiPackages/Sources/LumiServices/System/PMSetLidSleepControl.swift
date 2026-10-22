import Foundation
import IOKit.ps
import LumiKit

/// `pmset disablesleep` ile kapak kapalıyken uykuyu engeller (karar 122).
///
/// Okuma `pmset -g` ile root'suz yapılır; yazma `osascript … with
/// administrator privileges` üzerinden sistemin yönetici şifresi dialogunu
/// açar. Process I/O `ProcessRunning` enjeksiyonundan geçer.
public struct PMSetLidSleepControl: LidSleepControlling {
    public static let pmset = "/usr/bin/pmset"
    public static let osascript = "/usr/bin/osascript"
    static let readTimeout: TimeInterval = 5
    /// Kullanıcının şifreyi yazması için tanınan süre.
    static let authorizationTimeout: TimeInterval = 120
    /// AppleScript "User canceled." hata kodu.
    static let userCanceledCode = "-128"

    private let runner: any ProcessRunning

    public init(runner: any ProcessRunning = SystemProcessRunner()) {
        self.runner = runner
    }

    public func isSleepDisabled() async -> Bool? {
        guard let output = await runner.run(Self.pmset, arguments: ["-g"], timeout: Self.readTimeout),
              output.exitCode == 0 else { return nil }
        return Self.parseSleepDisabled(output.stdout)
    }

    public func setSleepDisabled(_ disabled: Bool) async -> LidSleepChange {
        let output = await runner.run(
            Self.osascript, arguments: ["-e", Self.script(disabled: disabled)],
            timeout: Self.authorizationTimeout
        )
        guard let output else { return .failed("Timed out waiting for authorization") }
        if output.exitCode == 0 { return .applied }
        if output.stderr.contains(Self.userCanceledCode) { return .cancelled }
        let message = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return .failed(message.isEmpty ? "pmset exited with \(output.exitCode)" : message)
    }

    public func isOnBatteryPower() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPMBatteryPowerKey
    }

    /// `pmset -g` çıktısında `SleepDisabled 1` satırı; satır yoksa kapalıdır.
    static func parseSleepDisabled(_ output: String) -> Bool {
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            if fields.first == "SleepDisabled" { return fields.dropFirst().first == "1" }
        }
        return false
    }

    static func script(disabled: Bool) -> String {
        let command = "\(pmset) -a disablesleep \(disabled ? 1 : 0)"
        let prompt = disabled
            ? "Lumi wants to keep your Mac awake when the lid is closed."
            : "Lumi wants to restore normal sleep when the lid is closed."
        return "do shell script \"\(command)\" with prompt \"\(prompt)\" with administrator privileges"
    }
}
