import Foundation

/// Dosya adı → highlight.js dil kimliği (karar 111).
///
/// Önce tam ad (küçük harf) bakılır — `Podfile`, `CMakeLists.txt`,
/// `Dockerfile` gibi uzantısız ya da uzantısı yanıltan dosyalar; sonra ön ek
/// kalıpları (`Dockerfile.dev`, `.env.local`), en son uzantı. Tablodaki her
/// kimlik paketlenen bundle'da (highlight.js + Lumi gramerleri) olmalıdır:
/// bilinmeyen kimlik tüm dosyada pahalı ve isabetsiz otomatik algılamaya
/// düşerdi — `HighlightJSEngine` bunu açılışta doğrular.
enum HighlightLanguage {
    static func id(forFileName fileName: String) -> String? {
        let name = (fileName as NSString).lastPathComponent.lowercased()
        guard !name.isEmpty else { return nil }
        if let byName = byName[name] { return byName }
        if let byPrefix = prefixes.first(where: { name.hasPrefix($0.prefix) }) { return byPrefix.id }
        return byExtension[(name as NSString).pathExtension]
    }

    /// Tablodaki bütün kimlikler (bundle doğrulaması ve testler için).
    static var allIDs: Set<String> {
        Set(byName.values).union(byExtension.values).union(prefixes.map(\.id))
    }

    private static let byName: [String: String] = [
        "dockerfile": "dockerfile", "containerfile": "dockerfile",
        "makefile": "makefile", "gnumakefile": "makefile", "cmakelists.txt": "cmake",
        "podfile": "ruby", "gemfile": "ruby", "rakefile": "ruby", "brewfile": "ruby",
        "vagrantfile": "ruby", "fastfile": "ruby", "appfile": "ruby", "matchfile": "ruby",
        "dangerfile": "ruby", "guardfile": "ruby", "podfile.lock": "yaml",
        "jenkinsfile": "groovy",
        "build": "python", "build.bazel": "python", "workspace": "python", "workspace.bazel": "python",
        "nginx.conf": "nginx",
        ".env": "properties", ".editorconfig": "ini", ".gitconfig": "ini", ".gitmodules": "ini",
        ".npmrc": "ini", ".bashrc": "bash", ".zshrc": "bash", ".profile": "bash", ".bash_profile": "bash",
        ".zprofile": "bash",
        "cargo.lock": "ini", "yarn.lock": "yaml", "package.resolved": "json",
    ]

    private static let prefixes: [(prefix: String, id: String)] = [
        ("dockerfile.", "dockerfile"),
        (".env.", "properties"),
    ]

    private static let byExtension: [String: String] = [
        // C ailesi, Apple, JVM
        "c": "c", "h": "objectivec", "m": "objectivec", "mm": "objectivec",
        "cpp": "cpp", "cc": "cpp", "cxx": "cpp", "c++": "cpp", "hpp": "cpp", "hh": "cpp", "hxx": "cpp",
        "inl": "cpp", "ino": "arduino",
        "cs": "csharp", "csx": "csharp", "fs": "fsharp", "fsx": "fsharp", "vb": "vbnet",
        "swift": "swift", "kt": "kotlin", "kts": "kotlin", "java": "java", "scala": "scala", "sc": "scala",
        "groovy": "groovy", "gradle": "gradle", "dart": "dart",
        // Web
        "ts": "typescript", "tsx": "typescript", "mts": "typescript", "cts": "typescript",
        "js": "javascript", "jsx": "javascript", "mjs": "javascript", "cjs": "javascript",
        "json": "json", "jsonc": "json", "json5": "json", "jsonl": "json", "webmanifest": "json",
        "html": "xml", "htm": "xml", "xhtml": "xml", "vue": "xml", "svelte": "xml",
        "css": "css", "scss": "scss", "sass": "scss", "less": "less", "styl": "stylus",
        "graphql": "graphql", "gql": "graphql", "hbs": "handlebars", "handlebars": "handlebars",
        "twig": "twig", "erb": "erb", "haml": "haml",
        // Betik ve backend
        "py": "python", "pyi": "python", "pyw": "python", "bzl": "python", "star": "python",
        "rb": "ruby", "gemspec": "ruby", "podspec": "ruby", "rake": "ruby",
        "php": "php", "go": "go", "rs": "rust", "ex": "elixir", "exs": "elixir", "erl": "erlang",
        "hrl": "erlang", "lua": "lua", "pl": "perl", "pm": "perl", "r": "r", "jl": "julia",
        "hs": "haskell", "ml": "ocaml", "mli": "ocaml", "clj": "clojure", "cljs": "clojure",
        "edn": "clojure", "nim": "nim", "cr": "crystal", "zig": "rust",
        "sql": "sql", "psql": "pgsql",
        // Kabuk ve altyapı
        "sh": "bash", "bash": "bash", "zsh": "bash", "fish": "bash", "command": "bash",
        "ps1": "powershell", "psm1": "powershell", "psd1": "powershell",
        "bat": "dos", "cmd": "dos",
        "dockerfile": "dockerfile", "mk": "makefile", "make": "makefile", "cmake": "cmake",
        "nix": "nix", "conf": "nginx",
        "tf": "hcl", "tfvars": "hcl", "hcl": "hcl", "nomad": "hcl",
        "proto": "protobuf", "thrift": "thrift",
        // Yapılandırma ve veri
        "yaml": "yaml", "yml": "yaml",
        "toml": "ini", "ini": "ini", "cfg": "ini", "editorconfig": "ini",
        "properties": "properties", "env": "properties", "xcconfig": "properties",
        "xml": "xml", "svg": "xml", "plist": "xml", "entitlements": "xml", "storyboard": "xml",
        "xib": "xml", "csproj": "xml", "vbproj": "xml", "fsproj": "xml", "props": "xml",
        "targets": "xml", "resx": "xml", "nuspec": "xml", "xaml": "xml", "axaml": "xml",
        "xsd": "xml", "xsl": "xml", "rss": "xml", "wsdl": "xml",
        "md": "markdown", "markdown": "markdown", "mdx": "markdown",
        "tex": "latex", "diff": "diff", "patch": "diff",
        // Unity
        "unity": "yaml", "prefab": "yaml", "asset": "yaml", "meta": "yaml", "mat": "yaml",
        "anim": "yaml", "controller": "yaml", "overridecontroller": "yaml", "physicmaterial": "yaml",
        "mask": "yaml", "lighting": "yaml", "playable": "yaml", "spriteatlas": "yaml",
        "terrainlayer": "yaml", "mixer": "yaml", "guiskin": "yaml", "fontsettings": "yaml",
        "asmdef": "json", "asmref": "json", "inputactions": "json", "uxml": "xml", "uss": "css",
        "tss": "css",
        "shader": "shaderlab",
        "hlsl": "hlsl", "hlsli": "hlsl", "cginc": "hlsl", "compute": "hlsl", "fx": "hlsl",
        "fxh": "hlsl", "usf": "hlsl", "ush": "hlsl", "raytrace": "hlsl",
        "glsl": "glsl", "vert": "glsl", "frag": "glsl", "geom": "glsl", "comp": "glsl",
        "fsh": "glsl", "vsh": "glsl", "metal": "cpp", "wgsl": "rust",
    ]
}
