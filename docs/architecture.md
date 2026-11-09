# Project structure

Features are grouped by the screen or workflow they own. There is no extra application-name folder under `Features`.

```text
celyx/
  Features/
    Home/         Main screen, navigation, observation settings and astronomy state
    Garden/       Collected-object sky, collection lists, albums and story export
    Events/       Event data, reminder persistence, calendar and event details
    Sky/          Camera collection, detection, prediction overlays and photo processing
    Calibration/  Reference selection, star-pattern matching and alignment
  Shared/
    Style/        Colors, panels, reusable controls and hints
    Crosshair/    Crosshair view, animation model, feedback service and sounds
```

Each feature uses `Models`, `Views`, `ViewModels`, and `Services` as needed. Garden and Home also have `Rendering` for Metal implementations. Small presentation-only components do not need a separate view model.

- `HomeView` composes the main screen using the existing `HomeViewModel` for observation settings and collection data.
- `GardenViewModel` owns object placement, sensor lifecycle and camera gestures.
- Garden constellation connections use the bundled figure edges and require both neighboring endpoints to be collected. No line is drawn to uncollected stars or arbitrary nearby objects. Existing connections remain on relaunch; new connections draw subtly toward the newly collected star over 0.9 seconds after its handover album closes. The virtual sky and live camera use their existing projection for each endpoint, and deletion removes the corresponding edges. Reduce Motion displays new connections immediately.
- Constellation threads have a soft blue-white halo and a fine luminous core. Every connected star has a staggered five-second timer and sends a gentle 2.4-second light sweep toward one collected neighbor, rotating among its connections. At most two sweeps run at once, and an edge never carries overlapping sweeps. Busy timers wait fairly for a free slot, so five seconds is the minimum start-to-start interval for a star rather than a strict global cadence. The animation timeline pauses between sweeps, and inactive gardens or Reduce Motion disable the ambient sweep entirely.
- Ambient sweeps activate only for connection lines that intersect the current frame, including partially visible segments. Offscreen constellations do not consume animation slots; looking away stops their sweeps, and looking back starts their staggered timers again. This visibility rule follows the existing virtual or AR camera projection.
- Garden gyro tracking follows true north without touch offsets. A swipe preserves the current direction and zoom, then switches to touch; motion tracking continues quietly in the background. After a swipe, changing the phone’s aim by at least 5° while pointing near the horizon (−8°) or above resumes gyro after a brief 0.15-second debounce. Lowering the phone first is unnecessary. Small hand tremors and screen-axis roll do not trigger it; movement during a drag or pinch resets the reference so the gesture keeps control. The direction menu can also select either mode. GPS/compass readiness still gates real-world tracking, without displaying setup progress or calibration prompts in the garden.
- `StarCollectViewModel` owns target selection, capture verification, feedback and saving observations. `SkyFinderService` owns live camera analysis, matching and retained camera frames.
- `EventCollectionViewModel` owns the existing event-camera prototype state; it does not turn that prototype into real event detection.
- `SkyCalendarViewModel` owns date navigation and shared filtering rules for the list and month grid. `SkyEventStore` owns reminder and collected-event persistence.
- `SkyCalibrationViewModel` owns target selection, sensor samples, reference validation and saved corrections. The calibration service and pattern solver remain separate.

Views keep layout, gestures, sheets and navigation bindings. Models do not own screen layout. Services handle device APIs, image processing and persistence. Changes to folder structure do not change resource names, stored keys or catalog IDs.

The DEBUG collection demo is toggled by long-pressing the camera preview in Start Collecting. It makes the six Libra and four Aries stars referenced by the bundled constellation line patterns collectible without optical detection, including stars below the horizon. Positions use the same HYG catalog, Astronomy Engine snapshot, refraction and camera alignment as the real sky; observing time and the live GPS fix are refreshed continuously. Stars are never recentered around the phone or lifted above the horizon: aim downward to collect one whose real position is below it. No coordinates or camera frame are fabricated if location or tracking is unavailable. Captures retain their real observation date/location and note that the star overlay was generated and optical verification bypassed. Already collected stars are dimmed and cannot be collected again. The shutter, wormhole and album use real astronomical placement, including the Reduce Motion alternative. No constellation animation is added yet.
