/// Pusat copywriting untuk tur onboarding.
/// Edit nilai teks di sini; urutan dan interaksi tetap di OnboardingFlow.
/// Bagian di bawah mengikuti alur tur, termasuk halaman yang dibuka di tengah tur.
/// Prompt izin iOS diatur lewat Info.plist / pengaturan proyek.
enum OnboardingCopy {

    static let continueTour = "Continue"
    static let skipTour = "Skip Tour"
    static let replayIntro = "Replay intro"
    static let startCollecting = "Start Collecting"

    static let welcomeTitle = "Welcome to Asterra"
    static let welcomeBody = "Let's take a one-minute walk through the sky together. You'll try everything yourself."
    static let startTour = "Start the Tour"

    static let lookTitle = "This is your Night Sea"
    static let lookBody = "Every star you collect will shine here. Turn around slowly and explore it: up, down and all the way round."

    static let lookSuccessTitle = "Nice, you're looking around"
    static let lookSuccessBody = "The Night Sea follows your phone, wherever you point it."

    static let cameraTitle = "See the real sky"
    static let cameraBody = "Your stars live in the real sky too. Tap the camera button in the corner to see it."

    static let cameraStartingTitle = "Opening your camera…"
    static let cameraStartingBody = "Hold your phone up toward the sky and keep it steady for a moment."

    static let cameraUnavailableTitle = "Camera access is off"
    static let cameraUnavailableBody = "You can allow it later in Settings. Let's practise right here in the Night Sea."

    static let cameraRetryTitle = "Let’s retry the camera"
    static let cameraRetryBody = "Try opening the camera again, or practise with a virtual star."
    static let cameraTimeoutBody = "The camera hasn’t delivered a frame yet. Try again, or practise with a virtual star."
    static let retryCamera = "Retry Camera"
    static let practiceWithoutCamera = "Practise with a virtual star"

    static let cameraSuccessTitle = "That's the real sky"
    static let cameraSuccessBody = "Let’s see what’s visible in your sky. Tap Start Collecting to try your first object."
    static let dayVisibilityTitle = "Can you see the Sun?"
    static let dayVisibilityBody = "It’s daytime where you are. If the Sun is visible, aim your camera toward it using the screen. Avoid looking directly at the Sun. If clouds hide it, we can try a virtual star."
    static let nightVisibilityTitle = "Can you see the Moon or a star?"
    static let nightVisibilityBody = "It’s dark where you are. Look for the Moon or a star, then aim your camera at the one you can see. If nothing is visible, we can try a virtual star."
    static let canSeeObject = "Yes, try the camera"
    static let cannotSeeObject = "Nothing visible — use a virtual star"
    static let realDayGuide = "Aim at the Sun using your screen, then hold steady until the circle locks."
    static let realNightGuide = "Aim at the Moon or a star you can see, then hold steady until the circle locks."
    static let findStarTitle = "Let’s try a virtual star"
    static let findStarBody = "This is a virtual practice star. Follow the glowing arrow, then move your phone until the star sits inside the circle."
    static let starLockedTitle = "It's in your circle"
    static let starLockedBody = "Now tap anywhere on the screen to collect it."
    static let collectingTitle = "Collecting…"
    static let collectingBody = "Hold steady."
    static let practiceStarName = "Practice Star"
    static let practiceStarIdentificationNote = "Practice star from the Asterra tour. Not saved to your collection."
    static let wormholeCaption = "Collected! Watch it fly into your Night Sea."
    static let noteEntryGuide = "Every star keeps a note. Write what this moment feels like, then tap Done."
    static let starCardGuide = "This is your star's card: your note, photo, place and time. Tap ✕ to go back to the sky."

    static let landedTitle = "That's collecting"
    static let landedBody = "Every real star you collect stays in your Night Sea. Tap the same button to go back there."

    static let landedWithoutCameraTitle = "That's collecting"
    static let landedWithoutCameraBody = "Every real star you collect stays in your Night Sea, in its true place."

    static let landedSuccessTitle = "Back in your Night Sea"
    static let landedSuccessBody = "Switch between the real sky and the Night Sea anytime with that button."
    
    static let collectionTitle = "Your collection"
    static let collectionBody = "Everything you find lands here. Tap the glowing book at the top to look inside."

    // Petunjuk di sheet kategori koleksi.
    static let collectionGuide = "Your stars, planets, sky events and constellations live here. Tap a category to explore."

    // List Celestial Object.
    static let collectionListGuide = "Everything you collect will be listed here. Tap ‹ at the top to come back."
    static let collectionSuccessTitle = "That's your collection"
    static let collectionSuccessBody = "Come back to it anytime from the book at the top."
    static let calendarTitle = "Sky Calendar"
    static let calendarBody = "Meteor showers, eclipses and more. Tap the glowing calendar at the top to see what's coming."
    static let calendarGuide = "Browse upcoming sky events in List or Calendar, then tap a bell to set a reminder."
    static let calendarSuccessTitle = "That's the Sky Calendar"
    static let calendarSuccessBody = "Set a reminder on any event so you never miss it."

    static let readyTitle = "You're ready"
    static let readyBody = "Tap Start Collecting whenever you're under the sky to find your first real star."

    static let doneTitle = "Done"
    static let doneBody = ""

    static func progress(current: Int, total: Int) -> String {
        "\(current) of \(total)"
    }
    static func progressAccessibilityLabel(current: Int, total: Int) -> String {
        "Step \(current) of \(total)"
    }
}
