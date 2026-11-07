# Ready-to-paste prompts

Use these after giving Claude the kit (see START-HERE.md). Writing them in Indonesian works just as well.

## 1. Get oriented
> Read CLAUDE.md, then web/env.js and shader/environment.frag.glsl. Explain in plain language how this night-sea scene is drawn, which settings change the look the most, and what I'd need to do to use it in my own project. Don't change anything yet.

## 2. Tweak the look
> Using CLAUDE.md as the guide, change the environment so that [the sea is calmer / there are more islands / the sky is a deeper blue / the Milky Way is stronger]. Edit only web/env.js (CONFIG) or shader/environment.frag.glsl, run `python3 tools/build.py`, and tell me what you changed and why.

## 3. Use it on a website (Three.js / React)
> Read CLAUDE.md. Port this environment into a [React + Three.js / plain Three.js] component that fills its container, keeps the same look, and accepts props for lat, lon, waves and islands. Follow the "Porting notes" section: render stars as THREE.Points into a render target instead of a 2D canvas. Keep the HYG credit.

## 4. Use it in an iPhone app (SwiftUI + Metal)
> Read CLAUDE.md, web/env.js and shader/environment.frag.glsl. Port this environment to a SwiftUI view backed by MetalKit: translate the shader to Metal, draw stars as point sprites into an offscreen texture, use CoreMotion (xTrueNorthZVertical) for looking around and CoreLocation for the place. Keep the same coordinate conventions. Start with a plan, then build it step by step.

## 5. Add something to the scene
> Read CLAUDE.md. Add [a dusk mode where the Sun is just below the horizon / a lighthouse on one island / shooting stars], reusing the existing uniforms where possible (the twilight uniforms are already in the shader at zero). Keep the default look unchanged when the new option is off.
