# Native sky camera

Collection, calibration and garden camera previews use AVFoundation, not ARKit. `SkyCaptureSession` owns the capture worker and publishes image/pose packets to the main actor. Camera setup, motion history and video callbacks are serialized away from the UI. At most one delivered frame waits on the main actor, and the detector keeps one analysis task in flight.

## Capture and geometry

The physical back wide camera captures native, unrotated 1080p YUV frames. Video stabilization is disabled so measured image intrinsics describe the analyzed pixels. Intrinsic matrix delivery is required; the app does not silently guess a field of view. Preview uses AVCaptureVideoPreviewLayer with aspect fill. Projection, digital zoom, taps and photos use the same orientation and center crop.

Core Motion provides true-north device orientation at 100 Hz. Video presentation timestamps are converted from the capture synchronization clock to host time, then matched/interpolated against a bounded motion history. World axes are east/up/south, preserving the astronomical calibration convention. Portrait and landscape rotations are applied explicitly. Translation is not estimated: celestial directions do not require room-scale position tracking.

Auto exposure may use 10–30 fps where the active format supports it, with an exposure ceiling bounded by that format and frame duration. Focus starts locked at the far lens position. Low-light boost is enabled where supported. This is a streaming camera configuration, not a promise of the stock Camera app's Night mode processing. The detector pauses during estimated exposure motion blur, without invalidating calibration merely because the phone moved.

## Detection and identification

The existing local-contrast point detector and foreground-context filter are retained. Roof/window edges, broad illuminated halos, extended discs and single hot pixels are screened by the existing optical checks. The calibration pipeline now applies the same foreground-context filter.

`CameraPointStack` aligns native-resolution patches with measured intrinsics and sensor rotation. It combines up to eight frames with a trimmed mean, discarding the highest and lowest value at each pixel. A stacked source still needs support in independent raw frames; overlapping averages do not count as independent sightings.

A single stable optical point can suggest a star or planet without waiting for a pattern. Suggestions require a current heading accuracy of 15 degrees or better, bounded angular separation, compatible altitude, and an unambiguous catalog match. They are labeled “Likely” / “Estimated identity” and do not silently unlock collection or change alignment. A visible confirmation button opens the reference picker, which includes live planet ephemerides as well as stars. Automatic alignment still needs the unique four-star pattern plus repeated consensus; a user-confirmed single star or planet is an alternative. After alignment, catalog matching is limited to 0.5 degrees. Ordinary tracked sources need at least four observations spanning 0.6 seconds before a suggestion or confirmed name is displayed; pin confirmation and fresh observations gate collection. A stored name alone cannot renew collection support after a contradictory match.

Vision and Core ML are not added: no star-specific model or measured improvement is available in this repository. A general tracker does not establish celestial identity. AR scene feature-point proximity checks have been removed because this camera pipeline does not produce depth or a world map.

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
