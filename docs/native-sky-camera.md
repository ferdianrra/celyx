# Native sky camera

Collection, calibration and garden camera previews use AVFoundation, not ARKit. `SkyCaptureSession` owns the capture worker and publishes image/pose packets to the main actor. Camera setup, motion history and video callbacks are serialized away from the UI. At most one delivered frame waits on the main actor, and the detector keeps one analysis task in flight.

## Capture and geometry

The physical back wide camera captures native, unrotated 1080p YUV frames. Video stabilization is disabled so measured image intrinsics describe the analyzed pixels. Intrinsic matrix delivery is required; the app does not silently guess a field of view. Preview uses AVCaptureVideoPreviewLayer with aspect fill. Projection, digital zoom, taps and photos use the same orientation and center crop.

Core Motion provides true-north device orientation at 100 Hz. Video presentation timestamps are converted from the capture synchronization clock to host time, then matched/interpolated against a bounded motion history. World axes are east/up/south, preserving the astronomical calibration convention. Portrait and landscape rotations are applied explicitly. Translation is not estimated: celestial directions do not require room-scale position tracking.

Auto exposure may use 10–30 fps where the active format supports it, with an exposure ceiling bounded by that format and frame duration. Focus starts locked at the far lens position. Low-light boost is enabled where supported. This is a streaming camera configuration, not a promise of the stock Camera app's Night mode processing. The detector pauses during estimated exposure motion blur, without invalidating calibration merely because the phone moved.

## Detection and identification

The existing local-contrast point detector and foreground-context filter are retained. Roof/window edges, broad illuminated halos, extended discs and single hot pixels are screened by the existing optical checks. The calibration pipeline now applies the same foreground-context filter.

`CameraPointStack` aligns native-resolution patches with measured intrinsics and sensor rotation. It combines up to eight frames with a trimmed mean, discarding the highest and lowest value at each pixel. A stacked source still needs support in independent raw frames; overlapping averages do not count as independent sightings.

A single stable optical point can suggest a star or planet without waiting for a pattern. Suggestions require a current heading accuracy of 15 degrees or better, bounded angular separation, compatible altitude, and an unambiguous catalog match. A best match becomes eligible for collection after three independent, consistent candidate observations spanning at least 0.4 seconds, on top of the existing optical persistence requirement. The main camera then shows a green crosshair, the object name, a green Collect pill below it, and a blue/black information card at the bottom. Ambiguous matches continue scanning automatically without opening a chooser or asking for manual detection. These matches do not change sky alignment; the observation metadata retains the uncalibrated estimate provenance. A manual reference picker remains available to the separate calibration workflow, including planet ephemerides. Automatic alignment still needs the unique four-star pattern plus repeated consensus; a user-confirmed single star or planet is an alternative. After alignment, catalog matching is limited to 0.5 degrees. Ordinary tracked sources need at least four observations spanning 0.6 seconds before a suggestion or confirmed name is displayed; pin confirmation and fresh observations gate collection. A stored name alone cannot renew collection support after a contradictory match.

Vision and Core ML are not added: no star-specific model or measured improvement is available in this repository. A general tracker does not establish celestial identity. AR scene feature-point proximity checks have been removed because this camera pipeline does not produce depth or a world map.

## Following a detected light

Acquisition accepts a source within 96 screen points of the aim, rather than requiring a 28-point bullseye. One optical sighting starts following; repeated independent sightings still support naming. The selected source is updated anywhere it remains visible, using optical identity before distance to the reticle. A new central light replaces it after repeated support and a clear advantage in distance to the aim; brightness does not decide target selection. Scanning retains the last measured target while the phone remains within 20 degrees of the aim at its last sighting, even through a longer gap. It switches when another repeatedly observed point is within 48 screen points of center and at least 12 points closer than the held source. This allows a faint centered star to replace a brighter neighbor without forcing the bright star out of view. A large turn abandons the old scan. The five-second retained-photo offer and fresh capture timestamps remain separate from this scan memory.

Native-resolution analysis covers both the aim and the projected selected source on every pass. Wide discovery uses an Accelerate-scaled overview capped at 960 pixels, once per second. This keeps expensive full-frame searches from repeatedly delaying or resetting the target. Tracks tolerate up to 1.5 seconds between analysis observations. An analyzed result can be consumed for up to two seconds, but retains its original capture timestamp so slow processing cannot manufacture fresh capture evidence.

The local point detector's flood-fill radius covers mildly widened star/planet cores. A reconstructed luminance profile from the submitted screenshot (excluding reticle graphics) is tested at all nine pixel-grid phases; this catches the old position-dependent rejection of the same visible light.

## Screenshot and background lifecycle

