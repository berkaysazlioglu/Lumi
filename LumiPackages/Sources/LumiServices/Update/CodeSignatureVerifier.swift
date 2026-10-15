import Foundation
import Security

/// Developer ID imza kontrolleri (karar 118) — Security.framework, süreç yok.
public protocol CodeSignatureVerifying: Sendable {
    /// Çalışan uygulama Developer ID ile imzalıysa takım kimliği, değilse `nil`.
    func runningDeveloperIDTeam() -> String?
    /// `appURL` aynı takımın Developer ID imzasını taşıyor ve imzası (iç içe
    /// kod dahil) bozulmamış mı.
    func isSignedByDeveloperID(_ appURL: URL, team: String) -> Bool
}

public struct CodeSignatureVerifier: CodeSignatureVerifying {
    public init() {}

    public func runningDeveloperIDTeam() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode,
              let team = Self.teamIdentifier(of: staticCode)
        else { return nil }
        // Çalışan kopyanın kaynaklarını hash'lemek açılışta gereksiz maliyettir;
        // burada soru yalnız "hangi sertifikayla imzalı".
        let flags = SecCSFlags(rawValue: kSecCSDoNotValidateResources)
        return Self.satisfiesDeveloperID(staticCode, team: team, flags: flags) ? team : nil
    }

    public func isSignedByDeveloperID(_ appURL: URL, team: String) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode
        else { return false }
        let flags = SecCSFlags(
            rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode
        )
        return Self.satisfiesDeveloperID(staticCode, team: team, flags: flags)
    }

    /// Apple'ın Developer ID uygulama sertifikası zinciri + yaprakta bizim takım.
    /// Apple Development sertifikası bu gereksinimi KARŞILAMAZ — yerel build
    /// güncelleyiciyi açmaz.
    static func developerIDRequirement(team: String) -> String {
        "anchor apple generic"
            + " and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
            + " and certificate leaf[subject.OU] = \"\(team)\""
    }

    private static func satisfiesDeveloperID(_ code: SecStaticCode, team: String, flags: SecCSFlags) -> Bool {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(
            developerIDRequirement(team: team) as CFString, SecCSFlags(), &requirement
        ) == errSecSuccess, let requirement else { return false }
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    private static func teamIdentifier(of code: SecStaticCode) -> String? {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(
            code, SecCSFlags(rawValue: kSecCSSigningInformation), &info
        ) == errSecSuccess,
            let dictionary = info as? [String: Any]
        else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
