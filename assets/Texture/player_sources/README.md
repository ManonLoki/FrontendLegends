# Player sprite sources

The two character sheets were generated with the built-in image generation tool,
then chroma-keyed and normalized by `tools/build_player_spritesheet.py`.

- `rabbit_male_chroma.png`: generated male rabbit sheet on green.
- `rabbit_male_rgba.png`: transparent source used by the builder.
- `succubus_female_chroma.png`: generated female succubus sheet on green.
- `succubus_female_rgba.png`: transparent source used by the builder.
- Sheet layout: 4 columns × 4 rows; down, left, right, up; four walk frames.

## Final prompt — rabbit man

Create a consistent pixel-art top-down RPG walk-cycle sheet based on the supplied
white rabbit man. Preserve his white rabbit body, long upright pink-lined ears,
round pale human-like face, tired eyes, nose and deadpan mouth. Facial identity is
an invariant. Use exactly four columns and four rows: down, left, right and up;
four seamless contact/passing walk frames per row. Keep body center and foot
baseline fixed, with equal padding and no overlap. Use crisp limited-palette
16-bit RPG pixel art readable around 32×40 pixels. Render only one full character
per cell on flat `#00ff00`, with no shadow, grid, labels, props or extra figures.

## Final prompt — succubus woman

Create a consistent pixel-art top-down RPG walk-cycle sheet based on the supplied
female succubus. Facial recognizability is the highest-priority invariant:
preserve her large dark eyes, round black glasses, warm face, straight black
bangs, long black hair and cute intelligent expression. Preserve the curved black
horns, fitted gothic black dress with small gold accents, black boots, and compact
black-to-deep-purple bat wings. Use exactly four columns and four rows: down,
left, right and up; four seamless contact/passing walk frames per row. Keep body
center and foot baseline fixed, with equal padding and no overlap. Keep glasses,
eye highlights, bangs, horns and wings distinct at 32×40 pixel game scale. Render
only one tasteful adult character per cell on flat `#00ff00`, with no shadow,
grid, labels, props or extra figures.
