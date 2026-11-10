import Foundation

/// Brief limited tracking pauses identification without throwing away the current world.
/// Interruptions and relocalization are reset separately by the session delegate.
struct CameraTrackingRecovery {
    private var hasTracked = false
    private var lossStarted: TimeInterval?
    private var reportedLoss = false

    mutating func update(isNormal: Bool, time: TimeInterval) -> Bool {
        if isNormal {
            hasTracked = true
            lossStarted = nil
            reportedLoss = false
            return false
        }
        guard hasTracked, !reportedLoss else { return false }
        if lossStarted == nil { lossStarted = time }
        guard time - (lossStarted ?? time) >= 2 else { return false }
        reportedLoss = true
        return true
    }
}
