enum OnboardingCopy {

    static let continueTour = "Continue"
    static let skipTour = "Skip Tour"
    static let replayTour = "Replay tour"
    static let startCollecting = "Start Collecting"

    static let welcomeTitle = "Welcome to Asterra!"
    static let welcomeBody = "Ready to explore the sky? Let's take a quick tour and discover how to find and collect objects above you."
    static let startTour = "Start the Tour"

    static let lookTitle = "This is your Sky Garden"
    static let lookBody = "Every star you collect will shine here. Take a look around! Move your phone in different directions and explore the sky all around you."

    static let lookSuccessTitle = "Nice exploring!"
    static let lookSuccessBody = "Your Sky Garden moves wherever you point your phone. Now, are you ready to see the real sky?"

    static let cameraTitle = "Let's explore the real sky!"
    static let cameraBody = "Ready to see what's above you? Tap the AR button to switch to your camera."

    static let cameraStartingTitle = "Opening your camera…"
    static let cameraStartingBody = "Hold your phone up toward the sky and keep it steady for a moment."

    static let cameraUnavailableTitle = "Camera access is off"
    static let cameraUnavailableBody = "You can allow it later in Settings. Let's practise right here in the Sky Garden."

    static let cameraRetryTitle = "Let’s retry the camera"
    static let cameraRetryBody = "Try opening the camera again, or practise with a virtual star."
    static let cameraTimeoutBody = "The camera hasn’t delivered a frame yet. Try again, or practise with a virtual star."
    static let retryCamera = "Retry Camera"
    static let practiceWithoutCamera = "Practise with a virtual star"

    static let cameraSuccessTitle = "Welcome to the real sky!"
    static let cameraSuccessBody = "Let's see what's visible in your sky. Tap Start Collecting to find your first object."
    static let dayVisibilityTitle = "Let’s try a virtual Sun"
    static let dayVisibilityBody = "A virtual Sun will appear on your screen, in the same direction as the real Sun. Collect it to add it to your Sky Garden."
    static let nightVisibilityTitle = "Can you spot the Moon or a star?"
    static let nightVisibilityBody = "Take a look at the sky around you. See something? Point your camera towards it! Can't see anything right now? No worries, let's try a virtual star."
    static let canSeeObject = "Yes, try the camera"
    static let tryGuidedSun = "Show the virtual Sun"
    static let findSunTitle = "Bring the virtual Sun into view"
    static let findSunBody = "Follow the arrow and move your phone until the virtual Sun is inside the circle."
    static let sunLockedBody = "Tap anywhere to add the Sun to your Sky Garden."
    static let sunGardenBody = "The Sun you just collected is here now. It will stay in your Sky Garden, along with the stars you collect next."
    static let guidedSunIdentificationNote = "Added with the Sun guide using time and location, without optical identification."
    static let cannotSeeObject = "Try a virtual star"
    static let realDayGuide = "Point your camera at the Sun and hold steady until it locks. Keep your eyes on the screen."
    static let realNightGuide = "Point your camera at the Moon or a visible star, then hold steady until the circle locks."
    static let findStarTitle = "Let’s try a virtual star!"
    static let findStarBody = "Follow the glowing arrow and move your phone to bring the star inside the circle."
    static let starLockedTitle = "Star locked!"
    static let starLockedBody = "You've got your star in sight! Tap anywhere on the screen to collect it."
    static let collectingTitle = "Collecting…"
    static let collectingBody = "Hold steady."
    static let practiceStarName = "Practice Star"
    static let practiceStarIdentificationNote = "Practice star from the Asterra tour. Not saved to your collection."
    static let wormholeCaption = "Collected! Watch it fly into your Sky Garden."
    static let noteEntryGuide = "Every discovery has a story. Write down yours below, then tap Done."
    static let starCardGuide = "This is your star's card: your note, photo, place and time. Tap ✕ to go back to the sky."
    static let gardenTitle = "This is your virtual Sky Garden"
    static let practiceGardenBody = "The stars you collect gather here. That one above is the practice star you just caught, now in your Sky Garden."
    static let gardenBody = "The stars you collect gather here. That one above is your latest discovery, now in your Sky Garden."

    static let landedTitle = "That's collecting"
    static let landedBody = "Every real star you collect stays in your Sky Garden. Tap the same button to go back there."

    static let landedWithoutCameraTitle = "That's collecting"
    static let landedWithoutCameraBody = "Every real star you collect stays in your Sky Garden, in its true place."

    static let landedSuccessTitle = "Back in your Sky Garden"
    static let landedSuccessBody = "Switch between the real sky and the Sky Garden anytime with that button."
    
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
    static let calendarGuide = "Use Calendar to browse by date. Tap a card for details or its bell to toggle a reminder."
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
