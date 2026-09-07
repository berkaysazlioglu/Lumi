import Foundation
import LumiKit
import Observation

/// Commit/checkin mesajı üretim akışı (karar 46): Git ve Plastic composer'ları
/// aynı asistanı kullanır. Store yalnız "uçuşta mı?" durumunu ve hata
/// raporlamasını taşır; isteğin içeriğini VCS store'u kurar
/// (`GitStore.commitMessageRequest` / `PlasticStore.checkinMessageRequest`),
/// sonucu `ShellContext` koordinasyon intent'i mesaj alanına yazar.
@Observable
@MainActor
public final class CommitMessageAssistant {
    public private(set) var generatingPaths: Set<String> = []

    @ObservationIgnored private let generator: any CommitMessageGenerating
    @ObservationIgnored private let toasts: ToastStore

    public init(generator: any CommitMessageGenerating, toasts: ToastStore) {
        self.generator = generator
        self.toasts = toasts
    }

    public func isGenerating(_ repoPath: String) -> Bool {
        generatingPaths.contains(repoPath)
    }

    /// Aynı repo için ikinci istek uçuştaki bitmeden başlamaz (nil döner).
    /// Boş seçim görünür hatadır — düğme zaten kapalıdır, klavye yolu için guard.
    public func generate(_ repoPath: String, request: CommitMessageRequest) async -> String? {
        guard !generatingPaths.contains(repoPath) else { return nil }
        generatingPaths.insert(repoPath)
        defer { generatingPaths.remove(repoPath) }

        var message: String?
        await toasts.reporting {
            guard !request.changes.isEmpty else {
                throw LumiError.commitMessageGenerationFailed(detail: "No files selected")
            }
            message = try await self.generator.generate(request)
        }
        return message
    }
}
