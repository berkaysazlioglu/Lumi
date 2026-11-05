import Testing
import Foundation
@testable import LumiRemote
import LumiKit
import LumiTestSupport

// Hub şifresi, Keychain kayıtları, deneme kilidi ve izleyici sayımı (docs/design/08).

struct HubPasswordHashTests {
    @Test func verifiesOnlyTheOriginalPassword() throws {
        let record = try #require(HubPasswordHash.make(password: "doğru şifre", iterations: 1_000))
        #expect(record.hasPrefix("pbkdf2-sha256$1000$"))
        #expect(!record.contains("doğru"))
        #expect(HubPasswordHash.verify(password: "doğru şifre", record: record))
        #expect(!HubPasswordHash.verify(password: "doğru şifr", record: record))
        #expect(!HubPasswordHash.verify(password: "", record: record))
    }

    @Test func saltMakesEveryRecordDifferent() throws {
        let a = try #require(HubPasswordHash.make(password: "x", iterations: 1_000))
        let b = try #require(HubPasswordHash.make(password: "x", iterations: 1_000))
        #expect(a != b)
    }

    @Test(arguments: ["", "pbkdf2-sha256$1000$abc", "md5$1$AA==$AA==", "pbkdf2-sha256$0$AA==$AA==", "pbkdf2-sha256$x$AA==$AA=="])
    func malformedRecordNeverVerifies(record: String) {
        #expect(!HubPasswordHash.verify(password: "x", record: record))
    }
}

struct RemoteHubSecretsTests {
    @Test func storesOnlyTheHashAndRejectsEmptyPassword() async throws {
        let keychain = FakeKeychain()
        let secrets = RemoteHubSecrets(keychain: keychain)
        await #expect(throws: RemoteHubError.emptyPassword) { try await secrets.setPassword("") }
        try await secrets.setPassword("gizli")
        let stored = try #require(await keychain.stored(service: RemoteHubSecrets.service, account: "password"))
        #expect(!stored.contains("gizli"))
        #expect(HubPasswordHash.verify(password: "gizli", record: stored))
        try await secrets.removePassword()
        #expect(await secrets.passwordRecord() == .missing)
    }

    @Test func hubKeyIsCreatedOnceAndReused() async throws {
        let secrets = RemoteHubSecrets(keychain: FakeKeychain())
        let first = try #require(await secrets.hubKey())
        #expect(first.count >= 16)
        #expect(await secrets.hubKey() == first)
    }
}

struct HubAttemptLimiterTests {
    @Test func locksAfterRepeatedFailuresAndUnlocksLater() {
        var limiter = HubAttemptLimiter()
        let start = Date(timeIntervalSince1970: 1_000)
        for i in 0..<HubAttemptLimiter.maxFailures {
            #expect(!limiter.isLocked("c", now: start))
            limiter.recordFailure("c", now: start.addingTimeInterval(Double(i)))
        }
        #expect(limiter.isLocked("c", now: start.addingTimeInterval(10)))
        #expect(!limiter.isLocked("other", now: start))
        #expect(!limiter.isLocked("c", now: start.addingTimeInterval(HubAttemptLimiter.lockout + 10)))
    }

    @Test func oldFailuresOutsideTheWindowDoNotCount() {
        var limiter = HubAttemptLimiter()
        let start = Date(timeIntervalSince1970: 1_000)
        for i in 0..<(HubAttemptLimiter.maxFailures - 1) {
            limiter.recordFailure("c", now: start.addingTimeInterval(Double(i)))
        }
        limiter.recordFailure("c", now: start.addingTimeInterval(HubAttemptLimiter.window + 10))
        #expect(!limiter.isLocked("c", now: start.addingTimeInterval(HubAttemptLimiter.window + 11)))
    }
}

struct RemoteSubscribersTests {
    private let id = TerminalID()

    @Test func modeClosesOnlyWhenItsLastWatcherLeaves() {
        var subs = RemoteSubscribers()
        #expect(subs.subscribe(id, subscriber: "a", mode: .terminal).isEmpty)
        #expect(subs.subscribe(id, subscriber: "b", mode: .terminal).isEmpty)
        #expect(subs.unsubscribe(id, subscriber: "a").isEmpty)
        #expect(subs.unsubscribe(id, subscriber: "b") == [.terminal])
        #expect(!subs.has(id, mode: .terminal))
        // Hiç abone olmamış izleyicinin çıkışı hiçbir şeyi kapatmaz.
        #expect(subs.unsubscribe(id, subscriber: "ghost").isEmpty)
    }

    @Test func switchingModeOrphansThePreviousModeOnlyIfNobodyElseUsesIt() {
        var subs = RemoteSubscribers()
        _ = subs.subscribe(id, subscriber: "phone", mode: .terminal)
        _ = subs.subscribe(id, subscriber: "hub:1", mode: .terminal)
        #expect(subs.subscribe(id, subscriber: "phone", mode: .chat).isEmpty)
        #expect(subs.has(id, mode: .terminal))
        #expect(subs.subscribe(id, subscriber: "hub:1", mode: .chat) == [.terminal])
    }

    @Test func removingAControllerReportsOrphanedTerminals() {
        var subs = RemoteSubscribers()
        let other = TerminalID()
        _ = subs.subscribe(id, subscriber: "hub:1", mode: .terminal)
        _ = subs.subscribe(other, subscriber: "hub:1", mode: .chat)
        _ = subs.subscribe(other, subscriber: "phone", mode: .chat)
        let orphaned = subs.removeSubscribers { $0 == "hub:1" }
        #expect(orphaned == [id: [.terminal]])
        #expect(subs.has(other, mode: .chat))
    }
}
