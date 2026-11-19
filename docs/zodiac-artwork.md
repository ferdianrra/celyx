# Zodiac artwork

The virtual garden and live camera garden load the prepared Rafi PNGs from `Asterra/Assets.xcassets/constellation-figures-rafi-aligned`. The source drawings are in `constellation-figures-rafi`. The file `Asterra/Resources/sky/zodiac-artwork.json` maps each constellation code to its prepared image set.

Each prepared PNG uses rotation, uniform scale and translation to place three catalog stars on recognizable parts of the drawing. Transparent padding keeps the complete silhouette in frame. The `referenceCanvas` entry describes the original Stellarium square inside the 1024px PNG, using a normalized top left offset and a uniform scale. The garden still projects the same original sky coordinates. The `alignmentStarIDs` are the catalog stars chosen to align the artwork.

| Figure | Landmark matches |
| --- | --- |
| Aries | Bharani on the back, Hamal on the chest, Sheratan at the front leg |
| Taurus | Elnath and Tianguan at the horn tips, Aldebaran on the face |
| Gemini | Pollux and Castor at the twins’ heads, Propus at the raised foot |
| Cancer | Acubens and Iota Cancri at the claws, Asellus Australis on the shell |
| Leo | Denebola at the tail tuft, Zosma on the back, Regulus at the base of the foreleg |
| Virgo | Nu Virginis at the head, 109 Virginis at a foot, Tau Virginis on the lower garment |
| Libra | Zubeneschamali and Brachium at the suspension points, Upsilon Librae at the second pan’s rigging |
| Scorpius | Acrab at the claw, Shaula at the stinger, Sargas at the tail bend |
| Sagittarius | Nunki on the archer’s torso, Ascella at the waist, Kaus Australis where the lower bow meets the raised foreleg |
| Capricornus | Deneb Algedi at the tail curl, Algedi at the horn, Omega Capricorni at the bent hoof |
| Aquarius | Sadalmelik on the jug, Sadalsuud at the shoulder, Albali at the hand holding the staff |
| Pisces | Catalog star 933 and Gamma Piscium at the two fish, Alrescha at the knot |

Aries, Leo, Sagittarius and Aquarius were fitted against the supplied reference images using the full plotted star pattern. The table lists the three highlighted stars for each figure.

## Adjust a figure in an image editor

1. Find the constellation in `Asterra/Resources/sky/figures.json` and open its reference PNG from `Asterra/Resources/sky/figures`. Use that image as the template for the full canvas, including transparent margins.
2. Add guides at the three reference anchor pixels, measured from the upper left. If working at 1024 × 1024, multiply the original pixel coordinates by 2 for a 512px reference or by 4 for a 256px reference.
3. Place the original Rafi drawing on a separate layer. Move, rotate and scale it until recognizable features line up with the guides. Zoom out and check the entire silhouette for clipping. For a different pose, prioritize the landmarks that make the drawing easiest to read.
4. Hide the reference and guides, then export the full transparent canvas into the matching image set under `constellation-figures-rafi-aligned`. Keep the image-set name and export with transparent margins intact. Preserve the reference square's position and size inside the padded canvas. The existing `Capriconous` and `Sagitarius` spellings are part of the asset names.

In a Debug build, tap the compass and turn on **Constellations**. The garden fills in missing pattern stars for all 12 zodiac figures using their current positions. Lines and artwork appear through the usual garden completion rules as you look around the virtual or live sky. Some constellations may be below the horizon. Turn the toggle off to clear the temporary stars and return to your saved collection.

As you look away from a figure, the garden compares its projected shape with the centered view and fades the artwork before the change in proportions becomes pronounced. The stars and lines stay in place.

The garden decodes and reduces each image to at most 512px on its longest side and caches the glow away from motion updates. Other sky views still use the bundled Stellarium figures. Attribution is in `Asterra/Resources/LICENSES.md`.
