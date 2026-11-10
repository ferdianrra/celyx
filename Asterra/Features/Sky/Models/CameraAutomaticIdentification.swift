import Foundation

/// A stable best match can be collected without becoming a sky calibration.
/// Only independent optical observations count; repeated render frames do not.
struct CameraAutomaticIdentification {
    private(set) var sourceID: Int?
    private var candidate: CameraCandidateMatch?
    private var firstSupport: TimeInterval = 0
    private var lastSupport: TimeInterval?
    private var count = 0
    var stableMatch: CameraCandidateMatch? {
        guard count >= 3, let lastSupport, lastSupport - firstSupport >= 0.4 else { return nil }
        return candidate
    }
    mutating func update(candidate: CameraCandidateMatch?, sourceID: Int, observedAt: TimeInterval) {
        guard observedAt.isFinite else { return }
        if self.sourceID != sourceID { self = Self(); self.sourceID = sourceID }
        if let lastSupport, observedAt <= lastSupport { return }
        let sameName = candidate?.star.id == self.candidate?.star.id && candidate != nil
        let continues = sameName && (stableMatch != nil
            || lastSupport.map { observedAt - $0 <= CameraTrackingPolicy.trackGap } == true)
        if !continues { count = 0; firstSupport = observedAt }
        self.candidate = candidate
        lastSupport = observedAt
        count = candidate == nil ? 0 : count + 1
    }
    /// A geometric re-sighting can regain a new optical ID after blur. Preserve
    /// the name decision, but never refresh its optical timestamp without pixels.
    mutating func continueSource(from oldID: Int?, to newID: Int) {
        guard let oldID, sourceID == oldID else { return }
        sourceID = newID
    }
    func canOfferCapturedPhoto(starID: Int, sourceID: Int?, at time: TimeInterval) -> Bool {
        guard self.sourceID == sourceID, stableMatch?.star.id == starID, let lastSupport else { return false }
        return CameraTrackingPolicy.keepsScan(lastSeen: lastSupport, now: time)
    }
    func freshMatch(at time: TimeInterval) -> CameraCandidateMatch? {
        guard let lastSupport, time >= lastSupport, time - lastSupport < 0.65 else { return nil }
        return stableMatch
    }
}
