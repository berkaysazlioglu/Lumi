import CryptoKit
import Foundation
import LumiKit

/// GitHub Releases'teki notarize edilmiş zip'i indirip doğrulayan ve Lumi
/// kapanınca kuran servis (karar 118).
///
/// Güven zinciri iki halkadır: zip release'in `SHA256SUMS` dosyasıyla eşleşir
/// (bozuk/yarım indirme), açılan `.app` çalışan kopyayla AYNI takımın
/// Developer ID imzasını taşır (GitHub hesabı ele geçirilse bile bizim
/// sertifikamız olmadan kurulacak bir build üretilemez).
///
/// Dizin düzeni (`~/.lumi/updates`):
/// - `staged/<sürüm>/Lumi.app` — kurulmayı bekleyen sürüm (kurulumda silinir)
/// - `install.sh`, `install.log`, `com.lumi.app-update.plist` — tek seferlik
///   LaunchAgent'ın script'i, çıktısı ve tanımı (`launchctl bootstrap` plist'i
///   buradan yükler; `~/Library/LaunchAgents`'a konmaz, login'de yeniden koşmaz)
/// - `install-failed` — son denemenin hatası (bir sonraki açılışta okunur)
public actor AppUpdateInstaller: AppUpdateInstalling {
    static let downloadTimeout: TimeInterval = 120
    static let processTimeout: TimeInterval = 60
    static let launchctlTimeout: TimeInterval = 10

    private let root: URL
    private let bundleURL: URL
    private let bundleIdentifier: String?
    private let architecture: String
    private let processID: Int32
    private let userID: uid_t
    private let session: URLSession
    private let runner: any ProcessRunning
    private let signatures: any CodeSignatureVerifying
    /// Çalışan kopyanın Developer ID takımı; `nil` → güncelleyici kapalı.
    private let team: String?

    public init(
        root: URL,
        bundleURL: URL = Bundle.main.bundleURL,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        architecture: String = AppUpdateInstaller.currentArchitecture,
        processID: Int32 = ProcessInfo.processInfo.processIdentifier,
        userID: uid_t = getuid(),
        session: URLSession = .shared,
        runner: any ProcessRunning = SystemProcessRunner(),
        signatures: any CodeSignatureVerifying = CodeSignatureVerifier()
    ) {
        self.root = root
        self.bundleURL = bundleURL
        self.bundleIdentifier = bundleIdentifier
        self.architecture = architecture
        self.processID = processID
        self.userID = userID
        self.session = session
        self.runner = runner
        self.signatures = signatures
        self.team = signatures.runningDeveloperIDTeam()
    }

    /// Release asset adlarındaki mimari (`make-app.sh`: `uname -m`).
    public static var currentArchitecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }

    private var stagingDir: URL { root.appendingPathComponent("staged") }
    private var scriptURL: URL { root.appendingPathComponent("install.sh") }
    private var logURL: URL { root.appendingPathComponent("install.log") }
    private var failureURL: URL { root.appendingPathComponent("install-failed") }
    private var plistURL: URL { root.appendingPathComponent("\(AppUpdateInstallScript.label).plist") }

    /// Zip'in kökü her zaman `Lumi.app`'tir (`ditto --keepParent`); kullanıcı
    /// kurulu kopyanın adını değiştirmiş olsa da sahnede bu ad aranır.
    static let stagedAppName = "Lumi.app"

    // MARK: - Destek

    public nonisolated func installSupport() -> AppUpdateInstallSupport {
        guard team != nil else { return .unsignedBuild }
        let path = bundleURL.path
        let parent = bundleURL.deletingLastPathComponent().path
        let files = FileManager.default
        // Translocation salt-okunur bir bağlama noktasıdır; yazılabilirlik
        // testi de yakalardı ama yol kendi başına açık bir işarettir.
        guard !path.contains("/AppTranslocation/"),
              files.isWritableFile(atPath: parent),
              files.isWritableFile(atPath: path)
        else { return .readOnlyLocation(path: path) }
        return .supported
    }

    // MARK: - Hazırlık

    public func prepare(_ release: AppRelease) async throws -> StagedAppUpdate {
        guard let team, installSupport().isSupported else {
            throw Self.failure("this copy of Lumi can't update itself")
        }
        guard let package = release.packageAsset(architecture: architecture) else {
            throw Self.failure("release \(release.version) has no \(architecture) build")
        }
        guard let checksums = release.checksumsAsset else {
            throw Self.failure("release \(release.version) has no checksum file")
        }
        let versionDir = stagingDir.appendingPathComponent(release.assetVersion)
        let app = versionDir.appendingPathComponent(Self.stagedAppName)
        if isValidStagedApp(app, release: release, team: team) {
            return StagedAppUpdate(release: release, appPath: app.path)
        }

        // Bu sürümün yarım kalmış bir denemesi temizlenir; DİĞER sürümlerin
        // sahnesine ancak bu sürüm hazır olunca dokunulur.
        try? FileManager.default.removeItem(at: versionDir)
        do {
            try FileManager.default.createDirectory(at: versionDir, withIntermediateDirectories: true)
        } catch {
            throw Self.failure("could not create \(versionDir.path): \(error.localizedDescription)")
        }

        let expected = try await expectedChecksum(of: package, in: checksums)
        let zip = try await download(package, into: versionDir)
        guard try Self.sha256(of: zip) == expected else {
            try? FileManager.default.removeItem(at: versionDir)
            throw Self.failure("checksum mismatch for \(package.name)")
        }
        try await extract(zip, into: versionDir)
        try? FileManager.default.removeItem(at: zip)

        guard isValidStagedApp(app, release: release, team: team) else {
            try? FileManager.default.removeItem(at: versionDir)
            throw Self.failure("the downloaded app is not a Lumi \(release.version) build signed by this developer")
        }
        removeStagedVersions(except: versionDir)
        return StagedAppUpdate(release: release, appPath: app.path)
    }

    /// Yalnız tek sürüm sahnede kalır (eski indirmeler yer kaplamasın).
    private func removeStagedVersions(except keep: URL) {
        let siblings = (try? FileManager.default.contentsOfDirectory(
            at: stagingDir, includingPropertiesForKeys: nil
        )) ?? []
        for sibling in siblings where sibling.standardizedFileURL != keep.standardizedFileURL {
            try? FileManager.default.removeItem(at: sibling)
        }
    }

    /// Bundle kimliği + sürüm + Developer ID imzası. Eski bir sahne de aynı
    /// kontrolden geçmeden yeniden kullanılmaz.
    private func isValidStagedApp(_ app: URL, release: AppRelease, team: String) -> Bool {
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let version = (info["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init),
              version == release.version,
              info["CFBundleIdentifier"] as? String == bundleIdentifier
        else { return false }
        return signatures.isSignedByDeveloperID(app, team: team)
    }

    private func expectedChecksum(of package: AppReleaseAsset, in checksums: AppReleaseAsset) async throws -> String {
        let data = try await fetch(checksums.downloadURL)
        let text = String(decoding: data, as: UTF8.self)
        guard let hash = SHA256Sums.parse(text)[package.name] else {
            throw Self.failure("\(checksums.name) has no entry for \(package.name)")
        }
        return hash
    }

    private func fetch(_ url: URL) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request(url))
        } catch {
            throw Self.failure(error.localizedDescription)
        }
        try Self.requireOK(response, url: url)
        return data
    }

    private func download(_ asset: AppReleaseAsset, into directory: URL) async throws -> URL {
        let (temporary, response): (URL, URLResponse)
        do {
            (temporary, response) = try await session.download(for: request(asset.downloadURL))
        } catch {
            throw Self.failure(error.localizedDescription)
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Self.requireOK(response, url: asset.downloadURL)
        let destination = directory.appendingPathComponent(asset.name)
        do {
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch {
            throw Self.failure("could not save \(asset.name): \(error.localizedDescription)")
        }
        return destination
    }

    private func extract(_ zip: URL, into directory: URL) async throws {
        let output = await runner.run(
            "/usr/bin/ditto",
            arguments: ["-x", "-k", zip.path, directory.path],
            timeout: Self.processTimeout
        )
        guard let output, output.exitCode == 0 else {
            throw Self.failure("could not unpack \(zip.lastPathComponent): \(output?.stderr ?? "timed out")")
        }
    }

    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = Self.downloadTimeout
        return request
    }

    // MARK: - Kurulum

    /// Hata kullanıcıya iki yoldan ulaşır: fırlatılır (Restart Now kapanmadan
    /// önce gösterir) ve `install-failed`'a yazılır (Install on Quit'te uygulama
    /// zaten kapanıyordur — bir sonraki açılış okur).
    public func scheduleInstall(_ update: StagedAppUpdate, relaunch: Bool) async throws {
        do {
            try await registerAgent(for: update, relaunch: relaunch)
        } catch {
            try? Data(error.localizedDescription.utf8).write(to: failureURL, options: .atomic)
            throw error
        }
    }

    private func registerAgent(for update: StagedAppUpdate, relaunch: Bool) async throws {
        guard let team else { throw Self.failure("this copy of Lumi can't update itself") }
        let files = FileManager.default
        do {
            try files.createDirectory(at: root, withIntermediateDirectories: true)
            try Data(AppUpdateInstallScript.source.utf8).write(to: scriptURL, options: .atomic)
            try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
            let arguments = [
                String(processID), update.appPath, bundleURL.path, relaunch ? "1" : "0",
                AppUpdateInstallScript.label, plistURL.path, stagingDir.path, failureURL.path,
                CodeSignatureVerifier.developerIDRequirement(team: team),
            ]
            try AppUpdateInstallScript.plist(script: scriptURL.path, arguments: arguments, logPath: logURL.path)
                .write(to: plistURL, options: .atomic)
        } catch {
            throw Self.failure("could not write the installer: \(error.localizedDescription)")
        }

        let domain = "gui/\(userID)"
        // Önceki yarım kalmış bir agent varsa yeni kayıt "already loaded" ile reddedilir.
        _ = await runner.run(
            "/bin/launchctl",
            arguments: ["bootout", "\(domain)/\(AppUpdateInstallScript.label)"],
            timeout: Self.launchctlTimeout
        )
        let output = await runner.run(
            "/bin/launchctl",
            arguments: ["bootstrap", domain, plistURL.path],
            timeout: Self.launchctlTimeout
        )
        guard let output, output.exitCode == 0 else {
            try? files.removeItem(at: plistURL)
            let detail = output?.stderr.trimmingCharacters(in: .whitespacesAndNewlines) ?? "timed out"
            throw Self.failure("could not register the installer (launchctl: \(detail))")
        }
    }

    public func consumeInstallFailure() async -> String? {
        guard let data = try? Data(contentsOf: failureURL) else { return nil }
        try? FileManager.default.removeItem(at: failureURL)
        let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? nil : message
    }

    // MARK: - Yardımcılar

    static func sha256(of file: URL) throws -> String {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: file)
        } catch {
            throw failure("could not read \(file.lastPathComponent): \(error.localizedDescription)")
        }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func requireOK(_ response: URLResponse, url: URL) throws {
        guard let http = response as? HTTPURLResponse else { throw failure("unexpected response") }
        guard http.statusCode == 200 else {
            throw failure("HTTP \(http.statusCode) for \(url.lastPathComponent)")
        }
    }

    private static func failure(_ detail: String) -> LumiError {
        .updateInstallFailed(detail: detail)
    }
}

/// `shasum -a 256` / `sha256sum` çıktısı: `<hex>  <dosya>` (ikili modda `*dosya`).
enum SHA256Sums {
    static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2 else { continue }
            let hash = parts[0].lowercased()
            guard hash.count == 64, hash.allSatisfy(\.isHexDigit) else { continue }
            var name = parts[1].trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("*") { name.removeFirst() }
            result[name] = hash
        }
        return result
    }
}
