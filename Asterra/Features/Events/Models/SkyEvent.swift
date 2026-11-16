import Foundation

/// A sky event shown on the Sky Calendar, computed by Astronomy Engine for the user's location and time zone.
struct SkyEvent: Identifiable, Hashable {
    enum Kind: String, CaseIterable, Identifiable {
        case object = "Object"
        case moon = "Moon"
        case event = "Events"
        var id: String { rawValue }
        /// Label used on the calendar filter chips.
        var chipTitle: String { self == .object ? "Objects" : rawValue }
        var icon: String {
            switch self {
            case .object: "celyx-icon-object"
            case .moon: "celyx-icon-moon"
            case .event: "celyx-icon-events"
            }
        }
    }
    /// Artwork placement inside a 362×109 card, in points relative to the card's top-left corner.
    struct Artwork: Hashable {
        let asset: String
        let size: CGFloat
        let x: CGFloat
        let y: CGFloat
        /// Mirrored horizontally in the design.
        var flipped = false
    }
    /// What to point the camera at: Astronomy Engine body names ("Moon", "Mars"…) or a meteor radiant.
    enum Target: Hashable {
        case body(String)
        /// Both bodies must be up; the camera is guided to their midpoint.
        case pair(String, String)
        /// Right ascension in hours, declination in degrees.
        case radiant(ra: Double, dec: Double)
    }

    let id: String
    let kind: Kind
    let title: String
    let start: Date
    let end: Date
    let headerDate: String
    let detailDate: String
    let viewingTime: String
    let direction: String
    let about: String
    let tips: String
    let artwork: Artwork
    let target: Target
    var hero: String { artwork.asset == "celyx-event-mars-jupiter" ? "celyx-event-mars-jupiter-hero" : artwork.asset }
    var cameraThumbnail: String {
        artwork.asset == "celyx-event-mars-jupiter" ? "celyx-mars-jupiter-thumb" : artwork.asset
    }

    /// Events can only be collected inside their viewing window (the time shown on the card).
    func isOpen(at date: Date) -> Bool { date >= start && date <= end }
    func hasEnded(at date: Date) -> Bool { date > end }
    /// "November 16, 2026 · 12:50 AM – 04:55 AM"
    var collectWindow: String { "\(detailDate) · \(viewingTime)" }
    var opensLabel: String {
        "Opens "
            + start.formatted(
                .dateTime.month(.abbreviated).day().hour().minute().locale(Locale(identifier: "en_US")))
    }
}

extension SkyEvent {
    /// Events computed live by Astronomy Engine for the user's location (see `SkyEventCatalog`).
    static var catalogue: [SkyEvent] { SkyEventCatalog.shared.catalogue }
}
