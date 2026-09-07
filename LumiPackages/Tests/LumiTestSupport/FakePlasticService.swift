import Foundation
import LumiKit

/// `PlasticReading` test ikamesi: dönüşler ayarlanabilir, çağrılar kaydedilir.
/// Varsayılan olarak `cm` kurulu ve dizin çalışma alanı DEĞİL (nil) —
/// hata yolu senaryosu kutudan çıkar.
public actor FakePlasticService: PlasticReading {
    public var isCLIInstalled = true
    public var workspaceInfoToReturn: PlasticWorkspaceInfo?
    public var statusToReturn: [PlasticFileChange] = []
    public var changesetsToReturn: [PlasticChangeset] = []

    public private(set) var cliProbeCount = 0
    public private(set) var workspaceInfoCalls: [String] = []
    public private(set) var statusCalls: [String] = []
    public private(set) var changesetCalls: [(path: String, limit: Int)] = []

    public init() {}

    public func setCLIInstalled(_ value: Bool) { isCLIInstalled = value }
    public func setWorkspaceInfo(_ value: PlasticWorkspaceInfo?) { workspaceInfoToReturn = value }
    public func setStatus(_ value: [PlasticFileChange]) { statusToReturn = value }
    public func setChangesets(_ value: [PlasticChangeset]) { changesetsToReturn = value }

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
}