Taking a screenshot and brief inactive overlays do not stop capture or invalidate calibration. Actual background entry stops capture and invalidates the reference. On return, a paused native session is restarted even if the service retained a running flag; a recent measured location can be reused while GPS updates resume.

Native camera notifications are delivered asynchronously to the UI actor, avoiding a synchronous main-queue wait while AVFoundation holds camera locks during start/stop. Control restoration uses the capture queue instead of locking the device on the UI thread. Lifecycle tests use an injected driver to check stale frame rejection, delivery-slot release, background/resume and notification lock ordering without requiring a real camera.

## Validation and limits

Automated tests exercise projection/pixel agreement in all four orientations and several zoom levels, cardinal sensor axes, crop transforms, optical persistence, candidate confirmation, noise/hot-pixel/flash/halo rejection, stacking and pattern matching.

Physical-device validation remains necessary. On the same phone and sky, record the number of detected real stars, false identities, time to identification, overlay error after panning/rotation/zoom, and heat/frame rate. Include dim stars, streetlights, distant isolated lamps, building windows, moving lights, compass interference, permission denial, camera interruption and background/resume.

A distant point-like lamp exactly aligned with a catalog star cannot always be distinguished from that star by one monocular observation. A manual reference can also be wrong. Stricter gates reduce false naming at the cost of withholding uncertain names; synthetic tests do not establish real-world recognition accuracy or sensitivity gains.

## Verification recorded for this migration

- Debug builds succeeded for both the iOS simulator and generic iOS device with code signing disabled.
- The focused camera/recognition selection passed 76 tests (geometry, identity, optical detection, stacking, sky context, exposure gestures, pattern matching and capture enhancement).
- The full unit suite reported seven failing test names outside the migrated camera pipeline. All seven also failed in a separate checkout of the original HEAD using the same project settings and simulator. They concern constellation rendering, magnitude/zoom behavior, search/collection metadata and garden transitions. Baseline animation tests also showed timing sensitivity.
- No physical camera, real sky accuracy, faint-star sensitivity, battery or thermal measurements were performed here.

## Single-object and screenshot fix verification

- 88 selected tests passed, including single-star/planet proposals, live Jupiter reference coordinates, ambiguous/invalid direction rejection, native sensor axis orientation, screenshot inactivity, pause/resume, stale callback release, notification lock ordering, pattern matching and the merged demo/garden constellation tests.
- Debug simulator tests and the generic iOS Release build succeeded with signing disabled.
- Single-point names remain estimates until the observer confirms a reference; physical-device sky recognition and screenshot-editor recovery still need field verification.

## Following-target fix verification

- 100 selected tests passed, including the reconstructed visible-light profile at all nine scan-grid phases, off-center acquisition and continuation, deliberate source switching, scan memory versus fresh photo evidence, bounded overview coordinates, single-object naming, sensor geometry, screenshot lifecycle, and noise/hot-pixel/halo rejection.
- The generic iOS Release build succeeded with signing disabled.
- The screenshot profile is a reconstruction of the compact light, excluding UI marks; it is not an original sensor frame. Actual on-device sky sensitivity and hand-motion behavior still require physical-device testing.

## Automatic collection flow

`CameraAutomaticIdentification` keeps source ID, candidate consistency and actual optical timestamps separate from global calibration. Duplicate render frames cannot establish an identity; source/name changes, ambiguity and long observation gaps restart consensus. A fresh stable match can expose an annotation and retain a real captured photo, including for planets. Cached automatic photos are hidden after contradictory evidence or a source switch. Raw capture still checks fresh optical support; the retained-photo path preserves its original image and observation context.

A real retained capture keeps the automatic Collect offer available for up to five seconds after its last supported observation, including while the source moves out of the camera view. Contradictory evidence or a source switch withdraws that offer. The information card stays at the bottom. A single green “Collect <name>” pill follows the locked crosshair, matching the object discovery reference; tapping the stationary card or preview also collects the ready object. Detection and catalog matching run automatically. The camera does not present Choose, Confirm or Detect buttons during scanning, and single-object estimates are not used to recalibrate other objects.

## Faint neighbor and motion continuity

Motion-aligned stacking tolerates up to six degrees of rotation before resetting its reference patch; out-of-bounds warps, large turns and missing temporal support still reset or reject the stack. Tests verify that a faint point remains detectable alongside a much brighter neighbor, and that several degrees of compensated motion preserve accumulation. Scan progress and an established name survive a geometrically consistent re-sighting with a new optical ID, but new pixels are still required for a fresh observation. Simultaneously visible points never share an identity merely because their rays are close at high zoom.

The source marker suppresses its scanning text and spinner while acquisition is in progress. The single scanning status remains at the bottom; ready object names and the bottom information card remain available after identification.

## Latest verification

