import Foundation

enum AgentShortcutAction: Equatable {
    case start
    case stop
}

/// Toggle-only state machine for the dedicated Agent Mode shortcut: press to
/// start, press again to stop. Mirrors the tap-to-toggle dictation lifecycle
/// (first activation starts, deactivation arms, second activation stops) but
/// tracks agent sessions independently so dictation state is unaffected.
final class AgentShortcutSessionController {
    private(set) var isActive = false
    private(set) var stopArmed = false

    func handle(event: ShortcutEvent, isTranscribing: Bool) -> AgentShortcutAction? {
        switch event {
        case .agentActivated:
            guard !isTranscribing else { return nil }
            if !isActive {
                isActive = true
                stopArmed = false
                return .start
            }
            guard stopArmed else { return nil }
            reset()
            return .stop
        case .agentDeactivated:
            guard isActive else { return nil }
            stopArmed = true
            return nil
        case .holdActivated, .holdDeactivated,
            .toggleActivated, .toggleDeactivated,
            .copyAgainTriggered:
            return nil
        }
    }

    func reset() {
        isActive = false
        stopArmed = false
    }
}
