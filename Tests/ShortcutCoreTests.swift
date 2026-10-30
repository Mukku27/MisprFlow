import Foundation

enum ShortcutCoreTests {
    static func run() {
        testBareFnHoldLifecycle()
        testDefaultShortcutSpecificityOrdering()
        testRightOptionPresetIsSideSpecific()
        testExactModifierMatching()
        testReducerHonorsExactModifierMatching()
        testRepeatedKeyDownDoesNotReactivate()
        testPasteAgainFiresOnLeadingEdgeOnly()
        testBackendResetClearsActiveBindings()
        testBindingMigrationAndIdentity()
        testConflictDetection()
        testHoldSessionControllerLifecycle()
        testToggleSessionControllerLifecycle()
        testHoldToToggleSessionControllerLifecycle()
        testAgentActivationDeactivationEdges()
        testAgentWinsSpecificityAgainstHold()
        testReleaseGatingIncludesAgentInputs()
        testDefaultAgentBindingsDoNotConflict()
        testAgentSessionControllerLifecycle()
        testDictationSessionControllerIgnoresAgentEvents()
    }

    private static func testBareFnHoldLifecycle() {
        let configuration = ShortcutConfiguration(hold: .defaultHold, toggle: .disabled)
        let down = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 63, isDown: true),
            configuration: configuration
        )
        let up = ShortcutMatcher.reduce(
            state: down.state,
            event: .modifierChanged(keyCode: 63, isDown: false),
            configuration: configuration
        )

        TestSupport.expectEqual(down.emittedEvents, [.holdActivated])
        TestSupport.expectEqual(down.consumeDecision, .consume)
        TestSupport.expectEqual(up.emittedEvents, [.holdDeactivated])
        TestSupport.expectEqual(up.consumeDecision, .consume)
    }

    private static func testDefaultShortcutSpecificityOrdering() {
        let configuration = ShortcutConfiguration(
            hold: .defaultHold,
            toggle: .defaultToggle
        )
        let commandDown = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 55, isDown: true),
            configuration: configuration
        )
        let fnDown = ShortcutMatcher.reduce(
            state: commandDown.state,
            event: .modifierChanged(keyCode: 63, isDown: true),
            configuration: configuration
        )
        let fnUp = ShortcutMatcher.reduce(
            state: fnDown.state,
            event: .modifierChanged(keyCode: 63, isDown: false),
            configuration: configuration
        )

        TestSupport.expectEqual(fnDown.emittedEvents, [.toggleActivated, .holdActivated])
        TestSupport.expectEqual(fnUp.emittedEvents, [.holdDeactivated, .toggleDeactivated])
    }

    private static func testRightOptionPresetIsSideSpecific() {
        let configuration = ShortcutConfiguration(
            hold: ShortcutPreset.rightOption.binding,
            toggle: .disabled
        )
        let leftOption = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 58, isDown: true),
            configuration: configuration
        )
        let rightOption = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 61, isDown: true),
            configuration: configuration
        )

        TestSupport.expectEqual(leftOption.emittedEvents, [])
        TestSupport.expectEqual(rightOption.emittedEvents, [.holdActivated])
    }

    private static func testExactModifierMatching() {
        TestSupport.expect(
            ShortcutBinding.exactModifierKeyCodesMatch([54], exactModifierKeyCodes: [54, 55]),
            "A generic Command binding should accept Right Command"
        )
        TestSupport.expect(
            ShortcutBinding.exactModifierKeyCodesMatch([55], exactModifierKeyCodes: [54, 55]),
            "A generic Command binding should accept Left Command"
        )
        TestSupport.expect(
            !ShortcutBinding.exactModifierKeyCodesMatch([55, 56], exactModifierKeyCodes: [55]),
            "Unexpected Shift should invalidate an exact Command binding"
        )
        TestSupport.expect(
            ShortcutBinding.exactModifierKeyCodesMatch(
                [55, 56],
                exactModifierKeyCodes: [55],
                permittedAdditionalExactMatchModifiers: [.shift]
            ),
            "Explicitly permitted Shift should not invalidate an exact Command binding"
        )
    }

    private static func testReducerHonorsExactModifierMatching() {
        let binding = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [.command],
            kind: .key,
            preset: nil,
            exactModifierKeyCodes: [55]
        )

        let rightCommandState = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 54, isDown: true),
            configuration: ShortcutConfiguration(hold: binding, toggle: .disabled)
        ).state
        let rightCommandKey = ShortcutMatcher.reduce(
            state: rightCommandState,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: ShortcutConfiguration(hold: binding, toggle: .disabled)
        )
        TestSupport.expectEqual(rightCommandKey.emittedEvents, [])

        let leftCommandState = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 55, isDown: true),
            configuration: ShortcutConfiguration(hold: binding, toggle: .disabled)
        ).state
        let leftCommandKey = ShortcutMatcher.reduce(
            state: leftCommandState,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: ShortcutConfiguration(hold: binding, toggle: .disabled)
        )
        TestSupport.expectEqual(leftCommandKey.emittedEvents, [.holdActivated])

        let shiftedState = ShortcutMatcher.reduce(
            state: leftCommandState,
            event: .modifierChanged(keyCode: 56, isDown: true),
            configuration: ShortcutConfiguration(hold: binding, toggle: .disabled)
        ).state
        let shiftedKey = ShortcutMatcher.reduce(
            state: shiftedState,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: ShortcutConfiguration(hold: binding, toggle: .disabled)
        )
        TestSupport.expectEqual(shiftedKey.emittedEvents, [])

        let permittedConfiguration = ShortcutConfiguration(
            hold: binding,
            toggle: .disabled,
            permittedAdditionalExactMatchModifiers: [.shift]
        )
        let permittedKey = ShortcutMatcher.reduce(
            state: shiftedState,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: permittedConfiguration
        )
        TestSupport.expectEqual(permittedKey.emittedEvents, [.holdActivated])
    }

    private static func testRepeatedKeyDownDoesNotReactivate() {
        let binding = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [],
            kind: .key,
            preset: nil
        )
        let configuration = ShortcutConfiguration(hold: binding, toggle: .disabled)
        let first = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: configuration
        )
        let repeated = ShortcutMatcher.reduce(
            state: first.state,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: true),
            configuration: configuration
        )

        TestSupport.expectEqual(first.emittedEvents, [.holdActivated])
        TestSupport.expectEqual(repeated.emittedEvents, [])
        TestSupport.expectEqual(repeated.state, first.state)
        TestSupport.expectEqual(repeated.consumeDecision, .consume)
    }

    private static func testPasteAgainFiresOnLeadingEdgeOnly() {
        let binding = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [],
            kind: .key,
            preset: nil
        )
        let configuration = ShortcutConfiguration(hold: .disabled, toggle: .disabled, copyAgain: binding)
        let firstDown = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: configuration
        )
        let repeated = ShortcutMatcher.reduce(
            state: firstDown.state,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: true),
            configuration: configuration
        )
        let up = ShortcutMatcher.reduce(
            state: repeated.state,
            event: .keyChanged(keyCode: 96, isDown: false, isRepeat: false),
            configuration: configuration
        )
        let secondDown = ShortcutMatcher.reduce(
            state: up.state,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: configuration
        )

        TestSupport.expectEqual(firstDown.emittedEvents, [.copyAgainTriggered])
        TestSupport.expectEqual(repeated.emittedEvents, [])
        TestSupport.expectEqual(up.emittedEvents, [])
        TestSupport.expectEqual(secondDown.emittedEvents, [.copyAgainTriggered])
    }

    private static func testBackendResetClearsActiveBindings() {
        let configuration = ShortcutConfiguration(hold: .defaultHold, toggle: .defaultToggle)
        let commandDown = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 55, isDown: true),
            configuration: configuration
        )
        let fnDown = ShortcutMatcher.reduce(
            state: commandDown.state,
            event: .modifierChanged(keyCode: 63, isDown: true),
            configuration: configuration
        )
        let reset = ShortcutMatcher.reduce(
            state: fnDown.state,
            event: .backendReset,
            configuration: configuration
        )

        TestSupport.expectEqual(reset.emittedEvents, [.holdDeactivated, .toggleDeactivated])
        TestSupport.expectEqual(reset.consumeDecision, .passthrough)
        TestSupport.expect(reset.state.pressedKeyCodes.isEmpty, "Backend reset should clear pressed keys")
        TestSupport.expect(reset.state.pressedModifierKeyCodes.isEmpty, "Backend reset should clear modifiers")
        TestSupport.expect(!reset.state.holdIsActive && !reset.state.toggleIsActive, "Backend reset should clear active bindings")
    }

    private static func testBindingMigrationAndIdentity() {
        let stored = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [],
            kind: .key,
            preset: nil,
            exactModifierKeyCodes: [999, 61]
        )
        let normalized = stored.normalizedForStorageMigration()
        TestSupport.expectEqual(normalized.exactModifierKeyCodes, [61])
        TestSupport.expectEqual(normalized.modifiers, [.option])

        let first = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [.command, .option],
            kind: .key,
            preset: nil,
            exactModifierKeyCodes: [55, 58]
        )
        let second = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [.option, .command],
            kind: .key,
            preset: nil,
            exactModifierKeyCodes: [58, 55]
        )
        TestSupport.expectEqual(first.id, second.id)
    }

    private static func testConflictDetection() {
        let first = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [.command],
            kind: .key,
            preset: nil
        )
        let same = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [.command],
            kind: .key,
            preset: nil
        )
        let different = ShortcutBinding(
            keyCode: 97,
            keyDisplay: "F6",
            modifiers: [.command],
            kind: .key,
            preset: nil
        )

        TestSupport.expect(first.conflicts(with: same), "Equivalent bindings should conflict")
        TestSupport.expect(same.conflicts(with: first), "Conflict detection should be symmetric")
        TestSupport.expect(!first.conflicts(with: different), "Different primary keys should not conflict")
        TestSupport.expect(!first.conflicts(with: .disabled), "Disabled bindings should not conflict")
    }

    private static func testHoldSessionControllerLifecycle() {
        let controller = DictationShortcutSessionController()
        TestSupport.expectEqual(controller.handle(event: .holdActivated, isTranscribing: true), nil)
        TestSupport.expectEqual(controller.handle(event: .holdActivated, isTranscribing: false), .start(.hold))
        TestSupport.expectEqual(controller.handle(event: .holdDeactivated, isTranscribing: false), .stop)
        TestSupport.expectEqual(controller.activeMode, nil)
    }

    private static func testToggleSessionControllerLifecycle() {
        let controller = DictationShortcutSessionController()
        TestSupport.expectEqual(controller.handle(event: .toggleActivated, isTranscribing: false), .start(.toggle))
        TestSupport.expectEqual(controller.handle(event: .toggleActivated, isTranscribing: false), nil)
        TestSupport.expectEqual(controller.handle(event: .toggleDeactivated, isTranscribing: false), nil)
        TestSupport.expectEqual(controller.toggleStopArmed, true)
        TestSupport.expectEqual(controller.handle(event: .toggleActivated, isTranscribing: false), .stop)
        TestSupport.expectEqual(controller.activeMode, nil)
    }

    private static func testHoldToToggleSessionControllerLifecycle() {
        let controller = DictationShortcutSessionController()
        TestSupport.expectEqual(controller.handle(event: .holdActivated, isTranscribing: false), .start(.hold))
        TestSupport.expectEqual(controller.handle(event: .toggleActivated, isTranscribing: false), .switchedToToggle)
        TestSupport.expectEqual(controller.handle(event: .holdDeactivated, isTranscribing: false), nil)
        TestSupport.expectEqual(controller.activeMode, .toggle)
        TestSupport.expectEqual(controller.handle(event: .copyAgainTriggered, isTranscribing: false), nil)
        controller.beginManual(mode: .hold)
        TestSupport.expectEqual(controller.activeMode, .hold)
        controller.forceToggleMode()
        TestSupport.expectEqual(controller.activeMode, .toggle)
        controller.reset()
        TestSupport.expectEqual(controller.activeMode, nil)
        TestSupport.expectEqual(controller.toggleStopArmed, false)
    }

    private static func testAgentActivationDeactivationEdges() {
        let configuration = ShortcutConfiguration(hold: .disabled, toggle: .disabled, agent: .defaultAgent)
        let controlDown = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 59, isDown: true),
            configuration: configuration
        )
        TestSupport.expectEqual(controlDown.emittedEvents, [])
        let fnDown = ShortcutMatcher.reduce(
            state: controlDown.state,
            event: .modifierChanged(keyCode: 63, isDown: true),
            configuration: configuration
        )
        TestSupport.expectEqual(fnDown.emittedEvents, [.agentActivated])
        TestSupport.expectEqual(fnDown.consumeDecision, .consume)
        TestSupport.expect(fnDown.state.agentIsActive, "Agent binding should be active while Fn+Ctrl is held")
        let controlUp = ShortcutMatcher.reduce(
            state: fnDown.state,
            event: .modifierChanged(keyCode: 59, isDown: false),
            configuration: configuration
        )
        TestSupport.expectEqual(controlUp.emittedEvents, [.agentDeactivated])
        let fnUp = ShortcutMatcher.reduce(
            state: controlUp.state,
            event: .modifierChanged(keyCode: 63, isDown: false),
            configuration: configuration
        )
        TestSupport.expectEqual(fnUp.emittedEvents, [])
        TestSupport.expect(!fnUp.state.agentIsActive, "Agent binding should be inactive after release")
    }

    private static func testAgentWinsSpecificityAgainstHold() {
        let configuration = ShortcutConfiguration(
            hold: .defaultHold,
            toggle: .disabled,
            agent: .defaultAgent
        )
        let controlDown = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 59, isDown: true),
            configuration: configuration
        )
        let fnDown = ShortcutMatcher.reduce(
            state: controlDown.state,
            event: .modifierChanged(keyCode: 63, isDown: true),
            configuration: configuration
        )
        // Agent (Fn+Ctrl) is more specific than bare-Fn hold, so it sorts first.
        TestSupport.expectEqual(fnDown.emittedEvents, [.agentActivated, .holdActivated])
        let reset = ShortcutMatcher.reduce(
            state: fnDown.state,
            event: .backendReset,
            configuration: configuration
        )
        // Deactivations sort least-specific first.
        TestSupport.expectEqual(reset.emittedEvents, [.holdDeactivated, .agentDeactivated])
    }

    private static func testReleaseGatingIncludesAgentInputs() {
        let configuration = ShortcutConfiguration(hold: .disabled, toggle: .disabled, agent: .defaultAgent)
        var state = ShortcutInputState()
        TestSupport.expect(!state.hasPressedShortcutInputs(configuration: configuration), "Idle state should not gate release")
        state = ShortcutMatcher.reduce(
            state: state,
            event: .modifierChanged(keyCode: 59, isDown: true),
            configuration: configuration
        ).state
        state = ShortcutMatcher.reduce(
            state: state,
            event: .modifierChanged(keyCode: 63, isDown: true),
            configuration: configuration
        ).state
        TestSupport.expect(state.hasPressedShortcutInputs(configuration: configuration), "Held agent shortcut should gate release so paste waits for key-up")
        state = ShortcutMatcher.reduce(
            state: state,
            event: .modifierChanged(keyCode: 59, isDown: false),
            configuration: configuration
        ).state
        state = ShortcutMatcher.reduce(
            state: state,
            event: .modifierChanged(keyCode: 63, isDown: false),
            configuration: configuration
        ).state
        TestSupport.expect(!state.hasPressedShortcutInputs(configuration: configuration), "Released agent shortcut should stop gating release")
    }

    private static func testDefaultAgentBindingsDoNotConflict() {
        TestSupport.expect(!ShortcutBinding.defaultAgent.conflicts(with: .defaultHold), "Agent and hold defaults should not conflict")
        TestSupport.expect(!ShortcutBinding.defaultHold.conflicts(with: .defaultAgent), "Conflict detection should be symmetric")
        TestSupport.expect(!ShortcutBinding.defaultAgent.conflicts(with: .defaultToggle), "Agent and tap defaults should not conflict")
        TestSupport.expect(!ShortcutBinding.defaultToggle.conflicts(with: .defaultAgent), "Conflict detection should be symmetric")
        TestSupport.expect(!ShortcutBinding.defaultAgent.conflicts(with: .disabled), "Disabled bindings should not conflict")
        TestSupport.expect(!ShortcutBinding.defaultHold.conflicts(with: .defaultToggle), "Hold/tap defaults stay distinct")
    }

    private static func testAgentSessionControllerLifecycle() {
        let controller = AgentShortcutSessionController()
        TestSupport.expectEqual(controller.handle(event: .agentActivated, isTranscribing: true), nil)
        TestSupport.expectEqual(controller.handle(event: .holdActivated, isTranscribing: false), nil)
        TestSupport.expectEqual(controller.handle(event: .toggleActivated, isTranscribing: false), nil)
        TestSupport.expectEqual(controller.handle(event: .copyAgainTriggered, isTranscribing: false), nil)
        TestSupport.expectEqual(controller.handle(event: .agentActivated, isTranscribing: false), .start)
        TestSupport.expectEqual(controller.isActive, true)
        TestSupport.expectEqual(controller.handle(event: .agentActivated, isTranscribing: false), nil)
        TestSupport.expectEqual(controller.handle(event: .agentDeactivated, isTranscribing: false), nil)
        TestSupport.expectEqual(controller.stopArmed, true)
        TestSupport.expectEqual(controller.handle(event: .agentActivated, isTranscribing: false), .stop)
        TestSupport.expectEqual(controller.isActive, false)
        TestSupport.expectEqual(controller.stopArmed, false)
        controller.reset()
        TestSupport.expectEqual(controller.isActive, false)
        TestSupport.expectEqual(controller.stopArmed, false)
    }

    private static func testDictationSessionControllerIgnoresAgentEvents() {
        let controller = DictationShortcutSessionController()
        TestSupport.expectEqual(controller.handle(event: .agentActivated, isTranscribing: false), nil)
        TestSupport.expectEqual(controller.handle(event: .agentDeactivated, isTranscribing: false), nil)
        TestSupport.expectEqual(controller.activeMode, nil)
        TestSupport.expectEqual(controller.handle(event: .holdActivated, isTranscribing: false), .start(.hold))
        TestSupport.expectEqual(controller.handle(event: .agentActivated, isTranscribing: false), nil)
        TestSupport.expectEqual(controller.handle(event: .agentDeactivated, isTranscribing: false), nil)
        TestSupport.expectEqual(controller.activeMode, .hold)
    }
}
