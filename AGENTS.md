# Working on Asterra

- Read [PROJECT.md](PROJECT.md) for current behavior and verification status. Consult [the architecture notes](docs/architecture.md) and the relevant feature documentation before changing a workflow.
- Use `Asterra.xcodeproj` and the `Asterra` scheme. App source is in `Asterra/`, unit tests in `AsterraTests/`, and UI tests in `AsterraUITests/`.
- Follow the existing feature boundaries. Views own SwiftUI presentation and navigation, view models own feature state, and services own hardware access, analysis and persistence. Reuse existing components and preserve catalog IDs, persisted keys and compatibility with saved observations.
- Use native SwiftUI controls where they fit. Keep the published capture sequence and existing Reduce Motion behavior in mind when changing the garden, capture animation or observation sheets.
- Keep image decoding and other expensive work out of per-frame camera and gyro paths. Review projection changes in both virtual and live camera modes.
- Keep demo collection behavior scoped to Debug builds. Document user-visible workflow and architecture changes in the relevant file under `docs/` and update [PROJECT.md](PROJECT.md) when the project status changes.

## Build and test

List destinations and use an available iOS simulator for focused tests.

```sh
xcodebuild -project Asterra.xcodeproj -scheme Asterra -showdestinations
xcodebuild -project Asterra.xcodeproj -scheme Asterra \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -only-testing:AsterraTests/SkyCaptureLifecycleTests test
```

Report which tests ran and distinguish simulator results from physical-device checks. Lens focus, live sky alignment, motion smoothness and third-party share handoffs require hardware or receiving-app validation.
