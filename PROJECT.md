# Asterra

Asterra is a Swift and SwiftUI iPhone app for casual stargazing and collecting celestial objects. Users find objects through a live camera, save observations with photos and notes, and revisit them in a personal sky garden.

## Current behavior

- **Collect.** The native AVFoundation camera uses device orientation and location to align the sky. It scans for celestial objects and uses continuous autofocus on supported hardware. Tapping to focus moves the autofocus point. Overlays continue to follow a usable pose during motion blur, while new optical analysis waits for a clear frame.
- **Return to the garden.** A successful capture returns to the virtual garden, even when collection started from the live camera garden. The app places and focuses on the new object, reveals any new constellation lines or artwork, then returns to the current garden orientation before opening the note editor. A capture without a reveal has a shorter pause.
- **Explore the garden.** The virtual garden supports gyro and touch controls. Its sky shows collected objects and constellation artwork over the Milky Way backdrop. The live camera garden uses continuous autofocus and keeps projecting overlays through frames flagged for motion blur when the pose is usable. Rafi’s zodiac artwork, prepared on Stellarium’s reference canvases, appears after all required stars are collected and fades when the viewing angle would visibly stretch it.
- **Revisit and share.** Each object can be captured again. The garden opens a compact sheet that expands to show observation count, best Bortle class and a log of individual captures. The collection opens the sheet at full height. A capture detail shows its photo, note and conditions. The pencil enables inline note editing. Share offers two card layouts, Instagram Stories, Copy, Save and More. More exports a PNG with transparent corners and can reach WhatsApp through the iOS share sheet.
- **Learn the flow.** The daytime tour goes directly to a guided Sun placed from the current time and location. At night, the real-camera action appears before the virtual-star fallback. A prominent target arrow stays close to the capture reticle until the object approaches the lock area, and the first note editor opens with a descriptive, object-aware prompt instead of an extra instructional banner.
- **Review and collect sky events.** The Sky Calendar separates upcoming and ongoing events from dimmed past events for the selected month. During an event’s local viewing window, its detail page opens the live camera. A successful guided capture saves the photo, returns to the Garden, and opens the note editor. Both bodies in a conjunction open their own profiles, where the shared event capture appears alongside individual observations. The saved event is also accessible from **Your Collection → Sky event**.
- **Practice collecting an event.** In Debug builds, open **Sky Events → Demo** and choose **Single target** or **Moon–Jupiter conjunction**. The practice target is northeast, about 35° above the horizon. The conjunction shows two labeled targets and enables capture when both fit in the preview and their midpoint is near the reticle. Each demo type has its own observation log, and the conjunction places a Moon and Jupiter at their simulated directions in the Garden.
- **Demo constellations.** The Debug compass menu toggles missing pattern stars for all 12 zodiac constellations at their current sky positions. Completed patterns show their lines and figures in the garden without saving observations.
- **Exercise constellation completion.** The Debug-only collection demo uses real sky positions for Libra, Aries and Capricornus. It can seed missing Capricornus members up to nine of ten and add seven nearby stars.

## Verification

Shared conjunction history passed 15 unit tests and two UI tests on the iPhone 18 Pro simulator. The conjunction UI test opened the saved photo, note, location and light pollution from both body profiles.

Conjunction profile routing passed nine unit tests and two UI tests on the iPhone 18 Pro simulator. Moon and Jupiter opened their own profiles, and the conjunction observation log remained available in Sky Events.

Conjunction placement and handover passed 18 unit tests and two UI tests on the iPhone 18 Pro simulator. The conjunction UI test verified that the Moon and Jupiter labels both open the same event. The animated landing still needs a physical iPhone check.

Event observations passed 13 unit tests and four UI tests on the iPhone 18 Pro simulator. The Garden UI test uses a sample frame to verify arrival, note entry and reopening from Sky Events. Live alignment, camera frames and the animated landing still need a physical iPhone check.

Event calendar grouping, viewing-window and aim rules, and camera lifecycle passed 30 focused unit tests plus one UI test on the iPhone 18 Pro simulator. The UI test verified that an open event launches the guided camera. Live aiming still needs physical-device verification.

Merge validation against `dev` on November 18 passed all 20 focused garden capture and zodiac tests on the iPhone 18 Pro simulator. Three onboarding tests crashed during the merged run; the same tests also crashed on an untouched `dev` checkout. The shared project keeps `dev`'s app signing team.

The onboarding welcome uses the app's vector logo. Back navigation is available on intermediate tour steps, including the note sheet. The initial welcome, camera-switch step (including its ready confirmation) and completion card have no Back button; capture transitions finish before navigation resumes. Returning through the tour preserves collected observations.

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
