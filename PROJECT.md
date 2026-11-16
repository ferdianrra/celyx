# Asterra

Asterra is a Swift and SwiftUI iPhone app for casual stargazing and collecting celestial objects. Users find objects through a live camera, save observations with photos and notes, and revisit them in a personal sky garden.

## Current behavior

- **Collect.** The native AVFoundation camera uses device orientation and location to align the sky. It scans for celestial objects and uses continuous autofocus on supported hardware. Tapping to focus moves the autofocus point.
- **Return to the garden.** A successful capture returns to the virtual garden, even when collection started from the live camera garden. The app places and focuses on the new object, reveals any new constellation lines or artwork, then returns to the current garden orientation before opening the note editor. A capture without a reveal has a shorter pause.
- **Explore the garden.** The virtual garden supports gyro and touch controls. The live camera garden uses continuous autofocus and keeps projecting overlays through frames flagged for motion blur when the pose is usable. Rafi’s zodiac artwork, prepared on Stellarium’s reference canvases, appears after all required stars are collected and fades when the viewing angle would visibly stretch it.
- **Revisit and share.** The observation sheet shows the photo, note and capture details. The pencil enables inline note editing. Share offers two card layouts, Instagram Stories, Copy, Save and More. More exports a PNG with transparent corners and can reach WhatsApp through the iOS share sheet.
- **Review sky events.** The Sky Calendar lists upcoming events and opens event details.
- **Demo constellations.** The Debug compass menu toggles missing pattern stars for all 12 zodiac constellations at their current sky positions. Completed patterns show their lines and figures in the garden without saving observations.
- **Exercise constellation completion.** The Debug-only collection demo uses real sky positions for Libra, Aries and Capricornus. It can seed missing Capricornus members up to nine of ten and add seven nearby stars.

## Verification

Merge integration repaired the camera autofocus option, restored the Debug constellation toggle and event collection panel alongside the guided Sun tutorial and camera recovery. Debug demo pattern IDs are cached to avoid repeated bundle decoding during live camera updates. The integration repair builds in Debug for the iOS simulator and Release for generic iOS with signing disabled. No unit tests were run for this repair; the test results below predate it. Autofocus, camera interruption recovery and demo smoothness still need physical-device validation.

The latest focused camera run passed 10 simulator tests covering capture geometry and lifecycle. Physical iPhone validation remains open for low-light autofocus, live sky alignment and recognition, and sharing to installed apps.

The compass menu toggle passed its UI test on the iPhone 18 Pro simulator. All 11 zodiac unit tests passed, including completion of all 12 demo figures and preservation of a saved Libra collection when the demo is turned off.

## Reference

- [Architecture and capture flow](docs/architecture.md)
- [Native camera pipeline](docs/native-sky-camera.md)
- [Zodiac artwork and anchors](docs/zodiac-artwork.md)
- [Social sharing](docs/social-sharing.md)