113 selected tests passed after the automatic Collect and faint-neighbor continuity changes. They cover stable best-match decisions, retained capture/source identity, duplicate observations, faint and bright points together, near-center target switching at small separations, angular scan retention, compensated rotation, UI rendering without the redundant scanning label, noise rejection and merged demo/garden behavior. The generic iOS Release build also succeeded with signing disabled. These are synthetic and simulator checks; actual sky/phone sensitivity remains unmeasured here.

## Solar-disc collection

Resolved discs use a dedicated Sun/Moon path, including in daylight and without manual calibration. Native disc detection runs on every analysis pass when the Sun or Moon is up. Measured disc bounds exclude its own bright rim from foreground-texture rejection. Discs take precedence over duplicate compact peaks; a matched disc near the aim can replace an unclassified lens-flare point. Large rectangular patches are rejected.

Disc identity requires a matching above-horizon ephemeris, altitude agreement within four degrees, a bounded angular separation using compass accuracy (three degrees after reference alignment), and the same independent temporal consensus as single-point identification. Compact points cannot acquire a solar-disc identity. This path offers the actual recognized photo for collection and does not use its estimate to recalibrate the sky.

Solar-disc follow-up validation: 116 selected tests in 16 suites passed, including daytime disc extraction/context, Sun and Moon naming with and without reference alignment, temporal collection eligibility, wrong-direction/compact flare rejection, rectangular light rejection, and reference information-card rendering. Physical-device sky testing is still required.

## Sun next to illuminated clouds

The reported daytime image is retained as a camera-only crop in `celyxTests/Fixtures/sun-beside-cloud.png`. The previous single-threshold detector failed to locate its solar center, instead returning cloud fragments. Simply adding higher thresholds also failed because saturated cloud edges still touched the solar core.

Disc extraction now inspects several luminance levels and uses distance-to-boundary maxima to separate round bright cores from connected cloud rims. A split core needs a darker exterior around most of its circumference. Daylight requires a bright local core in the correct full/video luminance range, so a dim lens-flare bloom cannot inherit the peak brightness of a connected cloud component. Broad cores rank above tiny cloud highlights. Solar acquisition retains the disc's measured size and prefers the resolved core within the 160-point aim neighborhood, rather than a closer small highlight.

Ordinary point-source identification is disabled when solar altitude is at or above -6 degrees, or unavailable. This applies before target selection, at single-point naming, and to automatic/retained collection offers; stale ordinary-star tracks and captures are cleared. Thus a daytime flare cannot become an ordinary catalog star such as the reported Star 1028. Sun/Moon identification continues to require ephemeris agreement and independent optical observations.

Validation: the reported image failed before the change and passes afterward in full-range and video-range luminance, in both native image orientations. 119 selected tests in 16 suites pass, including dim-neighbor tracking, solar target selection, cloud/flare rejection, identity persistence, capture geometry and lifecycle. Generic iOS Release builds with signing disabled. A screenshot validates optical extraction but cannot reproduce the original phone's location/compass stream; live-device verification remains outstanding.

Ready-state presentation now uses the recognized target immediately. The extra 0.7-second UI lock and intermediate “Ready to collect” labels are removed; optical/identity consensus still runs before recognition. The green Collect pill and object information card appear together as soon as a target becomes available.

## Small solar cores through thin cloud

A camera-only 52-pixel crop of the next reported screenshot is retained as `sun-through-cloud.png`. Tests place the original screenshot pixels in a camera-sized sky image to exclude the UI reticle while preserving the small core and its immediate cloud surroundings. Before the fix, the point-source context veto rejected the resolved solar core in all four full/video-range and rotation cases; video-range centroid extraction also drifted into the halo.

Disc luminance is now normalized from video range (16–235) into the same scale as full-range input. Thresholds follow the measured peak, and the daylight core floor adapts to scene contrast with an absolute lower bound. This allows attenuated cores without requiring clipped white. Partial daylight discs can supply a smaller inscribed core; nighttime point-source detection is unchanged.

A shape-validated optical disc is exempt from the point-source texture veto, since cloud rims and scattering around the Sun are valid sky. Rectangular-light rejection remains in disc extraction. Every disc still needs above-horizon solar ephemeris agreement, heading/altitude bounds, and independent temporal consensus before collection. A fully hidden Sun does not get a new optical observation from its predicted position.

Validation: 122 selected tests in 16 suites pass. The small reported core is checked across nine sampling-grid positions, two luminance ranges and two transmission levels (36 combinations). Synthetic partial occlusion, flat cloud, isolated hot pixels, rectangular lights, ephemeris mismatch and the earlier sun-beside-cloud regression also pass. Generic iOS Release build succeeds with signing disabled. These checks cover image extraction and policy behavior; the original live camera/compass stream remains unavailable for device validation.
