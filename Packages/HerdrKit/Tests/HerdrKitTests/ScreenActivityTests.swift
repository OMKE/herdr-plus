import Foundation
import Testing
@testable import HerdrKit

@Test func claudeSpinnerLine() {
    let screen = """
    ● Potvrđeno: bez exit 0 kod je 128.

    ✻ Deliberating… (4m 50s · ↓ 3.4k tokens)
      ⎿  Tip: Use /btw to ask a quick side question
    ──────────────────────────────
    >
    """
    let a = ScreenActivity.parse(screen)
    #expect(a?.label == "Deliberating…")
    #expect(a?.detail == "4m 50s · ↓ 3.4k tokens")
}

@Test func claudeSpinnerEscOnly() {
    let a = ScreenActivity.parse("✶ Combobulating… (esc to interrupt)\n> ")
    #expect(a?.label == "Combobulating…")
    #expect(a?.detail == nil)
}

@Test func codexSpinnerLine() {
    let a = ScreenActivity.parse("• Working (12s • esc to interrupt)\n› ")
    #expect(a?.label == "Working…")
    #expect(a?.detail == "12s")
}

@Test func finishedTurnHasNoActivity() {
    #expect(ScreenActivity.parse("✻ Cooked for 2m 10s\n\n> ") == nil)
    #expect(ScreenActivity.parse("● Done. All tests pass.\n> ") == nil)
    #expect(ScreenActivity.parse("* Loading… (step 1)\n● Done.\n> ") == nil)
}
