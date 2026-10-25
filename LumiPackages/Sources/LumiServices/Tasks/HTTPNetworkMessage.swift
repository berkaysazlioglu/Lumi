import Foundation

/// Ağ hatasının insan dilindeki karşılığı — Tasks ve Sessions istemcileri
/// paylaşır (uyuyan dyno, yanlış adres, sertifika…).
enum HTTPNetworkMessage {
    static func describe(_ error: any Error, timeout: TimeInterval) -> String {
        guard let urlError = error as? URLError else { return error.localizedDescription }
        switch urlError.code {
        case .timedOut: return "The request timed out after \(Int(timeout))s (a sleeping server can take a while to wake up)."
        case .cannotFindHost, .dnsLookupFailed: return "The host can't be found — check the address."
        case .cannotConnectToHost: return "Nothing is listening at this address — is the server running?"
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate:
            return "The HTTPS connection failed (certificate problem)."
        case .notConnectedToInternet: return "This Mac is offline."
        default: return urlError.localizedDescription
        }
    }
}
