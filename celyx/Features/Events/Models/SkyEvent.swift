import Foundation

/// A curated sky event shown on the Sky Calendar (content from the Figma design).
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
    var hero: String { id == "mars-jupiter" ? "celyx-event-mars-jupiter-hero" : artwork.asset }
    var cameraThumbnail: String { id == "mars-jupiter" ? "celyx-mars-jupiter-thumb" : artwork.asset }

    func isOpen(at date: Date) -> Bool { date >= start }
    var opensLabel: String {
        "Opens "
            + start.formatted(
                .dateTime.month(.abbreviated).day().hour().minute().locale(Locale(identifier: "en_US")))
    }
}

extension SkyEvent {
    private static func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0
    ) -> Date {
        Calendar.current.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
            ?? .distantFuture
    }

    static let catalogue: [SkyEvent] = [
        SkyEvent(
            id: "mars-jupiter", kind: .event, title: "Mars & Jupiter Conjunction",
            start: date(2026, 11, 15, 0), end: date(2026, 11, 16, 5),
            headerDate: "November 15-16, 2026", detailDate: "November 15–16, 2026",
            viewingTime: "12:00 AM – 05:00 AM", direction: "Eastern Sky",
            about:
                "A beautiful celestial encounter awaits! Mars and Jupiter appear remarkably close together in the night sky, creating a stunning planetary pairing.\n\nAlthough millions of kilometers apart, these two planets seem to meet from our perspective on Earth, offering a fascinating sight for stargazers.",
            tips:
                "Find a spot with a clear view of the horizon, look towards the eastern sky, and watch these two bright planets shine together.",
            artwork: .init(asset: "celyx-event-mars-jupiter", size: 223, x: -65, y: -53)),
        SkyEvent(
            id: "leonids", kind: .event, title: "Leonid Meteor Shower",
            start: date(2026, 11, 18, 0), end: date(2026, 11, 18, 4, 30),
            headerDate: "November 18, 2026", detailDate: "November 18, 2026",
            viewingTime: "12:00 AM – 04:30 AM", direction: "Eastern Sky",
            about:
                "The Leonids streak out of the constellation Leo as Earth passes through dust left behind by Comet Tempel–Tuttle.\n\nMost meteors appear after midnight, when your side of Earth faces into the stream.",
            tips:
                "Get away from city lights, lie back and give your eyes 20 minutes to adjust. No telescope needed.",
            artwork: .init(asset: "celyx-event-meteor-card", size: 281, x: -100, y: -85)),
        SkyEvent(
            id: "beaver-moon", kind: .moon, title: "Beaver Moon",
            start: date(2026, 11, 24, 18), end: date(2026, 11, 25, 0),
            headerDate: "November 24, 2026", detailDate: "November 24, 2026",
            viewingTime: "06:00 PM – 12:00 AM", direction: "Eastern Sky",
            about: "November’s full Moon rises at sunset and lights up the sky all night long.",
            tips: "Catch it just after moonrise, when it sits low on the horizon and looks its biggest.",
            artwork: .init(asset: "celyx-event-beaver-moon", size: 146, x: -30, y: -18, flipped: true)),
        SkyEvent(
            id: "uranus-opposition", kind: .object, title: "Uranus at Opposition",
            start: date(2026, 11, 25, 18), end: date(2026, 11, 26, 0),
            headerDate: "November 25-26, 2026", detailDate: "November 25–26, 2026",
            viewingTime: "06:00 PM – 12:00 AM", direction: "Eastern Sky",
            about:
                "Earth passes between the Sun and Uranus, so the planet is at its closest and brightest for the year.",
            tips:
                "Uranus is very faint. Use binoculars under a dark sky and look for a small blue-green dot.",
            artwork: .init(asset: "celyx-event-uranus", size: 155, x: -30, y: -23)),
        SkyEvent(
            id: "venus-brightness", kind: .object, title: "Venus at Greatest Brightness",
            start: date(2026, 11, 27, 4), end: date(2026, 11, 27, 6),
            headerDate: "November 27, 2026", detailDate: "November 27, 2026",
            viewingTime: "Before Sunrise", direction: "Eastern Sky",
            about:
                "Venus shines at its most brilliant, outshining every other planet and star in the morning sky.",
            tips:
                "Look low in the east in the hour before sunrise. It’s the brightest point of light you’ll see.",
            artwork: .init(asset: "celyx-event-venus", size: 146, x: -26, y: -18)),
        SkyEvent(
            id: "geminids", kind: .event, title: "Geminid Meteor Shower",
            start: date(2026, 12, 13, 22), end: date(2026, 12, 14, 4, 30),
            headerDate: "December 13–14, 2026", detailDate: "December 13–14, 2026",
            viewingTime: "10:00 PM – 04:30 AM", direction: "Eastern Sky",
            about:
                "One of the richest meteor showers of the year, with bright, slow meteors radiating from Gemini.",
            tips: "Dress warmly, find a dark spot and watch a wide patch of sky rather than one point.",
            artwork: .init(asset: "celyx-event-meteor-card", size: 159, x: -6, y: -44)),
        SkyEvent(
            id: "cold-moon", kind: .moon, title: "Cold Moon",
            start: date(2026, 12, 24, 18), end: date(2026, 12, 25, 0),
            headerDate: "December 24, 2026", detailDate: "December 24, 2026",
            viewingTime: "06:00 PM – 12:00 AM", direction: "Eastern Sky",
            about: "December’s full Moon rides high through the long winter night.",
            tips: "Look east after sunset and watch it climb higher through the evening.",
            artwork: .init(asset: "celyx-event-cold-moon", size: 146, x: -26, y: -18, flipped: true)),
        SkyEvent(
            id: "moon-jupiter", kind: .event, title: "Moon & Jupiter Conjunction",
            start: date(2026, 12, 27, 19), end: date(2026, 12, 27, 23),
            headerDate: "December 27, 2026", detailDate: "December 27, 2026",
            viewingTime: "07:00 PM – 11:00 PM", direction: "Eastern Sky",
            about: "The Moon passes close to Jupiter, making the giant planet easy to find.",
            tips: "Find the Moon first, then look for the bright, steady point of light right beside it.",
            artwork: .init(asset: "celyx-event-moon-jupiter", size: 169, x: -28, y: -24, flipped: true)),
        SkyEvent(
            id: "wolf-moon", kind: .moon, title: "Wolf Moon",
            start: date(2027, 1, 3, 18), end: date(2027, 1, 4, 0),
            headerDate: "January 3-4, 2027", detailDate: "January 3–4, 2027",
            viewingTime: "06:00 PM – 12:00 AM", direction: "Eastern Sky",
            about: "The first full Moon of the new year.",
            tips: "Watch it rise in the east around sunset.",
            artwork: .init(asset: "celyx-event-wolf-moon", size: 146, x: -32, y: -19, flipped: true)),
    ]
}
