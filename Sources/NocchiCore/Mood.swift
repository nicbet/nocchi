/// What a face expresses. The reducer maps `AgentStatus` to a mood (M3); the UI draws it.
public enum Mood: String, CaseIterable, Sendable {
    /// Ready, nothing happening: blinks, follows the pointer.
    case idle
    /// Eyes wander.
    case thinking
    /// Typing badge, nods.
    case working
    /// Needs you: amber ring, head tilt, looks at the pointer.
    case waiting
    /// Finished: happy `^ ^` eyes, sparkles.
    case done
    /// Failed: turns red, `– –` eyes, shakes.
    case error
    /// No activity for a while: closed eyes, zZz.
    case sleep
}
