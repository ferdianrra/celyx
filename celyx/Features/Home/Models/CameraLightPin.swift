import Foundation
import simd

/// One real optical source retained in the current AR world. A remembered source is
/// navigation evidence only; collection still needs fresh light inside the reticle.
struct CameraLightPin {
    private(set) var direction: SIMD3<Float>
    let firstSeen: TimeInterval
    private(set) var lastSeen: TimeInterval
    private(set) var observationCount: Int
    private(set) var match: CameraCandidateMatch?
    private(set) var identifiedMatch: CameraCandidateMatch?
    var isIdentified: Bool { identifiedMatch != nil }
    private(set) var issue: CameraIdentificationIssue = .stabilizing
    private(set) var confirmedAt: TimeInterval?
    private var confirmationCount = 0

    init(direction: SIMD3<Float>,time: TimeInterval,observations: Int) {
        self.direction = direction; firstSeen = time; lastSeen = time
        observationCount = observations
    }
    func isSameSource(_ ray: SIMD3<Float>) -> Bool {
        simd_dot(direction,ray) > cos(0.75 * Float.pi/180)
    }
    func canReacquire(_ ray: SIMD3<Float>,identifiedAs candidate: CameraCandidateMatch?) -> Bool {
        // A nearby different catalog identity is not evidence that our source moved.
        if let saved = identifiedMatch, let candidate, saved.star.id != candidate.star.id { return false }
        if isSameSource(ray) { return true }
        // Reattach after a small tracking/zoom discontinuity only with independent
        // optical naming support. Never snap a remembered pin to the reticle itself.
        return identifiedMatch != nil && candidate?.star.id == identifiedMatch?.star.id
            && simd_dot(direction,ray) > cos(3 * Float.pi/180)
    }
    mutating func observe(direction: SIMD3<Float>,time: TimeInterval,identifiedAs candidate: CameraCandidateMatch? = nil) {
        guard time > lastSeen, canReacquire(direction,identifiedAs:candidate) else { return }
        self.direction = direction; lastSeen = time; observationCount += 1
    }
    func canBeReplaced(by ray: SIMD3<Float>,identifiedAs candidate: CameraCandidateMatch?) -> Bool {
        guard !isSameSource(ray) else { return false }
        return !isIdentified || (candidate != nil && candidate?.star.id != identifiedMatch?.star.id)
    }
    mutating func assess(_ assessment: CameraCandidateAssessment) {
        issue = assessment.issue
        guard !isIdentified else { return }
        // Keep the last supported suggestion if a later compass reading becomes ambiguous.
        if let match = assessment.match, observationCount >= 2 {
            if self.match?.star.id != match.star.id { confirmedAt = nil; confirmationCount = 0 }
            self.match = match
        }
    }
    /// Identification persists for this observed source. Frame freshness belongs
    /// to collection verification and must never erase the saved identity.
    mutating func identify(using match: CameraCandidateMatch) {
        guard !isIdentified, observationCount >= 2 else { return }
        self.match = match; identifiedMatch = match
    }
    /// Returning to a saved screen position is not a sighting. Only independent,
    /// newly observed rays with the same unambiguous identity can confirm this pin.
    mutating func confirm(_ assessment: CameraCandidateAssessment,observedAt: TimeInterval?,insideReticle: Bool) {
        guard insideReticle else { confirmedAt = nil; confirmationCount = 0; return }
        guard let observedAt else { return }
        guard assessment.match?.star.id == match?.star.id, assessment.match != nil else {
            confirmedAt = nil; confirmationCount = 0; return
        }
        if let confirmedAt {
            guard observedAt > confirmedAt else { return }
            if observedAt-confirmedAt > 0.65 { confirmationCount = 0 }
        }
        confirmedAt = observedAt; confirmationCount += 1
        if confirmationCount >= 2, let match { identify(using:match) }
    }
    func isDetected(at time: TimeInterval) -> Bool {
        guard let confirmedAt else { return false }
        return confirmationCount >= 2 && time >= confirmedAt && time-confirmedAt < 0.65
    }
    func isRecognizing(at time: TimeInterval) -> Bool {
        match == nil && time-firstSeen < 6
    }
}
