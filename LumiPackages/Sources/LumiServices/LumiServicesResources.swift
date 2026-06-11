import Foundation

/// Bundle.module modül-içi olduğundan seed dizinleri composition root'a
/// buradan açılır (design/00: default'lar Bundle resource'u).
public enum LumiServicesResources {
    public static var defaultPersonasDirectory: URL? {
        Bundle.module.resourceURL?.appendingPathComponent("default-personas")
    }

    public static var defaultActionsDirectory: URL? {
        Bundle.module.resourceURL?.appendingPathComponent("default-actions")
    }
}
