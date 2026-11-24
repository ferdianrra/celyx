# Asterra

Asterra is a Swift and SwiftUI iPhone app for casual stargazing and collecting celestial objects. Users find objects through a live camera, save observations with photos and notes, and revisit them in their Sky Garden.

## Current behavior

- **Collect.** The native AVFoundation camera uses device orientation and location to align the sky. It scans for celestial objects and uses continuous autofocus on supported hardware. Tapping to focus moves the autofocus point. Overlays continue to follow a usable pose during motion blur, while new optical analysis waits for a clear frame.
- **Return to the garden.** A successful capture returns to the virtual garden, even when collection started from the live camera garden. The app places and focuses on the new object, reveals any new constellation lines or artwork, then returns to the current garden orientation before opening the note editor. A capture without a reveal has a shorter pause.
- **Explore the garden.** The virtual garden supports Gyro and Touch from Direction options. The collect camera maps the sky automatically. Its sky shows collected objects and constellation artwork over the Milky Way backdrop. The live camera garden uses continuous autofocus and keeps projecting overlays through frames flagged for motion blur when the pose is usable. Rafi’s zodiac artwork, prepared on Stellarium’s reference canvases, appears after all required stars are collected and fades when the viewing angle would visibly stretch it.
- **Revisit and share.** Each object can be captured again. The garden opens a compact sheet that expands to show observation count, best Bortle class and a log of individual captures. The collection opens the sheet at full height. A capture detail shows its photo, note and conditions. The pencil enables inline note editing. Share offers two card layouts, Instagram Stories, Copy, Save and More. More exports a PNG with transparent corners and can reach WhatsApp through the iOS share sheet.
- **Learn the flow.** The daytime tour goes directly to a guided Sun placed from the current time and location. At night, the real-camera action appears before the virtual-star fallback. A prominent target arrow stays close to the capture reticle until the object approaches the lock area, and the first note editor opens with a descriptive, object-aware prompt instead of an extra instructional banner.
- **Star portraits.** Every sheet, card and page that shows a star (camera collect card, collection list, object sheets, album, zodiac book, calibration pickers, share card) draws it live with StarKit (`Asterra/Shared/StarKit`, Metal shader) from the catalog's B−V and a luminosity derived from magnitude and distance. Portraits use `StarTuning.asterra`: a wider, brighter corona, stronger breathing of corona and disk, soft diffraction spikes on a slightly smaller disk, and low granulation contrast so the surface reads as smooth photosphere rather than glassy cells. The Sun is drawn by StarKit as a G2V star with a brighter, warmer surface (reddened near the horizon). The Moon and planets use `PlanetView` (`Asterra/Shared/Planets`): the garden's equirectangular textures on a lit, slowly rotating sphere with an atmosphere rim for Venus, Mars and Jupiter; Saturn, which has no texture, gets procedural bands and rings. The Moon does not rotate. `stars.json` has no spectral type or variability, so every star uses StarKit's dwarf class and default pulse.
- **Zoom into the garden.** Pinching the virtual garden smoothly reaches a telescope-like 0.5° view (20× in gyro mode), and drags glide to a stop. Zoomed out in touch mode, the sky is drawn as a planetarium dome (stereographic projection). Stars keep their original colored glow and four-point spikes. The Sun, Moon and planets resolve into a live Sun, a textured Moon and planets with their real phase, and Saturn with rings. Object names fade out when zooming out.
- **Review sky events.** The Sky Calendar lists upcoming events and opens event details. Reminder bells ask for confirmation before enabling or disabling. Confirmed reminders are saved to iPhone Reminders with an alarm when viewing starts; disabling removes the saved reminder.
- **Constellations.** The Debug compass menu toggles missing pattern stars for all 12 zodiac constellations at their current sky positions. Completed patterns show their lines and figures in the garden without saving observations.
- **Practice collecting Sagittarius.** The Debug-only camera demo shows 25 Sagittarius pattern stars at their real sky positions. Demo captures use the normal save, shutter and garden handover flow, and the figure unlocks as its stars are collected.

## Verification

