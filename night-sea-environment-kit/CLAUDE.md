# Night Sea environment kit: brief for Claude

You are helping someone build on, restyle, or port the **Night Sea environment**: the real night sky for the viewer's place and time (stars, planets, Moon, Milky Way) seen from a calm sea ringed by island silhouettes. It is the background scene of a star-observation app prototype, shipped here **without** the app features (no labels, constellation lines, cards, collecting, boat, or UI).

Read this file first, then `web/env.js` and `shader/environment.frag.glsl`. Those two files hold all of the logic (about 30 KB together). **Don't read `web/stars.js` or `data/stars.json` in full**: they are 3,248 rows of star data (about 100 KB). Read the first lines if you need to see the format.

## Files

| Path | What it is | Edit it? |
|---|---|---|
| `night-sea-preview.html` | Everything in one file. Double-click to open, works offline. | No, it is generated |
| `web/index.html` | Page shell: two canvases, the hint pill, and the script tags | Yes |
| `web/env.js` | Astronomy, camera, star layer, WebGL setup, input, main loop. `CONFIG` at the top holds the knobs. | Yes |
| `shader/environment.frag.glsl` | The full-screen fragment shader: sky, Milky Way, islands, sea, reflections | Yes |
| `data/stars.json` | `[raHours, decDeg, magnitude, colourIndexBV, name]`, J2000, to magnitude 5.6 (HYG v3.8) | Yes |
| `data/milky-way-radec-4096.jpg` | Milky Way, equirectangular in RA/Dec: u = RA/360°, v = (90° − Dec)/180°. 4096×2048, gamma-encoded | Yes |
| `web/shader.js`, `web/stars.js`, `web/assets/` | Copies of the above wrapped for script tags | No, they are generated |
| `tools/build.py` | Regenerates the generated files and the single-file HTML | Run it after any edit |

After editing, run `python3 tools/build.py`. To run the multi-file version, serve `web/` over HTTP (`python3 -m http.server -d web 8000`, then open http://localhost:8000). Opening `web/index.html` straight from disk fails, because browsers block WebGL textures loaded from `file://`. The single file does not have this problem.

## How a frame is drawn

1. **Astronomy** (`computeSlow` once a second, `computeFast` every frame). Star catalogue positions are precessed from J2000 to today. Local sidereal time turns equatorial vectors into horizon vectors with `horizXf`. The Sun and Moon come from low-precision formulas, or from astronomy-engine when it loaded from the CDN, which also adds Venus, Mars, Jupiter, Saturn, and Mercury. Each star gets an *effective magnitude* `em`, dimmed by airmass (0.3 mag per airmass) and by moonlight near the Moon.
2. **Star layer** (`drawStars`, a 2D canvas that is never shown directly). Stars down to `CONFIG.starLimit` (6.2) are drawn coloured from B−V, with a glow for stars brighter than mag 3.4, small diffraction spikes for stars brighter than mag 1.2, and a slight twinkle. Planets are drawn as steady discs. The Moon is drawn with its real phase, the lit side turned toward the Sun.
3. **Environment shader** (one full-screen quad, WebGL 1). For each pixel it builds the view ray `d`:
   - **Sky** (`d.z ≥ 0`): a gradient from `uZen`/`uMid`/`uHor`, plus the Milky Way texture rotated to the current sky (`uE0..uE2`), plus the star layer, then three rings of procedural islands (`island()`: far dark, mid, near hazy) with lit and shadow flanks and a rim.
   - **Sea** (`d.z < 0`): four Gerstner-like wave trains give a surface normal. The shader reflects the sky with a Fresnel term, mirrors the star layer by sampling it at the reflected screen position, reflects the islands, and adds a Moon glitter road with sparkles. The far sea fades into the horizon colour. The last ~0.7° below the horizon blends into the colour directly above it, so there is no bright seam line.
4. **Camera**: a pinhole model with `foc = 0.62·min(W,H) / tan(fov/2)` and the optical centre at (W/2, 0.47·H). Drag, pinch, and the wheel change az, alt, and fov. On phones, the first tap asks for motion-sensor permission; after that the phone's orientation drives the view, and drag adds an offset.

## Conventions

- Directions are unit vectors **[east, north, up]**. Azimuth is measured from north toward east, altitude from the horizon. Angles in JS are degrees (`sin`, `cos`, and the other helpers take degrees). Angles in GLSL are radians.
- Time is the device clock in UTC milliseconds. The place is GPS if the viewer allows it, otherwise Jakarta (−6.2°, 106.85°).
- The scene is **always night**: `uSun` is pinned below the horizon. The twilight and Sun uniforms (`uGlow, uTw, uBelt, uDay, uSunI, uSunCol, uLow`) are kept but are zero. They are the starting point for a dusk mode.

## Knobs

`CONFIG` in `web/env.js`: `waves` (0.06 calm to 0.3 choppy), `islands`, `milkyWay` (strength), `starLimit`, `palette` (zenith/mid/horizon hex), `fov`, `useGPS`, `motion`, `place`. In the browser console, `NightSea.CONFIG` and `NightSea.state.view` can be changed live.

In the shader, island layout comes from `isl(az, n, heightDeg, seed)`. Each of the three rings has a cell count, a maximum height, and a seed. Changing the seed gives a different coastline. Sea colour is set by `sea=mix(...)`, wave trains by `ang`/`L`/`A`, and Milky Way brightness by `mwCol`.

## Porting notes

- **Three.js / React Three Fiber**: put the fragment shader on a full-screen `ShaderMaterial` (or a large inverted sphere with `d` = the world direction). Render the stars as `THREE.Points` into a `WebGLRenderTarget` and feed that in as `tStar`, instead of uploading a 2D canvas every frame.
- **iOS (SwiftUI + Metal)**: translate the GLSL to MSL almost line by line (`vec3`→`float3`, `mix`/`smoothstep` keep their names, `texture2D`→`tex.sample`). Draw the stars as point sprites into an offscreen texture. Use CoreMotion's `CMAttitudeReferenceFrame.xTrueNorthZVertical` in place of `deviceorientation`. For astronomy, keep these formulas or use a Swift port such as SwiftAA.
- **Unity**: an HLSL full-screen pass or skybox shader. Most of the GLSL maps across directly.
- **Performance**: it is a single full-screen pass. The heaviest parts are the three island layers, which are evaluated twice per sea pixel. On weak GPUs, cap the device pixel ratio (already capped at 2) or render the sea at half resolution.

## Known limits

- Looking straight down shows plain dark water. The original app had a boat there.
- Without astronomy-engine (offline), there are no planets and the Sun and Moon positions are a few tenths of a degree less exact.
- The island shapes are procedural and decorative, not a real coastline.

## Credits you must keep

The star data is HYG v3.8 (CC BY-SA 4.0), so credit it and keep derived star tables under the same licence. astronomy-engine is MIT. The Milky Way map, sky, sea, and islands were made for this project. See `LICENSES.md`.
