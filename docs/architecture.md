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
- `StarCollectViewModel` owns target selection, capture verification, feedback and saving observations. `SkyFinderService` owns live camera analysis, matching and retained camera frames.
- `EventCollectionViewModel` owns the existing event-camera prototype state; it does not turn that prototype into real event detection.
- `SkyCalendarViewModel` owns date navigation and shared filtering rules for the list and month grid. `SkyEventStore` owns reminder and collected-event persistence.
- `SkyCalibrationViewModel` owns target selection, sensor samples, reference validation and saved corrections. The calibration service and pattern solver remain separate.

Views keep layout, gestures, sheets and navigation bindings. Models do not own screen layout. Services handle device APIs, image processing and persistence. Changes to folder structure do not change resource names, stored keys or catalog IDs.
