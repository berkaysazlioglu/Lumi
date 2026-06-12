/// Tüm built-in terminal tema preset'lerinin tanımları.
/// Kaynak: her temanın resmi spec/dokümantasyonu.
/// Renkler 0xRRGGBB hex; selection 0xAARRGGBB (AA = alpha * 255).
enum TerminalThemePresets {

    // MARK: - Lumi (mevcut varsayılan tema — v1 xterm.js paritesi)
    // Kaynak: v1 src/renderer/components/Terminal/constants.ts

    static let lumi = TerminalTheme(
        id:             "lumi",
        name:           "Lumi",
        backgroundHex:  0x12121F,
        foregroundHex:  0xE2E2F0,
        cursorHex:      0xA78BFA,
        cursorTextHex:  0x12121F,
        selectionHex:   0x4D8B5CF6, // 0x8B5CF6 @ ~30% opacity (0x4D ≈ 77/255 ≈ 0.302)
        ansiHex: [
            0x0A0A12, // 0: black
            0xF87171, // 1: red
            0x4ADE80, // 2: green
            0xFBBF24, // 3: yellow
            0xA78BFA, // 4: blue
            0x8B5CF6, // 5: magenta
            0x22D3EE, // 6: cyan
            0xE2E2F0, // 7: white
            0x4A4A6A, // 8: bright black
            0xF87171, // 9: bright red
            0x4ADE80, // 10: bright green
            0xFBBF24, // 11: bright yellow
            0xA78BFA, // 12: bright blue
            0x8B5CF6, // 13: bright magenta
            0x22D3EE, // 14: bright cyan
            0xFFFFFF, // 15: bright white
        ]
    )

    // MARK: - Dracula
    // Kaynak: spec.draculatheme.com

    static let dracula = TerminalTheme(
        id:             "dracula",
        name:           "Dracula",
        backgroundHex:  0x282A36,
        foregroundHex:  0xF8F8F2,
        cursorHex:      0xF8F8F2,
        cursorTextHex:  0x282A36,
        selectionHex:   0x4D44475A, // 0x44475A @ ~30% opacity
        ansiHex: [
            0x21222C, // 0: black
            0xFF5555, // 1: red
            0x50FA7B, // 2: green
            0xF1FA8C, // 3: yellow
            0xBD93F9, // 4: blue
            0xFF79C6, // 5: magenta
            0x8BE9FD, // 6: cyan
            0xF8F8F2, // 7: white
            0x6272A4, // 8: bright black
            0xFF6E6E, // 9: bright red
            0x69FF94, // 10: bright green
            0xFFFFA5, // 11: bright yellow
            0xD6ACFF, // 12: bright blue
            0xFF92DF, // 13: bright magenta
            0xA4FFFF, // 14: bright cyan
            0xFFFFFF, // 15: bright white
        ]
    )

    // MARK: - One Dark
    // Kaynak: Binaryify/OneDark-Pro — oneDarkPro.ts (Atom/One Dark Pro spec)

    static let oneDark = TerminalTheme(
        id:             "one-dark",
        name:           "One Dark",
        backgroundHex:  0x282C34,
        foregroundHex:  0xABB2BF,
        cursorHex:      0x528BFF,
        cursorTextHex:  0x282C34,
        selectionHex:   0x4D3E4452, // 0x3E4452 @ ~30% opacity
        ansiHex: [
            0x3F4451, // 0: black
            0xE05561, // 1: red
            0x8CC265, // 2: green
            0xD18F52, // 3: yellow
            0x4AA5F0, // 4: blue
            0xC162DE, // 5: magenta
            0x42B3C2, // 6: cyan
            0xD7DAE0, // 7: white
            0x4F5666, // 8: bright black
            0xFF616E, // 9: bright red
            0xA5E075, // 10: bright green
            0xF0A45D, // 11: bright yellow
            0x4DC4FF, // 12: bright blue
            0xDE73FF, // 13: bright magenta
            0x4CD1E0, // 14: bright cyan
            0xE6E6E6, // 15: bright white
        ]
    )

    // MARK: - Nord
    // Kaynak: arcticicestudio/nord-alacritty — resmi Nord terminal portu

