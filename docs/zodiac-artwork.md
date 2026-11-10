# Zodiac artwork

Garden figures load all twelve images from `Asterra/Assets.xcassets/constellation-figures`. The folder provides an asset namespace, so each runtime name begins with `constellation-figures/`.

| Constellation code | Image set | Current artwork |
| --- | --- | --- |
| Ari | aries-figure | Temporary Stellarium copy |
| Tau | taurus-figure | Temporary Stellarium copy |
| Gem | gemini-figure | Temporary Stellarium copy |
| Cnc | cancer-figure | Temporary Stellarium copy |
| Leo | leo-figure | Temporary Stellarium copy |
| Vir | virgo-figure | Temporary Stellarium copy |
| Lib | libra-figure | Temporary Stellarium copy |
| Sco | scorpio-figure | User artwork |
| Sgr | sagittarius-figure | Temporary Stellarium copy |
| Cap | capricon-figure | User artwork; existing asset spelling preserved |
| Aqr | aquarius-figure | Temporary Stellarium copy |
| Psc | pisces-figure | User artwork |

To replace a temporary image, open its existing image set in Xcode and replace the image while keeping the image-set name. Rebuild the app. No Swift changes are needed. Keep transparency and the same canvas aspect ratio/content layout to preserve its mapping. Pixel resolution can change: the original 512px canvases and current 2048px custom canvases use the same normalized coordinate system. Decoded artwork is capped at 512px and the glow is cached once, away from motion updates.

## Alignment

`Asterra/Resources/sky/zodiac-artwork.json` defines the asset name and three normalized anchor positions for each constellation. `[0, 0]` is the top-left of the image canvas; `[1, 1]` is the bottom-right. The three points correspond, in order, to the three sky anchors in that constellation's existing entry in `Resources/sky/figures.json`. Divide an anchor's image pixel coordinates by its canvas width and height to obtain these normalized values.

Initial anchor positions preserve the existing Stellarium mapping. The three custom drawings are now loaded, but their anatomical features have not been separately calibrated to specific stars. If a new drawing changes the pose, orientation, crop, or internal placement, adjust its three normalized anchors in the JSON; replacing only the image cannot automatically determine which star belongs to which feature. Use three distinct, non-collinear anchors. This mapping affects garden figures and the real-camera garden overlay; required collected stars and astronomical positions remain unchanged.

The nine temporary images are exact copies of the existing bundled files. Their original attribution is retained in `Asterra/Resources/LICENSES.md`. The old resource images are retained for other sky views; the garden no longer reads those files for artwork.
