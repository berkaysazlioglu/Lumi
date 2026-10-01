import Foundation
import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiServices

/// Karar 56 — hesap ekleme, seçme ve yüzeye materialize etme.
///
/// Gerçek keychain ve gerçek `claude` binary'si yerine fake'ler kullanılır;
/// dosya tarafı geçici bir ev dizinine yazar.
final class ClaudeAccountServiceTests: XCTestCase {
    private var root: URL!
    private var home: URL!
    private var keychain: FakeKeychain!
    private var runner: FakeEnvironmentProcessRunner!
    private var locator: FakeBinaryLocator!
    private var config: FakeConfigService!
    private let user = "tester"

    override func setUp() async throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumi-accounts-\(UUID().uuidString)")
        home = root.appendingPathComponent("home")
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: home.appendingPathComponent(".claude.json"))
        keychain = FakeKeychain()
        runner = FakeEnvironmentProcessRunner()
        locator = FakeBinaryLocator(paths: ["claude": "/usr/local/bin/claude"])
        config = FakeConfigService()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Kurulum yardımcıları

    private var runtimePaths: ClaudeRuntimeAuthPaths {
        ClaudeAuthLocations.runtime(
            homeDirectory: home.path,
            environment: [:],
            fileExists: { FileManager.default.fileExists(atPath: $0) }
        )
    }

    private func makeService() -> ClaudeAccountService {
        ClaudeAccountService(
            config: config,
            store: ClaudeManagedAuthStore(
                keychain: keychain, root: root.appendingPathComponent("claude-accounts")
            ),
            surface: ClaudeAuthSurface(keychain: keychain, paths: runtimePaths, user: user),
            login: ClaudeLoginSession(
                runner: runner, locator: locator, keychain: keychain, user: user,
                temporaryDirectory: root.appendingPathComponent("tmp")
            ),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }

    private static func credentials(accessToken: String) -> String {
        #"{"claudeAiOauth":{"accessToken":"\#(accessToken)","refreshToken":"r"}}"#
    }

    /// `claude auth login`'in yan etkisini taklit eder: geçici config dizinine
    /// ait keychain kaydını ve `.claude.json`'ı yazar.
    private func scriptLogin(email: String, accessToken: String) async {
        await runner.setResult(
            ProcessOutput(exitCode: 0, stdout: #"{"email":"\#(email)"}"#, stderr: ""),
            for: "auth status"
        )
        let keychain = keychain!
        let user = user
        await runner.setSideEffect(for: "auth login") { invocation in
            guard let configDir = invocation.configDir else { return }
            try? await keychain.setPassword(
                Self.credentials(accessToken: accessToken),
                service: ClaudeAuthLocations.scopedKeychainService(configDir: configDir),
                account: user
            )
            let object = ["oauthAccount": ["emailAddress": email]]
            try? JSONSerialization.data(withJSONObject: object).write(
                to: URL(fileURLWithPath: configDir).appendingPathComponent(".claude.json")
            )
        }
    }

    private func addAccount(email: String, accessToken: String) async throws -> ClaudeAccount {
        await scriptLogin(email: email, accessToken: accessToken)
        let snapshot = try await makeService().addAccount()
        return try XCTUnwrap(snapshot.accounts.first { $0.email == email })
    }

    // MARK: - Ekleme

    func testAddAccountRunsLoginInAnIsolatedConfigDirAndStoresCredentials() async throws {
        let account = try await addAccount(email: "dev@example.com", accessToken: "token-1")

        let invocations = await runner.invocations
        let login = try XCTUnwrap(invocations.first)
        XCTAssertEqual(login.commandLine, "/usr/local/bin/claude auth login --claudeai")
        let configDir = try XCTUnwrap(login.configDir)
        XCTAssertNotEqual(configDir, home.appendingPathComponent(".claude").path, "login kullanıcının dizinine dokunmamalı")
        XCTAssertFalse(FileManager.default.fileExists(atPath: configDir), "geçici dizin temizlenmeli")

        let stored = await keychain.stored(
            service: ClaudeAuthLocations.managedKeychainService, account: account.id
        )
        XCTAssertEqual(stored, Self.credentials(accessToken: "token-1"))
        let emails = await config.config().claudeAccounts.map(\.email)
        XCTAssertEqual(emails, ["dev@example.com"])
    }

    /// Hesap eklemek AKTİF hesabı değiştirmez — kullanıcı switch'i ayrıca yapar.
    func testAddAccountLeavesTheSelectionAndSurfaceUntouched() async throws {
        await keychain.seed(
            Self.credentials(accessToken: "system"),
            service: ClaudeAuthLocations.legacyKeychainService, account: user
        )
        _ = try await addAccount(email: "dev@example.com", accessToken: "token-1")

        let selection = await config.config().claudeAccountSelection
        XCTAssertEqual(selection, .systemDefault)
        let live = await keychain.stored(
            service: ClaudeAuthLocations.legacyKeychainService, account: user
        )
        XCTAssertEqual(live, Self.credentials(accessToken: "system"), "kullanıcının oturumu korunmalı")
    }

    func testAddingTheSameIdentityTwiceIsRejected() async throws {
        _ = try await addAccount(email: "dev@example.com", accessToken: "token-1")
        await scriptLogin(email: "DEV@example.com", accessToken: "token-2")

        do {
            _ = try await makeService().addAccount()
            XCTFail("aynı kimlik ikinci kez eklenmemeli")
        } catch {
            let count = await config.config().claudeAccounts.count
            XCTAssertEqual(count, 1)
        }
    }

    func testFailedLoginPersistsNothing() async throws {
        await runner.setResult(
            ProcessOutput(exitCode: 1, stdout: "", stderr: "sign-in denied"), for: "auth login"
        )
        do {
            _ = try await makeService().addAccount()
            XCTFail("login hatası yutulmamalı")
        } catch {
            let accounts = await config.config().claudeAccounts
            let writes = await keychain.writes
            XCTAssertEqual(accounts, [])
            XCTAssertEqual(writes, [])
        }
    }

    func testMissingClaudeBinaryIsReportedAsCliNotFound() async throws {
        await locator.setPath(nil, for: "claude")
        do {
            _ = try await makeService().addAccount()
            XCTFail("binary yokken login denenmemeli")
        } catch {
            XCTAssertEqual(error as? LumiError, .cliNotFound(binary: "claude"))
        }
    }

    // MARK: - Seçim

    func testSelectingAnAccountWritesEveryChannelOfTheActiveSurface() async throws {
        let account = try await addAccount(email: "dev@example.com", accessToken: "token-1")
        _ = try await makeService().select(.account(account.id))

        let expected = Self.credentials(accessToken: "token-1")
        let scoped = ClaudeAuthLocations.scopedKeychainService(configDir: runtimePaths.configDir)
        let scopedValue = await keychain.stored(service: scoped, account: user)
        let legacyValue = await keychain.stored(
            service: ClaudeAuthLocations.legacyKeychainService, account: user
        )
        XCTAssertEqual(scopedValue, expected)
        XCTAssertEqual(legacyValue, expected, "eski CLI sürümleri düz servisi okur")
        let file = try String(contentsOfFile: runtimePaths.credentialsFile, encoding: .utf8)
        XCTAssertEqual(file, expected)

        let configData = try Data(contentsOf: URL(fileURLWithPath: runtimePaths.configFile))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: configData) as? [String: Any])
        let oauth = try XCTUnwrap(object["oauthAccount"] as? [String: Any])
        let selection = await config.config().claudeAccountSelection
        XCTAssertEqual(oauth["emailAddress"] as? String, "dev@example.com")
        XCTAssertEqual(selection, .account(account.id))
    }

    func testFirstSwitchCapturesTheSystemDefaultAndSwitchingBackRestoresIt() async throws {
        let systemCredentials = Self.credentials(accessToken: "system")
        await keychain.seed(
            systemCredentials, service: ClaudeAuthLocations.legacyKeychainService, account: user
        )
        let account = try await addAccount(email: "dev@example.com", accessToken: "token-1")

        _ = try await makeService().select(.account(account.id))
        let switched = await keychain.stored(
            service: ClaudeAuthLocations.legacyKeychainService, account: user
        )
        XCTAssertNotEqual(switched, systemCredentials)

        _ = try await makeService().select(.systemDefault)
        let restored = await keychain.stored(
            service: ClaudeAuthLocations.legacyKeychainService, account: user
        )
        let selection = await config.config().claudeAccountSelection
        XCTAssertEqual(restored, systemCredentials, "kullanıcının kendi oturumu geri gelmeli")
        XCTAssertEqual(selection, .systemDefault)
    }

    /// `System default` satırı Mac'teki login'in e-postasını gösterir —
    /// yönetilen bir hesaba geçildikten sonra da (yakalanan snapshot'tan).
    func testSystemDefaultEmailComesFromTheSurfaceAndThenFromTheSnapshot() async throws {
        await keychain.seed(
            Self.credentials(accessToken: "system"),
            service: ClaudeAuthLocations.legacyKeychainService, account: user
        )
        let object = ["oauthAccount": ["emailAddress": "me@home.com"]]
        try JSONSerialization.data(withJSONObject: object)
            .write(to: home.appendingPathComponent(".claude.json"))
        let account = try await addAccount(email: "dev@example.com", accessToken: "token-1")

        let initial = await makeService().accounts()
        XCTAssertEqual(initial.systemDefaultEmail, "me@home.com")

        let switched = try await makeService().select(.account(account.id))
        XCTAssertEqual(switched.systemDefaultEmail, "me@home.com", "yüzey artık yönetilen hesabın")
    }

    /// İkinci bir geçişte yakalanan snapshot ÜZERİNE yazılmamalı: yoksa
    /// yönetilen bir hesabın token'ı "sistem varsayılanı" sanılırdı.
    func testSystemDefaultSnapshotIsCapturedOnlyOnce() async throws {
        let systemCredentials = Self.credentials(accessToken: "system")
        await keychain.seed(
            systemCredentials, service: ClaudeAuthLocations.legacyKeychainService, account: user
        )
        let first = try await addAccount(email: "one@example.com", accessToken: "token-1")
        let second = try await addAccount(email: "two@example.com", accessToken: "token-2")

        let service = makeService()
        _ = try await service.select(.account(first.id))
        _ = try await service.select(.account(second.id))
        _ = try await service.select(.systemDefault)

        let restored = await keychain.stored(
            service: ClaudeAuthLocations.legacyKeychainService, account: user
        )
        XCTAssertEqual(restored, systemCredentials)
    }

    func testSwitchingToAnAccountWithoutStoredCredentialsFails() async throws {
        let account = try await addAccount(email: "dev@example.com", accessToken: "token-1")
        try await keychain.deletePassword(
            service: ClaudeAuthLocations.managedKeychainService, account: account.id
        )
        do {
            _ = try await makeService().select(.account(account.id))
            XCTFail("kimlik bilgisi olmayan hesaba geçilmemeli")
        } catch {
            let selection = await config.config().claudeAccountSelection
            XCTAssertEqual(selection, .systemDefault)
        }
    }

    // MARK: - Geri okuma (CLI'ın tazelediği token'lar)

    func testSwitchingAwayPersistsTokensTheCliRefreshedOnTheSurface() async throws {
        let first = try await addAccount(email: "one@example.com", accessToken: "token-1")
        let second = try await addAccount(email: "two@example.com", accessToken: "token-2")
        let service = makeService()
        _ = try await service.select(.account(first.id))

        // CLI token'ı tazeledi (yüzeydeki değer değişti).
        let refreshed = Self.credentials(accessToken: "token-1-refreshed")
        let scoped = ClaudeAuthLocations.scopedKeychainService(configDir: runtimePaths.configDir)
        await keychain.seed(refreshed, service: scoped, account: user)

        _ = try await service.select(.account(second.id))

        let persisted = await keychain.stored(
            service: ClaudeAuthLocations.managedKeychainService, account: first.id
        )
        XCTAssertEqual(persisted, refreshed, "tazelenen token hesabın deposuna geri yazılmalı")
    }

    /// Kullanıcı terminalde elle BAŞKA bir hesaba girdiyse yüzeydeki token
    /// bizim hesabımıza ait değildir — üzerine yazılmamalı.
    func testReadBackIsSkippedWhenTheSurfaceBelongsToAnotherIdentity() async throws {
        let first = try await addAccount(email: "one@example.com", accessToken: "token-1")
        let second = try await addAccount(email: "two@example.com", accessToken: "token-2")
        let service = makeService()
        _ = try await service.select(.account(first.id))

        let foreign = Self.credentials(accessToken: "someone-else")
        let scoped = ClaudeAuthLocations.scopedKeychainService(configDir: runtimePaths.configDir)
        await keychain.seed(foreign, service: scoped, account: user)
        let object = ["oauthAccount": ["emailAddress": "stranger@example.com"]]
        try JSONSerialization.data(withJSONObject: object)
            .write(to: URL(fileURLWithPath: runtimePaths.configFile))

        _ = try await service.select(.account(second.id))

        let persisted = await keychain.stored(
            service: ClaudeAuthLocations.managedKeychainService, account: first.id
        )
        XCTAssertEqual(
            persisted, Self.credentials(accessToken: "token-1"),
            "yabancı token yönetilen depoya sızmamalı"
        )
    }

    // MARK: - Silme

    func testRemovingTheActiveAccountRestoresTheSystemDefaultAndClearsStorage() async throws {
        let systemCredentials = Self.credentials(accessToken: "system")
        await keychain.seed(
            systemCredentials, service: ClaudeAuthLocations.legacyKeychainService, account: user
        )
        let account = try await addAccount(email: "dev@example.com", accessToken: "token-1")
        let service = makeService()
        _ = try await service.select(.account(account.id))

        let snapshot = try await service.removeAccount(accountID: account.id)

        let managed = await keychain.stored(
            service: ClaudeAuthLocations.managedKeychainService, account: account.id
        )
        let restored = await keychain.stored(
            service: ClaudeAuthLocations.legacyKeychainService, account: user
        )
        XCTAssertEqual(snapshot.accounts, [])
        XCTAssertEqual(snapshot.selection, .systemDefault)
        XCTAssertNil(managed)
        XCTAssertEqual(restored, systemCredentials)
    }

    // MARK: - Açılış senkronizasyonu

    func testSyncActiveSelectionRematerializesTheSelectedAccount() async throws {
        let account = try await addAccount(email: "dev@example.com", accessToken: "token-1")
        let service = makeService()
        _ = try await service.select(.account(account.id))

        // Başka bir araç yüzeyi ezdi.
        let scoped = ClaudeAuthLocations.scopedKeychainService(configDir: runtimePaths.configDir)
        await keychain.seed("{}", service: scoped, account: user)

        await service.syncActiveSelection()

        let rematerialized = await keychain.stored(service: scoped, account: user)
        XCTAssertEqual(rematerialized, Self.credentials(accessToken: "token-1"))
    }
}
