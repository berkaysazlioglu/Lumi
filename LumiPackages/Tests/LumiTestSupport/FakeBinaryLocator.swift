import Foundation
import LumiKit

/// `BinaryLocating` test ikamesi: ad → path eşlemesi; eşleşmeyen ad "PATH'te yok"
/// demektir. Gerçek dosya sistemine bakmaz (dev makinesindeki kurulu CLI'lar
/// testleri etkilemesin).
public actor FakeBinaryLocator: BinaryLocating {
    private var paths: [String: String]
    public private(set) var lookups: [String] = []

    public init(paths: [String: String] = [:]) {
        self.paths = paths
    }

    public func setPath(_ path: String?, for name: String) {
        paths[name] = path
    }

    public func locate(_ name: String, timeout: TimeInterval) async -> String? {
        lookups.append(name)
        return paths[name]
    }
}
