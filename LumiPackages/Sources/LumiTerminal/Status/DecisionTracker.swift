/// "Karar bekliyor" sinyalini taşıyan saf izleyici (status makinesinden ayrı —
/// 6 durumlu spec'e dokunmaz). Claude bir izin/onay promptunda asılı kaldığında
/// true olur; çalışmaya dönünce temizlenir. Prompt kuyruğu bunu görüp duraklar:
/// "bekliyor" ile "karar bekliyor" karışırsa kuyruk araya yanlış prompt sokar.
///
/// io queue'ya confine edilerek kullanılır; kendi senkronizasyonu yoktur
/// ([[StatusStateMachine]] ile aynı sözleşme).
final class DecisionTracker {
    private(set) var isAwaitingDecision = false

    /// Yalnız gerçek değişimde tetiklenir (no-op'lar yayılmaz).
    var onChange: ((Bool) -> Void)?

    func onPermissionRequest() {
        set(true)
    }

    /// Çalışma yeniden başladı → izin promptu cevaplandı/kapandı.
    func onWorking() {
        set(false)
    }

    func reset() {
        set(false)
    }

    private func set(_ value: Bool) {
        guard value != isAwaitingDecision else { return }
        isAwaitingDecision = value
        onChange?(value)
    }
}
