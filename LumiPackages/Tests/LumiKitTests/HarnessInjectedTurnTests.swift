import Testing
@testable import LumiKit

/// Karar 95: harness'in eklediği user turları chat'te gizlenir.
@Suite struct HarnessInjectedTurnTests {
    @Test func builtInCommandEnvelopeIsHidden() {
        // Gerçek `/clear` sonrası transcript'in ilk user kaydı.
        let clear = "<command-name>/clear</command-name>\n            <command-message>clear</command-message>\n            <command-args></command-args>"
        #expect(HarnessInjectedTurn.displayText(forUserText: clear) == nil)
        #expect(HarnessInjectedTurn.displayText(forUserText:
            "<command-name>/model</command-name><command-args>sonnet</command-args>") == nil)
    }

    @Test func skillEnvelopeSurfacesAsTypedToken() {
        let skill = "<command-message>review</command-message>\n<command-name>/superpowers:review</command-name>\n<command-args>PR 12</command-args>"
        #expect(HarnessInjectedTurn.displayText(forUserText: skill) == "/review PR 12")
    }

    @Test func localCommandOutputAndRemindersAreHidden() {
        for text in [
            "<local-command-stdout>Set model to Opus</local-command-stdout>",
            "<local-command-caveat>Caveat: The messages below…</local-command-caveat>",
            "  <system-reminder>\nfoo</system-reminder>",
            "<task-notification><task-id>x</task-id></task-notification>",
            "[Request interrupted by user]",
            "This session is being continued from a previous conversation that ran out of context.",
        ] {
            #expect(HarnessInjectedTurn.displayText(forUserText: text) == nil, "\(text)")
        }
    }

    @Test func genuineUserTextStays() {
        for text in ["merhaba", "<my-element> bunu düzelt", "<div>html paste</div>", "/clear yazınca ne olur?"] {
            #expect(HarnessInjectedTurn.displayText(forUserText: text) == text, "\(text)")
        }
    }
}
