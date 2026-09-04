import AppKit
import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiTerminal

/// TerminalViewRegistry reparenting davranışı (grid round-trip'te boş kart bug'ı).
@MainActor
final class TerminalViewRegistryTests: XCTestCase {
    private func makeRegistry(
        id: TerminalID
    ) -> (TerminalViewRegistry, NSView, () -> [Bool]) {
        let registry = TerminalViewRegistry()
        let view = NSView()
        var visibilityLog: [Bool] = []
        registry.register(view: view, for: id) { visibilityLog.append($0) }
        return (registry, view, { visibilityLog })
    }

    /// detachView kaldırmayı bir sonraki runloop'a erteler (reparenting yarış
    /// koruması); ertelenen bloğun çalışmasını beklemek için main queue'yu pompala.
    private func pumpMainRunLoop() {
        let done = expectation(description: "main runloop drained")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 1)
    }

    func testReattachThenStaleDetachKeepsViewInNewContainer() {
        // SwiftUI reparenting yarışı: yeni host attach eder, ARDINDAN eski host'un
        // dismantle'ı (bayat) gelir. Bayat detach canlı view'ı sökmemeli.
        let id = TerminalID()
        let (registry, view, _) = makeRegistry(id: id)
        let oldContainer = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let newContainer = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))

        registry.attachView(for: id, into: oldContainer)
        XCTAssertTrue(view.superview === oldContainer)

        // Grid rebuild: önce yeni container'a taşı
        registry.attachView(for: id, into: newContainer)
        XCTAssertTrue(view.superview === newContainer)

        // Eski host'un bayat dismantle'ı — view'ı yeni container'dan SÖKMEMELİ
        registry.detachView(for: id, from: oldContainer)
        XCTAssertTrue(view.superview === newContainer, "bayat detach canlı view'ı söktü")
    }

    func testDetachFromCurrentContainerRemovesView() {
        // Kart gerçekten kapanırken (doğru container'dan detach) view sökülmeli.
        let id = TerminalID()
        let (registry, view, _) = makeRegistry(id: id)
        let container = NSView()

        registry.attachView(for: id, into: container)
        XCTAssertTrue(view.superview === container)

        registry.detachView(for: id, from: container)
        pumpMainRunLoop() // detach ertelenmiş
        XCTAssertNil(view.superview)
    }

    func testDeferredDetachSkipsRemovalWhenReattachedBeforeRunLoop() {
        // Maximize↔grid round-trip yarışı: detach (artık ertelenmiş) çağrıldıktan
        // SONRA, runloop dönmeden view yeni container'a taşınır. Ertelenen detach
        // canlı view'ı öksüz BIRAKMAMALI (öksüz kalırsa kart boş + resize'a sağır).
        let id = TerminalID()
        let (registry, view, _) = makeRegistry(id: id)
        let oldContainer = NSView()
        let newContainer = NSView()

        registry.attachView(for: id, into: oldContainer)
        registry.detachView(for: id, from: oldContainer) // ertelenir
        registry.attachView(for: id, into: newContainer) // runloop dönmeden taşı
        pumpMainRunLoop()

        XCTAssertTrue(view.superview === newContainer, "ertelenmiş detach canlı view'ı öksüz bıraktı")
    }

    func testReattachMarksViewForRedraw() {
        // Re-attach sonrası buffer'dan tam çizim için needsDisplay set edilmeli
        // (grid round-trip'te "sadece input satırı geliyor" bug'ının ikinci yarısı).
        // Bare NSView window'suz needsDisplay'i tutmaz; setter'ı spy ile yakala.
        let id = TerminalID()
        let registry = TerminalViewRegistry()
        let spy = RedrawSpyView()
        registry.register(view: spy, for: id) { _ in }
        let container = NSView()

        registry.attachView(for: id, into: container)
        XCTAssertTrue(spy.redrawRequested)
    }

    func testAttachIntoZeroSizedContainerPreservesViewFrame() {
        // Tab değişimi: yeni host makeNSView anında 0×0 — SwiftTerm sıfıra
        // küçültülmemeli (emülatörü gereksiz resize eder, repaint no-op'laşır).
        let id = TerminalID()
        let (registry, view, _) = makeRegistry(id: id)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 480)
        let container = NSView() // bounds .zero

        registry.attachView(for: id, into: container)

        XCTAssertTrue(view.superview === container)
        XCTAssertEqual(view.frame.size, NSSize(width: 800, height: 480))
    }

    // MARK: - Yerleşim otoritesi (refactor 4.5)

    /// Reassert (host'un her layout'ta yaptığı `attachView`) artık frame'e DOKUNMAZ:
    /// yerleşimin tek otoritesi `TerminalHostContainer.pinTerminalView` →
    /// `TerminalGridFit.fit`. Registry yalnız reparent + görünürlük/çizim sinyali verir.
    func testReassertDoesNotTouchFrame() {
        let id = TerminalID()
        let (registry, view, _) = makeRegistry(id: id)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 480)
        let container = NSView()

        registry.attachView(for: id, into: container) // 0×0 — frame korunur
        container.setFrameSize(NSSize(width: 400, height: 300))
        registry.attachView(for: id, into: container) // reassert: gerçek boyut

        XCTAssertEqual(
            view.frame.size, NSSize(width: 800, height: 480),
            "registry frame'i oturttu — fit otoritesi host'ta olmalı"
        )
    }

    /// 4.5'in asıl kazancı: `TerminalHostContainer.layout()/setFrameSize` her AppKit
    /// layout geçişinde reassert eder. Eskiden frame deltası `onRedraw` →
    /// `redrawFromBuffer` → `updateFullScreen()` (tüm hücreler dirty) tetikliyordu;
    /// pencere resize/animasyonunda bu, N terminal × frame tam çizim demekti.
    /// Artık tam çizim yalnız GERÇEK attach olayına bağlı.
    func testFrameChangesAfterAttachDoNotTriggerFullRedraw() {
        // Arrange — tam çizim sinyali artık görünürlük kanalından akar (Faz 4B):
        // `onVisibilityChange(true)` = foreground yüzeyi + buffer'dan tam çizim.
        let id = TerminalID()
        let registry = TerminalViewRegistry()
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 480))
        var redrawCount = 0
        registry.register(view: view, for: id) { visible in
            if visible { redrawCount += 1 }
        }
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))

        // Act — attach + 20 layout geçişi (resize animasyonu benzetimi)
        registry.attachView(for: id, into: container)
        for step in 1 ... 20 {
            container.setFrameSize(NSSize(width: 400 + step, height: 300 + step))
            registry.attachView(for: id, into: container) // host reassert'i
        }

        // Assert
        XCTAssertLessThanOrEqual(
            redrawCount, 1,
            "frame deltası hâlâ tam çizim tetikliyor (\(redrawCount) kez)"
        )
    }

    /// Gerçek attach olayı (reparent) buffer'dan tam çizim ister — 0×0 host'a
    /// bağlanıp boyut sonradan otursa bile `updateFullScreen`'in dirty işaretlemesi
    /// model tarafında kalıcıdır (boş kart onarımı).
    func testGenuineAttachRequestsRedrawOnce() {
        let id = TerminalID()
        let registry = TerminalViewRegistry()
        let view = NSView()
        var redrawCount = 0
        registry.register(view: view, for: id) { visible in
            if visible { redrawCount += 1 }
        }
        let first = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let second = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))

        registry.attachView(for: id, into: first)
        XCTAssertEqual(redrawCount, 1)

        registry.attachView(for: id, into: first) // reassert — yeni olay değil
        XCTAssertEqual(redrawCount, 1)

        registry.attachView(for: id, into: second) // gerçek reparent
        XCTAssertEqual(redrawCount, 2)
    }

    /// Fullscreen onarımı fit'i kendi yapmaz; host'tan yeni bir layout geçişi ister.
    func testRefreshRequestsHostLayoutInsteadOfFitting() {
        let id = TerminalID()
        let (registry, view, _) = makeRegistry(id: id)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        registry.attachView(for: id, into: container)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 480) // bayat frame
        container.needsLayout = false

        registry.refreshAttachedViews()

        XCTAssertTrue(container.needsLayout, "onarım host layout'unu istemedi")
        XCTAssertEqual(
            view.frame.size, NSSize(width: 800, height: 480),
            "refresh frame'i kendi oturttu — fit otoritesi host'ta olmalı"
        )
    }

    func testVisibilityTogglesAcrossDetachReattach() {
        let id = TerminalID()
        let (registry, _, log) = makeRegistry(id: id)
        let container = NSView()

        // register → ilk visibility false (henüz bağlı değil)
        XCTAssertEqual(log(), [false])

        registry.attachView(for: id, into: container)
        XCTAssertEqual(log(), [false, true])

        registry.detachView(for: id, from: container)
        pumpMainRunLoop() // detach + visibility(false) ertelenmiş
        XCTAssertEqual(log(), [false, true, false])
    }

    // MARK: - Protokol yüzeyi (Faz 3.7)

    /// `refreshAttachedViews` artık `TerminalViewProviding` sözleşmesinin parçası:
    /// AppDelegate somut registry tipine inmeden fullscreen onarımını isteyebilir.
    func testRefreshAttachedViewsIsReachableThroughProtocol() {
        let id = TerminalID()
        let (registry, view, log) = makeRegistry(id: id)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        registry.attachView(for: id, into: container)
        XCTAssertEqual(log(), [false, true])

        let provider: any TerminalViewProviding = registry
        provider.refreshAttachedViews()

        XCTAssertTrue(view.superview === container)
        XCTAssertEqual(log(), [false, true, true], "onarım görünürlük sinyalini yeniler")
    }

    // MARK: - Toplu ayırma (Faz 4.4)

    /// Route değişiminde (Tasks'a geçiş) SwiftUI dismantle sırasına güvenmek
    /// yerine tek açık çağrı: bağlı her view sökülür ve her biri için
    /// `onVisibilityChange(false)` akar (gizli-terminal politikası).
    func testDetachAllDetachesEveryAttachedView() {
        let registry = TerminalViewRegistry()
        var logs: [TerminalID: [Bool]] = [:]
        var views: [TerminalID: NSView] = [:]
        var ids: [TerminalID] = []
        for _ in 0 ..< 3 {
            let id = TerminalID()
            ids.append(id)
            let view = NSView()
            views[id] = view
            registry.register(view: view, for: id) { logs[id, default: []].append($0) }
            registry.attachView(for: id, into: NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 120)))
        }
        XCTAssertEqual(ids.filter { registry.isAttached($0) }.count, 3)

        registry.detachAll()

        for id in ids {
            XCTAssertFalse(registry.isAttached(id), "detachAll bağlı view bıraktı")
            XCTAssertNil(views[id]?.superview)
            XCTAssertEqual(logs[id], [false, true, false], "görünürlük sinyali akmadı")
        }
    }

    func testIsAttachedTracksAttachAndDetach() {
        let id = TerminalID()
        let (registry, _, _) = makeRegistry(id: id)
        let container = NSView()
        XCTAssertFalse(registry.isAttached(id), "register tek başına bağlamaz")

        registry.attachView(for: id, into: container)
        XCTAssertTrue(registry.isAttached(id))

        registry.detachView(for: id, from: container)
        pumpMainRunLoop()
        XCTAssertFalse(registry.isAttached(id))
    }

    func testIsAttachedIsFalseForUnknownTerminal() {
        let registry = TerminalViewRegistry()
        XCTAssertFalse(registry.isAttached(TerminalID()))
    }

    func testDetachAllIsIdempotent() {
        let id = TerminalID()
        let (registry, _, log) = makeRegistry(id: id)
        registry.attachView(for: id, into: NSView())

        registry.detachAll()
        registry.detachAll()

        XCTAssertEqual(log(), [false, true, false], "ikinci detachAll bayat sinyal üretti")
    }

    func testFakeProviderSupportsDetachAllAndIsAttached() {
        let fake = FakeTerminalViewProvider()
        let first = TerminalID()
        let second = TerminalID()
        let container = NSView()
        let provider: any TerminalViewProviding = fake
        provider.attachView(for: first, into: container)
        provider.attachView(for: second, into: container)
        XCTAssertTrue(provider.isAttached(first))
        XCTAssertTrue(provider.isAttached(second))

        provider.detachAll()

        XCTAssertFalse(provider.isAttached(first))
        XCTAssertFalse(provider.isAttached(second))
        XCTAssertEqual(fake.detachAllCount, 1)
        XCTAssertEqual(fake.attachedIDs, [])
    }

    func testFakeProviderRecordsRefreshCalls() {
        let fake = FakeTerminalViewProvider()
        XCTAssertEqual(fake.refreshCallCount, 0)

        let provider: any TerminalViewProviding = fake
        provider.refreshAttachedViews()
        provider.refreshAttachedViews()

        XCTAssertEqual(fake.refreshCallCount, 2)
    }
}

/// needsDisplay set'ini yakalayan spy (bare NSView window'suz değeri tutmaz).
private final class RedrawSpyView: NSView {
    var redrawRequested = false
    override var needsDisplay: Bool {
        willSet { if newValue { redrawRequested = true } }
    }
}
