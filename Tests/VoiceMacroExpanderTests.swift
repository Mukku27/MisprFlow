import Foundation

enum VoiceMacroExpanderTests {
    static func run() {
        testWholeTriggerWithTrailingPunctuation()
        testInlineExpansionInSentence()
        testSecondCommandInline()
        testPartialWordsDoNotMatch()
        testTwoTriggersBothExpand()
        testLongerCommandWins()
        testRestoreKeepsCleanedAndFallsBack()
    }

    private static func macros() -> [VoiceMacro] {
        [
            VoiceMacro(command: "my email", payload: "SYNTHETIC-EMAIL-VALUE"),
            VoiceMacro(command: "my linkedin", payload: "SYNTHETIC-PROFILE-VALUE"),
            VoiceMacro(command: "desktop", payload: "SYNTHETIC-DESKTOP-VALUE"),
            VoiceMacro(command: "cf", payload: "SYNTHETIC-CF-VALUE"),
        ]
    }

    private static func testWholeTriggerWithTrailingPunctuation() {
        let macros = macros()
        if case .whole(let command, let payload) = VoiceMacroExpander.expand(
            transcript: "My email.",
            macros: macros
        ) {
            TestSupport.expectEqual(command, "my email")
            TestSupport.expectEqual(payload, "SYNTHETIC-EMAIL-VALUE")
        } else {
            TestSupport.expect(false, "Expected whole match for 'My email.'")
        }

        if case .whole(let command, let payload) = VoiceMacroExpander.expand(
            transcript: "MY EMAIL!",
            macros: macros
        ) {
            TestSupport.expectEqual(command, "my email")
            TestSupport.expectEqual(payload, "SYNTHETIC-EMAIL-VALUE")
        } else {
            TestSupport.expect(false, "Expected whole match for 'MY EMAIL!'")
        }
    }

    private static func testInlineExpansionInSentence() {
        let macros = macros()
        if case .inline(let expanded, let commands, let payloads) = VoiceMacroExpander.expand(
            transcript: "Please send the report to my email.",
            macros: macros
        ) {
            TestSupport.expectEqual(expanded, "Please send the report to SYNTHETIC-EMAIL-VALUE.")
            TestSupport.expectEqual(commands, ["my email"])
            TestSupport.expectEqual(payloads, ["SYNTHETIC-EMAIL-VALUE"])
        } else {
            TestSupport.expect(false, "Expected inline match for email sentence")
        }
    }

    private static func testSecondCommandInline() {
        let macros = macros()
        if case .inline(let expanded, let commands, let payloads) = VoiceMacroExpander.expand(
            transcript: "You can connect me on my linkedin.",
            macros: macros
        ) {
            TestSupport.expectEqual(expanded, "You can connect me on SYNTHETIC-PROFILE-VALUE.")
            TestSupport.expectEqual(commands, ["my linkedin"])
            TestSupport.expectEqual(payloads, ["SYNTHETIC-PROFILE-VALUE"])
        } else {
            TestSupport.expect(false, "Expected inline match for linkedin sentence")
        }
    }

    private static func testPartialWordsDoNotMatch() {
        let macros = macros()
        TestSupport.expectEqual(
            VoiceMacroExpander.expand(transcript: "My desktops are tidy.", macros: macros),
            .none
        )
        TestSupport.expectEqual(
            VoiceMacroExpander.expand(transcript: "I love craft beer.", macros: macros),
            .none
        )
    }

    private static func testTwoTriggersBothExpand() {
        let macros = macros()
        if case .inline(let expanded, let commands, let payloads) = VoiceMacroExpander.expand(
            transcript: "Send it to my email and connect on my linkedin.",
            macros: macros
        ) {
            TestSupport.expectEqual(
                expanded,
                "Send it to SYNTHETIC-EMAIL-VALUE and connect on SYNTHETIC-PROFILE-VALUE."
            )
            TestSupport.expectEqual(commands, ["my email", "my linkedin"])
            TestSupport.expectEqual(
                payloads,
                ["SYNTHETIC-EMAIL-VALUE", "SYNTHETIC-PROFILE-VALUE"]
            )
        } else {
            TestSupport.expect(false, "Expected both triggers to expand")
        }
    }

    private static func testLongerCommandWins() {
        let overlapping: [VoiceMacro] = [
            VoiceMacro(command: "email", payload: "SYNTHETIC-SHORT-VALUE"),
            VoiceMacro(command: "my email", payload: "SYNTHETIC-LONG-VALUE"),
        ]
        if case .inline(let expanded, let commands, _) = VoiceMacroExpander.expand(
            transcript: "Please send it to my email today.",
            macros: overlapping
        ) {
            TestSupport.expectEqual(expanded, "Please send it to SYNTHETIC-LONG-VALUE today.")
            TestSupport.expectEqual(commands, ["my email"])
        } else {
            TestSupport.expect(false, "Expected longer overlapping command to win")
        }
    }

    private static func testRestoreKeepsCleanedAndFallsBack() {
        let payloads = ["SYNTHETIC-EMAIL-VALUE"]
        let expanded = "Please send the report to SYNTHETIC-EMAIL-VALUE."
        let intact = "Please send the report to SYNTHETIC-EMAIL-VALUE."
        TestSupport.expectEqual(
            VoiceMacroExpander.restoredTranscript(
                cleaned: intact,
                expandedFallback: expanded,
                payloads: payloads
            ),
            intact
        )

        let dropped = "Please send the report to the inbox."
        TestSupport.expectEqual(
            VoiceMacroExpander.restoredTranscript(
                cleaned: dropped,
                expandedFallback: expanded,
                payloads: payloads
            ),
            expanded
        )
    }
}
