import Foundation
import LumiKit

/// `PlasticReading` + `PlasticWriting` test ikamesi: dönüşler ayarlanabilir,
/// çağrılar kaydedilir. Varsayılan olarak `cm` kurulu ve dizin çalışma alanı
/// DEĞİL (nil) — hata yolu senaryosu kutudan çıkar.
public actor FakePlasticService: PlasticReading, PlasticWriting {
    public struct CheckinCall: Equatable, Sendable {
        public let workspacePath: String
        public let message: String
        public let files: [String]

        public init(workspacePath: String, message: String, files: [String]) {
            self.workspacePath = workspacePath
            self.message = message
            self.files = files
        }
    }

    public var isCLIInstalled = true
    public var workspaceInfoToReturn: PlasticWorkspaceInfo?
    public var statusToReturn: [PlasticFileChange] = []
    public var changesetsToReturn: [PlasticChangeset] = []
    /// Yazma operasyonlarının (checkin/undo) hata enjeksiyonu.
    public var errorToThrow: LumiError?

    public private(set) var cliProbeCount = 0
    public private(set) var workspaceInfoCalls: [String] = []
    public private(set) var statusCalls: [String] = []
    public private(set) var changesetCalls: [(path: String, limit: Int)] = []
    public private(set) var checkinCalls: [CheckinCall] = []
    public private(set) var undoCalls: [[String]] = []

    public init() {}

    public func setCLIInstalled(_ value: Bool) { isCLIInstalled = value }
    public func setWorkspaceInfo(_ value: PlasticWorkspaceInfo?) { workspaceInfoToReturn = value }
    public func setStatus(_ value: [PlasticFileChange]) { statusToReturn = value }
    public func setChangesets(_ value: [PlasticChangeset]) { changesetsToReturn = value }
    public func setErrorToThrow(_ value: LumiError?) { errorToThrow = value }

    public func isCLIAvailable() async -> Bool {
        cliProbeCount += 1
        return isCLIInstalled
    }

    public func workspaceInfo(workspacePath: String) async -> PlasticWorkspaceInfo? {
        workspaceInfoCalls.append(workspacePath)
        return workspaceInfoToReturn
    }

    public func status(workspacePath: String) async -> [PlasticFileChange] {
        statusCalls.append(workspacePath)
        return statusToReturn
    }

    public func recentChangesets(workspacePath: String, limit: Int) async -> [PlasticChangeset] {
        changesetCalls.append((workspacePath, limit))
        return Array(changesetsToReturn.prefix(limit))
    }

    public func checkin(workspacePath: String, message: String, files: [String]) async throws {
        checkinCalls.append(CheckinCall(workspacePath: workspacePath, message: message, files: files))
        if let errorToThrow { throw errorToThrow }
        // Başarılı checkin: gönderilen dosyalar durumdan düşer.
        statusToReturn.removeAll { files.contains($0.path) }
    }

    public func undo(workspacePath: String, files: [String]) async throws {
        undoCalls.append(files)
        if let errorToThrow { throw errorToThrow }
        statusToReturn.removeAll { files.contains($0.path) }
    }
}
