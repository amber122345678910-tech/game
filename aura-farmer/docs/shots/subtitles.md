## Burned-in subtitle report: Aura Farmer reference (854×480, 30 fps, frames 1–470)

**Time convention:** `t = (frame − 1) / 30`. `start` is the time of the first frame that shows the line. `end` is the time of the first frame where it is gone, which is `last_frame / 30`.

**Cadence note:** the clip is a 24 fps source converted to 30 fps. Every frame with `f ≡ 1 (mod 5)` (f = 6, 11, 16, …) repeats the previous frame, and the subtitle layer follows the same 24 fps cadence. All changes below are measured on the 30 fps frames.

### 1. Timing (exact to the frame, every boundary checked frame by frame)

| # | Text (exact) | First frame | Last frame | start (s) | end (s) | Coincides with a scene cut? |
|---|---|---|---|---|---|---|
| 1 | `DO DO DO DO DO DO DO DO` (8 DOs) | 1 | 81 | 0.000 | 2.700 | – (shot cut at f44 does not change it) |
| 2 | `THE AURA FARMER` | 82 | 116 | 2.700 | 3.867 | yes, cut at f82 |
| 3 | `DO DO DO DO DO DO DO DO` (8 DOs) | 117 | 198 | 3.867 | 6.600 | yes, cut at f117 (cuts at f150 and f178 do not change it) |
| 4 | `HE’S SUCH A CHARMER` (curly ’) | 199 | 236 | 6.600 | 7.867 | yes, cut at f199 |
| 5 | `WAKE UP IN THE MORNING` | 237 | 286 | 7.867 | 9.533 | yes, cut at f237 |
| 6 | `I'M FEELING NO STRESS` (straight ') | 287 | 347 | 9.533 | 11.567 | yes, fast whip/blur transition f287–290 (gym cut at f335 does not change it) |
| – | *(no subtitle)* | 348 | 359 | 11.567 | 11.967 | no cut, gym shot continues |
| 7 | `AIN'T GOT NO WORRIES` (straight ') | 360 | 394 | 11.967 | 13.133 | no cut |
| 8 | `CUZ I KNOW I'M THE BEST` (straight ') | 395 | 462 | 13.133 | 15.400 | yes, throne cut at f395 |
| – | *(no subtitle)* | 463 | 469 | 15.400 | 15.633 | throne shot continues |

**End of clip: there is no fade and no black.** The subtitle cuts off at f463 (15.400 s) while the throne shot keeps going (mean luma about 34, the same as before). Frame 470 (t = 15.633 s) is a hard cut to the next shot of the video (a man in a white tank top in a gym, mean luma 86). The clip ends at 15.667 s. If the recreation ends on the throne, end it at 15.633 s and leave out frame 470.

**Scene cuts for reference:** 44, 82, 117, 150, 178, 199, 237, 287–290 (whip), 335, 395, 470.

### 2. Appear / disappear behaviour

- **Hard cuts only.** There is no pop-in scale, fade, slide or per-word reveal. The first frame of each line already has full pixel count, full opacity and final size, and the last frame is the same.
- **One continuous slow wiggle on the whole subtitle layer.** It is the text's own motion, not camera motion: in f387→388 and f201→202 the background is still while the text jumps.
  - Range is about ±3.5 px horizontally (±0.4 % W) and about ±3 px vertically (±0.6 % H) at 480p.
  - It is smooth and slow, roughly one cycle every 2–3 s (about 0.3–0.5 Hz).
  - On top of that there is roughly ±1 px of per-frame jitter, plus rare one-frame kicks of about 2–2.5 px (f60–61, f202, f209, f267, f388).
  - The wiggle carries on across line changes without resetting.
  - Rotation is at most 0.25°, so there is effectively none. Scale is constant.

### 3. Position and size (fractions of the 854×480 frame)

- **Horizontal:** centred at x = 0.500 W (bbox centres 426.5–427.5 px, ± the wiggle).
- **Vertical:**
  - Fill cap top is at 0.900 H (y ≈ 432) and the fill baseline at 0.946 H (y ≈ 454).
  - Including the extrusion, the bottom is at about 0.953 H (y ≈ 457.5).
  - The fill's vertical centre is about 0.923 H (wiggle 0.917–0.929).
- **Text height:**
  - Fill cap height is 22 px, or 0.0458 H.
  - With the extrusion the full glyph is about 25.5 px, or 0.053 H.
  - Font size works out to about 0.064 H (cap height ≈ 0.72 em), which is about 69 px at 1080p.
- **Line widths** (fill only, add about 4 px for the extrusion):

| Line | Pixels | Fraction of W | Multiple of cap height |
|---|---|---|---|
| DO ×8 | 374 | 0.438 W | 17.0 |
| THE AURA FARMER | 254 | 0.297 W | 11.5 |
| HE’S SUCH A CHARMER | 314 | 0.368 W | 14.3 |
| WAKE UP IN THE MORNING | 355 | 0.416 W | 16.1 |
| I'M FEELING NO STRESS | 321 | 0.376 W | 14.6 |
| AIN'T GOT NO WORRIES | 317 | 0.371 W | 14.4 |
| CUZ I KNOW I'M THE BEST | 346 | 0.405 W | 15.7 |

### 4. Font look

- **Case:** all caps.
- **Weight:** a heavy grotesque sans at Black / ExtraBold. Stems are 4–5 px on a 22 px cap, about 0.2 of the cap height.
- **Italic:** about 10–12° slant.
- **Width:** moderately condensed, with letters about 0.65–0.75 × cap height wide.
- **Shapes:** round C, O and S bowls; normal tracking.
- **Closest matches:** Roboto Condensed Black/Bold Italic, Helvetica Neue Condensed Black Oblique, Futura Condensed ExtraBold Oblique.

### 5. Colours and effects

**Fill:** a vertical linear gradient from top to bottom (UIGradient Rotation = 90). The measured medians below come from 20+ dark-background frames and are slightly desaturated by JPEG.

| Position | Measured colour |
|---|---|
| 0.00 | #ECCF63 (pale top edge) |
| 0.12 | #F2CB37 |
| 0.30 | #F2C135 |
| 0.45 | #EFB02D |
| 0.55 | #EE9F2A |
| 0.62 | #EB8A2C |
| 0.70 | #EA7930 |
| 0.80 | #E96733 |
| 0.88 | #E55535 |
| 1.00 | #DD443B |

Suggested clean stops: 0.0 **#FFD83A** → 0.45 **#FFAE2C** → 0.70 **#FF7A2E** → 1.0 **#F0443C**.

**Extrusion:**
- It is a solid dark-crimson 3D extrusion or hard shadow running down-right, with no gap between it and the glyph.
- Depth is about +4 px in x and +3.5 px in y at 480p, which is about 0.18 / 0.16 × cap height (0.0083 H right, 0.0073 H down).
- Colour is #8A0408 next to the glyph, #74001A in the middle, and #5A0016 to #710D20 at the far edge. A single colour of about **#7A0012** is a good match.
- On the right and bottom it fills the counters (inside C, U, O and so on).

**What is not there:**
- No outline stroke: the top and left edges anti-alias straight into the background, with zero red pixels above glyphs in most columns.
- No blurred drop shadow and no glow: background luma 1–8 px beyond the extrusion is unchanged.

### 6. JSON

[{"text":"DO DO DO DO DO DO DO DO","start":0.000,"end":2.700},{"text":"THE AURA FARMER","start":2.700,"end":3.867},{"text":"DO DO DO DO DO DO DO DO","start":3.867,"end":6.600},{"text":"HE’S SUCH A CHARMER","start":6.600,"end":7.867},{"text":"WAKE UP IN THE MORNING","start":7.867,"end":9.533},{"text":"I'M FEELING NO STRESS","start":9.533,"end":11.567},{"text":"AIN'T GOT NO WORRIES","start":11.967,"end":13.133},{"text":"CUZ I KNOW I'M THE BEST","start":13.133,"end":15.400}]