The restored Garden star rendering passed all eight `GardenZoomTests` on the iPhone 18 Pro simulator (iOS 27.0), including runtime Metal compilation and label fade thresholds. The older Garden zoom UI test stopped at its check for the Star Names menu item, which the current compass menu omits.

The Sky Garden copy passed all 17 onboarding unit tests and the UI test that checks the new title when returning to the first tour step on the iPhone 18 Pro simulator (iOS 27.2).

All 44 focused tests in `DemoSkyTests`, `CameraTargetSelectionTests`, `SkyCaptureLifecycleTests`, `GardenCaptureSequenceTests` and `GardenZodiacTests` passed on the iPhone 18 Pro simulator (iOS 27.2). Live aiming responsiveness, overlay alignment and shutter timing still need physical-device verification.

Sky event reminder integration builds for the iPhone 18 Pro simulator (iOS 27.2). All six reminder unit tests and the UI test covering enable/disable confirmation and cancellation from both list and detail passed. The broader 14-test feature view-model run passed 13 and failed `touchCanExploreBelowTheHorizon` in garden motion code outside this change. Real Reminders permission, saved-item visibility, removal and timed alarm delivery still need physical iPhone validation.

The app icon now uses only the updated PNG catalog, with the legacy Icon Composer source archived outside the app target. The welcome tour uses the same updated artwork. The Debug build for generic iOS Simulator passed; compiled assets contain the PNG welcome logo and no legacy layered icon records. No unit or UI tests were run for this asset change, and the installed Home Screen icon has not been checked on a physical device.

Sky Events expiry coverage passed with all 14 feature view-model tests and the focused List/Calendar UI test on the iPhone 18 Pro simulator (iOS 27.2).

The simplified Direction options menu passed its UI test on the iPhone 18 Pro simulator (iOS 27.2). All 71 selected tests across camera alignment, pattern matching, capture lifecycle, feature view models and optical recognition passed. Physical sky alignment remains to be checked.

The Sky Events List/Calendar picker and first-visit tip passed the focused UI test on an iPhone 18 Pro simulator (iOS 27.2). All 14 feature view-model tests passed.

Merge validation against `dev` on November 18 passed all 20 focused garden capture and zodiac tests on the iPhone 18 Pro simulator. Three onboarding tests crashed during the merged run; the same tests also crashed on an untouched `dev` checkout. The shared project keeps `dev`'s app signing team.

The onboarding welcome uses the updated app icon artwork. Back navigation is available on intermediate tour steps, including the note sheet. The camera-switch step hides the main toolbar and shows Back and Skip Tour. The initial welcome and completion card have no Back button; capture transitions finish before navigation resumes. Returning through the tour preserves collected observations.

The object-aware onboarding CTA order, guided-Sun copy, compact note entry and near-reticle target arrow build in Debug for the iOS simulator. No unit or UI tests were run for this presentation pass.

Camera Back now requests immediate dismissal; preview attachment/detachment runs on the capture worker alongside session operations. This change was built for the simulator without running unit tests. Physical-device Back latency remains to be checked.

Merge integration repaired the camera autofocus option, restored the Debug constellation toggle and event collection panel alongside the guided Sun tutorial and camera recovery. Debug demo pattern IDs are cached to avoid repeated bundle decoding during live camera updates. The integration repair builds in Debug for the iOS simulator and Release for generic iOS with signing disabled. No unit tests were run for this repair; the test results below predate it. Autofocus, camera interruption recovery and demo smoothness still need physical-device validation.

The latest focused camera run passed 10 simulator tests covering capture geometry and lifecycle. Physical iPhone validation remains open for low-light autofocus, live sky alignment and recognition, and sharing to installed apps.

The compass menu toggle passed its UI test on the iPhone 18 Pro simulator. All 11 zodiac unit tests passed, including completion of all 12 demo figures and preservation of a saved Libra collection when the demo is turned off.

## Reference

- [Architecture and capture flow](docs/architecture.md)
- [Native camera pipeline](docs/native-sky-camera.md)
- [Zodiac artwork and anchors](docs/zodiac-artwork.md)
- [Social sharing](docs/social-sharing.md)
- [Sky event reminders](docs/sky-event-reminders.md)