    static let nord = TerminalTheme(
        id:             "nord",
        name:           "Nord",
        backgroundHex:  0x2E3440,
        foregroundHex:  0xD8DEE9,
        cursorHex:      0xD8DEE9,
        cursorTextHex:  0x2E3440,
        selectionHex:   0x4D4C566A, // 0x4C566A @ ~30% opacity
        ansiHex: [
            0x3B4252, // 0: black
            0xBF616A, // 1: red
            0xA3BE8C, // 2: green
            0xEBCB8B, // 3: yellow
            0x81A1C1, // 4: blue
            0xB48EAD, // 5: magenta
            0x88C0D0, // 6: cyan
            0xE5E9F0, // 7: white
            0x4C566A, // 8: bright black
            0xBF616A, // 9: bright red   (Nord tasarımı: normal == bright)
            0xA3BE8C, // 10: bright green
            0xEBCB8B, // 11: bright yellow
            0x81A1C1, // 12: bright blue
            0xB48EAD, // 13: bright magenta
            0x8FBCBB, // 14: bright cyan
            0xECEFF4, // 15: bright white
        ]
    )

    // MARK: - Solarized Dark
    // Kaynak: ethanschoonover.com/solarized — canonical ANSI slot mapping

    static let solarizedDark = TerminalTheme(
        id:             "solarized-dark",
        name:           "Solarized Dark",
        backgroundHex:  0x002B36,
        foregroundHex:  0x839496,
        cursorHex:      0x93A1A1,
        cursorTextHex:  0x002B36,
        selectionHex:   0x4D073642, // 0x073642 @ ~30% opacity
        ansiHex: [
            0x073642, // 0: black       (base02)
            0xDC322F, // 1: red
            0x859900, // 2: green
            0xB58900, // 3: yellow
            0x268BD2, // 4: blue
            0xD33682, // 5: magenta
            0x2AA198, // 6: cyan
            0xEEE8D5, // 7: white       (base2)
            0x002B36, // 8: bright black  (base03)
            0xCB4B16, // 9: bright red    (orange)
            0x586E75, // 10: bright green (base01)
            0x657B83, // 11: bright yellow (base00)
            0x839496, // 12: bright blue  (base0)
            0x6C71C4, // 13: bright magenta (violet)
            0x93A1A1, // 14: bright cyan  (base1)
            0xFDF6E3, // 15: bright white (base3)
        ]
    )

    // MARK: - Solarized Light
    // ANSI paleti Solarized Dark ile aynıdır; yalnız bg/fg/cursor değişir.

    static let solarizedLight = TerminalTheme(
        id:             "solarized-light",
        name:           "Solarized Light",
        backgroundHex:  0xFDF6E3,
        foregroundHex:  0x657B83,
        cursorHex:      0x586E75,
        cursorTextHex:  0xFDF6E3,
        selectionHex:   0x4DEEE8D5, // 0xEEE8D5 @ ~30% opacity
        ansiHex: [
            0x073642, // 0: black       (base02)
            0xDC322F, // 1: red
            0x859900, // 2: green
            0xB58900, // 3: yellow
            0x268BD2, // 4: blue
            0xD33682, // 5: magenta
            0x2AA198, // 6: cyan
            0xEEE8D5, // 7: white       (base2)
            0x002B36, // 8: bright black  (base03)
            0xCB4B16, // 9: bright red    (orange)
            0x586E75, // 10: bright green (base01)
            0x657B83, // 11: bright yellow (base00)
            0x839496, // 12: bright blue  (base0)
            0x6C71C4, // 13: bright magenta (violet)
            0x93A1A1, // 14: bright cyan  (base1)
            0xFDF6E3, // 15: bright white (base3)
        ]
    )

    // MARK: - GitHub Light
    // Kaynak: primer/github-vscode-theme — src/classic/theme.js + colors.json

    static let githubLight = TerminalTheme(
        id:             "github-light",
        name:           "GitHub Light",
        backgroundHex:  0xFFFFFF,
        foregroundHex:  0x586069,
        cursorHex:      0x005CC5,
        cursorTextHex:  0xFFFFFF,
        selectionHex:   0x4DC8E1FF, // 0xC8E1FF @ ~30% opacity
        ansiHex: [
            0x24292E, // 0: black
            0xD73A49, // 1: red
            0x28A745, // 2: green
            0xDBAB09, // 3: yellow
            0x0366D6, // 4: blue
            0x5A32A3, // 5: magenta (primer.purple[6])
            0x1B7C83, // 6: cyan
            0x6A737D, // 7: white
            0x959DA5, // 8: bright black
            0xCB2431, // 9: bright red
            0x22863A, // 10: bright green
            0xB08800, // 11: bright yellow
            0x005CC5, // 12: bright blue
            0x5A32A3, // 13: bright magenta (primer.purple[6])
            0x3192AA, // 14: bright cyan
            0xD1D5DA, // 15: bright white
        ]
    )
}
