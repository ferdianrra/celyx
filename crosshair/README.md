# Crosshair for Xcode (SwiftUI)

Drop‑in implementation of the animated crosshair from Figma **PAI – Celyx › Crosshair** (node 922:1567).
It matches the live preview exactly: https://claude.ai/artifact/27QgvtUxUZaAF4LzwKtioe

Requirements: iOS 17+, SwiftUI. No dependencies.

## Setup (2 minutes)

1. Drag the **`Crosshair/`** folder into your Xcode project.
   In the dialog tick **Copy items if needed** and **your app target**.
2. Check that the 10 files in `Crosshair/Sounds/` are listed under
   *Target › Build Phases › Copy Bundle Resources* (Xcode does this automatically when the target is ticked).
3. Use it:

```swift
CrosshairView(state: crosshairState, label: star.name)
```

That's it. Change `crosshairState` and the crosshair animates there from wherever it is right now,
with the sound and haptic built in. You can change state at any time, even mid‑animation.

To try every state first, show `CrosshairDemoView()` (or open the `#Preview` in `CrosshairView.swift`).

## States

| `CrosshairState` | Figma variant | When to use it |
|---|---|---|
| `.default` | Property 1=Default | Nothing targeted |
| `.locking` | Property 1=Locking | A star is near the centre, lock in progress (loader runs) |
| `.enable` | Property 1=Enable | Locked on, star name shown, ready to collect |
| `.validating` | Property 1=Validating | Checking / collecting (faster loader) |

The order matters: moving forward (default → locking → enable → validating) turns the ticks clockwise,
moving back turns them counter‑clockwise.

## Options

```swift
CrosshairView(
    state: state,
    label: "Rigel",
    soundEnabled: true,      // SFX
    hapticsEnabled: true,    // Core Haptics (UIKit fallback on old devices)
    idleLoops: true,         // loader + idle tick life. false = static look
    scale: 1                 // 1 = Figma size. Use >1 to draw bigger without blur
)
```

* **Size and placement.** The view is a fixed `120 × 96 pt` canvas (`CrosshairView.size`).
  The reticle centre is at `CrosshairView.reticleCenter` = (60, 38); the label hangs below it.
  The reticle sits 10 pt above the view's own centre, so to put the reticle on a point `p` use
  `.position(x: p.x, y: p.y + 10)` (times `scale` if you scale it).
* **Reduce Motion** is read from the system automatically: 120 ms linear moves, no loader, no ping.
* **Audio session.** On first use it sets `AVAudioSession` to `.ambient` + `.mixWithOthers`
  (respects the silent switch, doesn't stop the user's music). If your app manages the session,
  set `CrosshairFeedback.shared.configuresAudioSession = false` before the first crosshair appears.
  Volume: `CrosshairFeedback.shared.volume` (0–1).
* **Haptics** fire on Acquire (soft tick), Lock (“ka‑chunk” double hit, synced to the arc closing at 190 ms)
  and Validate (light tap). Nothing fires on the way back.

## Files

| File | What it is |
|---|---|
| `Crosshair/CrosshairView.swift` | The SwiftUI view, the Canvas renderer and a demo view |
| `Crosshair/CrosshairMotion.swift` | State values, easing curves, the transition table and the animation engine |
| `Crosshair/CrosshairFeedback.swift` | Core Haptics patterns and sound playback |
| `Crosshair/Sounds/*.wav` | 10 short SFX (48 kHz mono) |
| `Reference/*.ahap` | The same haptic patterns as AHAP files, for designers / Haptics previewing. Not needed in the app |
| `tools/gen_sounds.py` | Re‑renders the WAVs (`python3 tools/gen_sounds.py Crosshair/Sounds`) |

## Tuning

Everything is in `CrosshairMotion.swift`:

* `CrosshairState.values`: per‑state geometry (from Figma).
* `CrosshairEase`: the curves (`flow`, `glide`, `settle`, `anticipate`, `exit`, loader head/tail).
* `CrosshairChoreography`: the transition table. Each track is `t(delay, duration, ease, stagger)` in ms,
  exactly as in the preview's spec tables.
* `CrosshairTuning`: loader speed, tick retract depth, squash, idle kicks, smear, ping.

## How it works (short)

One `Canvas` inside a `TimelineView(.animation)`. Each property (tick rotation/radius/width, ring scale,
colour, arc trim, label…) is a tween that always starts from its current on‑screen value, so states can
interrupt each other without jumps. The Locking/Validating loader is two trim paths (head and tail on
different curves) that chase each other; it fades in from the exact Figma frame (270° from 12 o'clock) and
is captured live when leaving the state. Ticks retract to a stub and fire out on every transition, squash
on Lock, kick outward when the loader head passes them, and ripple inward every 2.4 s in Enable.

Note: the view redraws every frame while on screen (that's what keeps the loader and idle life running).
If you show it in a place where it's always `.default`, you can pass `idleLoops: false`.

The sounds are good placeholders with the right timing. A sound designer can replace the WAVs
with the same file names at any time.
