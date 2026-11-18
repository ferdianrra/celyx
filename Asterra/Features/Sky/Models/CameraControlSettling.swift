import Foundation

/// Camera controls use uptime, not capture timestamps (which restart with a new session).
nonisolated struct CameraControlSettling: Sendable {
    private var deadline: TimeInterval = 0

    mutating func begin(at uptime: TimeInterval) { deadline = uptime + 0.6 }
    mutating func reset() { deadline = 0 }
    func isActive(at uptime: TimeInterval) -> Bool { uptime < deadline }
}
