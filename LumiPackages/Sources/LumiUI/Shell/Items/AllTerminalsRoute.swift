import LumiKit

/// All Terminals route'unun görünen kimliği (karar 103) — panel satırı, route
/// descriptor'ı ve toolbar başlığı aynı adı/ikonu buradan okur.
public enum AllTerminalsRoute {
    public static let title = "All Terminals"
    public static let icon = "rectangle.3.group"
    public static var route: WorkspaceRoute { .content(.allTerminals) }
}
