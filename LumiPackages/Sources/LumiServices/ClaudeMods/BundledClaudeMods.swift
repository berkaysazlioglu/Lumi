import Foundation

/// Lumi'nin mod klasörüne kendisinin yazdığı Claude Code modları (karar 142).
///
/// Dosyalar kaynak bundle'ı yerine Swift'e gömülür: SwiftPM/Xcode `.claude-plugin`
/// gibi noktalı klasörleri resource kopyasında güvenilir taşımıyor. Bir modun
/// içeriği değişince `version` artırılır — kurulumda sürüm farkı üzerine yazar.
struct BundledClaudeMod: Sendable {
    let id: String
    let version: String
    /// Mod klasörüne göre yol → içerik.
    let files: [String: String]
}

enum BundledClaudeMods {
    static let all: [BundledClaudeMod] = [imagePreview]

    /// Prompt'taki `[Image #N]` satırının altına yapıştırılan görselin küçük
    /// önizlemesi. Görsel Claude Code'un kitty grafikleriyle çizilir
    /// (`CLAUDE_CODE_FORCE_TERMINAL_IMAGES`, `TerminalEnvironment`); yol kuralı
    /// `ClaudePastedImages` ile aynıdır.
    static let imagePreview = BundledClaudeMod(
        id: "image-preview",
        version: "1.0.0",
        files: [
            ".claude-plugin/plugin.json": #"""
            {
              "name": "image-preview",
              "version": "1.0.0",
              "description": "Shows a small preview of each pasted image under the [Image #N] line of your prompt."
            }

            """#,
            "hooks/hooks.json": #"""
            { "modules": ["./register.tsx"] }

            """#,
            "hooks/register.tsx": #"""
            import type { Register } from 'claude-code'

            // Lumi'nin yazdığı mod (karar 142) — ~/.lumi/mods'ta elle yapılan değişiklik
            // Lumi güncellemesinde üzerine yazılır.
            // Claude Code yapıştırılan görseli /private/tmp/claude-<uid>/<cwd kodlaması>/<oturum>/images/N.png'ye yazar.
            const PLACEHOLDER = /\[Image #([1-9][0-9]{0,5})\]/g
            const TMP = '/private/tmp'

            export const register: Register = on => {
              on('ui.render', { component: 'UserMessage' }, async ($, e, next) => {
                const numbers = [...e.props.text.matchAll(PLACEHOLDER)].map(m => m[1])
                if (e.surface !== 'terminal' || numbers.length === 0) return next(e)

                const encoded = (await $.session.cwd()).replace(/[^a-zA-Z0-9]/g, '-')
                const sessionID = await $.session.id()
                const roots = (await $.fs.list(TMP)).filter(d => /^claude-\d+$/.test(d.name))
                const paths: string[] = []
                for (const n of numbers) for (const r of roots) {
                  const path = `${TMP}/${r.name}/${encoded}/${sessionID}/images/${n}.png`
                  if (await $.fs.exists(path)) { paths.push(path); break }
                }
                if (paths.length === 0) return next(e)

                const { Box, Image } = $.ui.resolve(e)
                return (
                  <Box flexDirection="column">
                    {await next(e)}
                    <Box gap={1} marginLeft={2}>
                      {paths.map(p => <Image source={{ file: p, format: 'png' }} columns={16} rows={8} alt={`[${p.split('/').pop()}]`} />)}
                    </Box>
                  </Box>
                )
              })
            }

            """#,
        ]
    )
}
