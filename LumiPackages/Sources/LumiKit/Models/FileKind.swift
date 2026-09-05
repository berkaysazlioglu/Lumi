import Foundation

/// Explorer satırının ikon + renk sınıfı.
///
/// Sunumdan (SF Symbol adı, bundle PNG'si, renk token'ı) ayrık tutulur: burada
/// yalnız "bu dosya ne" sorusu yanıtlanır, "nasıl çizilir" LumiUI'nın işidir.
/// Böylece sınıflandırma saf ve test edilebilir kalır (`FileKindTests`).
public enum FileKind: Sendable, Equatable, CaseIterable {
    case folder
    case folderOpen
    case swift
    case csharp
    case typescript
    case javascript
    case json
    case yaml
    case markdown
    case text
    case shell
    case python
    case image
    case shader
    case unityScene
    case unityPrefab
    case unityScriptableObject
    case unityMaterial
    case unityMeta
    case config
    case lock
    case git
    case archive
    case font
    case audio
    case video
    case generic

    /// Dosya/klasör adından sınıfı çözer.
    ///
    /// Sıra bağlayıcıdır: klasör → tam ad → ad öneki (`dockerfile.dev`,
    /// `.env.local`) → uzantı → `generic`. Tam adın uzantıyı yenmesi şart:
    /// `package-lock.json` bir JSON'dur ama kullanıcı onu lock dosyası olarak
    /// tanır.
    public static func classify(name: String, isFolder: Bool, isExpanded: Bool) -> FileKind {
        if isFolder { return isExpanded ? .folderOpen : .folder }
        let lowercased = name.lowercased()
        if let byName = exactNames[lowercased] { return byName }
        if let byPrefix = prefixed(lowercased) { return byPrefix }
        if let byExtension = extensions[fileExtension(of: lowercased)] { return byExtension }
        return .generic
    }

    // MARK: - Tablolar

    /// Uzantıyı yenen tam adlar (hepsi lowercase).
    private static let exactNames: [String: FileKind] = [
        "makefile": .shell,
        "cmakelists.txt": .config,
        "dockerfile": .config,
        ".dockerignore": .config,
        ".editorconfig": .config,
        ".env": .config,
        ".gitignore": .git,
        ".gitattributes": .git,
        ".gitmodules": .git,
        ".gitkeep": .git,
        "package-lock.json": .lock,
        "package.resolved": .lock,
    ]

    /// Uzantı → sınıf (hepsi lowercase, noktasız).
    private static let extensions: [String: FileKind] = [
        "swift": .swift,
        "cs": .csharp,
        "ts": .typescript, "tsx": .typescript, "mts": .typescript,
        "js": .javascript, "jsx": .javascript, "mjs": .javascript, "cjs": .javascript,
        "json": .json, "jsonc": .json,
        "yml": .yaml, "yaml": .yaml,
        "md": .markdown, "markdown": .markdown, "mdx": .markdown,
        "txt": .text, "log": .text, "rtf": .text,
        "sh": .shell, "bash": .shell, "zsh": .shell, "fish": .shell, "command": .shell,
        "py": .python, "pyi": .python,
        "png": .image, "jpg": .image, "jpeg": .image, "gif": .image, "svg": .image,
        "tga": .image, "webp": .image, "bmp": .image, "ico": .image, "heic": .image,
        "tiff": .image, "psd": .image,
        "shader": .shader, "shadergraph": .shader, "compute": .shader, "cginc": .shader,
        "hlsl": .shader, "glsl": .shader, "metal": .shader,
        "unity": .unityScene,
        "prefab": .unityPrefab,
        "asset": .unityScriptableObject,
        "mat": .unityMaterial,
        "meta": .unityMeta,
        "toml": .config, "plist": .config, "xcconfig": .config, "ini": .config,
        "cfg": .config, "conf": .config, "entitlements": .config, "xml": .config,
        "lock": .lock,
        "zip": .archive, "tar": .archive, "gz": .archive, "tgz": .archive,
        "bz2": .archive, "xz": .archive, "7z": .archive, "rar": .archive,
        "unitypackage": .archive,
        "ttf": .font, "otf": .font, "woff": .font, "woff2": .font,
        "mp3": .audio, "wav": .audio, "aiff": .audio, "aif": .audio, "ogg": .audio,
        "m4a": .audio, "aac": .audio, "flac": .audio,
        "mp4": .video, "mov": .video, "avi": .video, "mkv": .video,
        "webm": .video, "m4v": .video,
    ]

    /// Aile oluşturan adlar: `dockerfile.dev`, `.env.local`, `Makefile.common`.
    private static func prefixed(_ lowercased: String) -> FileKind? {
        if lowercased.hasPrefix("dockerfile.") { return .config }
        if lowercased.hasPrefix(".env.") { return .config }
        if lowercased.hasPrefix("makefile.") { return .shell }
        return nil
    }

    /// Son noktadan sonrası; nokta yoksa, başta ise (`.hidden`) ya da sonda ise boş.
    private static func fileExtension(of lowercased: String) -> String {
        guard let dot = lowercased.lastIndex(of: "."), dot != lowercased.startIndex else { return "" }
        let start = lowercased.index(after: dot)
        guard start < lowercased.endIndex else { return "" }
        return String(lowercased[start...])
    }
}
