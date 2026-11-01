# Undertale visual and lore reference for a 3D Roblox fan game (research as of 2026-11-01)

## 0. How this was checked, and what is still open

- **Network limits.** Only `github.com` and `raw.githubusercontent.com` could be reached. These hosts were blocked by the proxy (403), and each must be allowed in the session's network settings before anything on them can be read:
  - `undertale.com`, `deltarune.com`
  - `*.fandom.com`, `en.wikipedia.org`, `fanlore.org`, `tumblr`
  - `aftermath.site`
  - `create.roblox.com`, `devforum.roblox.com`
- **Search limit.** The WebSearch budget (200 per turn, shared by all agents) ran out after about 10 queries, all spent on the fan-policy topic. **The AU creator names and usage rules could not be checked.** The user can send a follow-up message to continue searching, or raise `CLAUDE_CODE_MAX_WEB_SEARCHES_PER_SESSION`.
- **Main evidence.** I cloned public repos and read them locally. Colours were sampled pixel by pixel with Pillow, and code and data files were read directly.
  - **[J]** Jcw87/c2-sans-fight ("Bad Time Simulator", 706★, last commit 2025-07-12): https://github.com/Jcw87/c2-sans-fight. Comments in the code say parts were taken from decompiled Undertale code ("decompiled code ftw").
  - **[U]** seanpm2001/Underune_Maker (2025-09-19): https://github.com/seanpm2001/Underune_Maker. It contains ripped sprite sheets: `Underune-maker/Undertale/Entities/Monsters/Bosses/{SansSprite,SansBattleSprite,PhotoshopFloweySprite}.png` and `.../Soul/HumanSouls.png`. The sheets carry the credit "Ripped by The Herp Derpinator… All credit goes to Toby Fox".
  - **[N]** naguiramiu/Undertale-Engine (2026-05-22): https://github.com/naguiramiu/Undertale-Engine
  - **[A]** techoskiller/AT-Engine (2026-01-10): https://github.com/techoskiller/AT-Engine
  - **[C]** RhenaudTheLukark/CreateYourFrisk (2025-12-16): https://github.com/RhenaudTheLukark/CreateYourFrisk
  - **[R]** Roblox data, local copies:
    - Client manifest for v0.745.0.7451137: `/tmp/claude-0/-home-user-game/f493f3e8-eb29-53b3-b677-a9d1a3d2561e/scratchpad/fc_man/rbxManifest.txt`
    - API dump: `/home/user/game/SoulVerdict/.tools/Full-API-Dump.json`
    - Tracker repo: https://github.com/MaximumADHD/Roblox-Client-Tracker
- **Local copies.**
  - Clones: `/tmp/claude-0/-home-user-game/f493f3e8-eb29-53b3-b677-a9d1a3d2561e/scratchpad/refs/`
  - Enlarged sprite views (`sanshead.png`, `blaster.png`, `blaster_front.png`, `ow_down.png`, `souls_a.png`, `souls_b.png`, `pf_s2.png`, `buttons.png`, `cyf_fonts.png`): `/tmp/claude-0/-home-user-game/f493f3e8-eb29-53b3-b677-a9d1a3d2561e/scratchpad/views/`
  - These sprites are Toby Fox's copyrighted art. Use them for measurement only and never put them in the game.

## 1. Fan-content policy and monetization

- **No written UNDERTALE fan-content or fan-game policy was found.** I could not confirm that none exists, because undertale.com and Tumblr were not reachable.
- **Undertale Yellow.** Toby Fox approved its development (https://en.wikipedia.org/wiki/Undertale_Yellow).
- **January 2024 music dispute.** Sebastian Wolff, CEO of Materia, challenged the Undertale Yellow team over its music.
  - Toby said: "The Undertale Yellow team did not receive explicit permission from me to publish any music until recently."
  - He said the way the dispute was handled was wrong, and donated $20,000 to AbleGamers.
  - He promised "a more clear set of guidelines" for using the music, and "better information on how to license the music properly".
  - Sources: Aftermath, 2024-01-08 (https://aftermath.site/undertale-creator-settles-music-ceos-bet-against-fans-by-donating-20000-to-charity/); GamesRadar (https://www.gamesradar.com/undertales-toby-fox-says-fans-should-be-supported-at-every-opportunity-amid-debate-over-music-rights-in-fanmade-prequel/); ResetEra (https://www.resetera.com/threads/toby-fox-donates-20k-to-ablegamers-after-undertale-yellow-materiamusic-drama-promises-clearer-guidelines-for-undertale-audio-fan-usage.802683/).
  - I found no evidence that the promised guidelines were ever published (UNVERIFIED).
- **Undertale Tumblr music guidelines, as Aftermath reports them** (the original post was not seen): selling covers needs a licence, and you may not use the UNDERTALE name or logo.
- **Materia Music Publishing YouTube FAQ** (https://materiamusicpub.com/youtube-faq/, dated 2020-10-20 according to https://deltarune.wiki/w/DELTARUNE_Soundtrack):
  - Most melodies may be used in non-commercial videos if Toby Fox (composer) and Materia (administrator) are credited.
  - For fan games that use the original music, covers or interpolations, "our claims will remain in place".
- **Toby has told streamers to dispute copyright claims** (https://www.gamesradar.com/games/rpg/toby-fox-urges-streamers-to-please-dispute-any-copyright-claims-they-get-over-undertale-and-deltarune-content-because-his-rpg-music-is-so-popular-it-hit-a-threshold-for-increased-copyright-strike-aggression-not-kidding/).
- **January 2026.** Automaton reports a Toby Fox statement about YouTube rights-claim problems, and that Materia is assigning a new person in charge (https://automaton-media.com/articles/newsjp/materia-music-toby-fox-20260126-411321/). The details are UNVERIFIED.
- **Weaker sources.** Toby's general stance is often summarised as "fine if it's not for profit" (Steam user, https://steamcommunity.com/app/391540/discussions/0/458606248620837592/; TV Tropes). Treat both as low reliability.
- **What this means for us (recommendations):**
  - Stay completely free: no Robux products of any kind.
  - Don't put "UNDERTALE" or its logo in the game title.
  - State in the description: "fan game, not affiliated; UNDERTALE © Toby Fox".
  - Use no ripped sprites, music or dialogue text. Write original lines.
  - Credit AU creators.

## 2. Classic Sans

### 2.1 Palette (sampled from the in-game sprites in [U]; the battle sprite is pure black and white)

| Part | Hex | Note |
|---|---|---|
| Hoodie | `#4782C9` | overworld sprite |
| Hood fur trim | `#BDC0C9` | bunched around neck and shoulders |
| Skull, teeth, T-shirt, pupils | `#FFFFFF` | |
| Outlines, eye sockets, shorts | `#000000` | the battle legs sprite shows white stripes on the shorts |
| Footwear | `#FFFFFF` in the overworld sprite | "Pink slippers" are an official-art or fan convention (UNVERIFIED). If used, something like `#F7A8C8` is a design choice. |
| Attack eye (his **left** eye, on the viewer's right) | `#84FFF2` ↔ `#FFFF40` | Two-frame cyan/yellow flicker: a ring iris with a 1 px dark centre ([U] "Face - Blue Eye"; [J] `Animations/SansHead/BlueEye`) |
| Ice-cream prop | `#FF40FF`, `#F48400` | overworld |

### 2.2 Proportions (measured)

- **Battle sprite at 1×** ([J]; drawn at 2× in `Layouts/BattleScreen.xml`):
  - Head 32×30, torso 54×25 (shrug 72×24), legs 44×23.
  - The head is about **38%** of total height (about 2.6 heads tall).
  - The jacket is about **1.7×** as wide as the head.
- **Overworld sprite:** about 30 px tall, with the head taking 14 rows (**about 47%**, about 2.1 heads tall). The head is 17 px wide and the hoodie 23 px.
- **3D recommendation:** make the head about 40–45% of total height, with a skull width-to-height ratio of about **1.07 : 1**. Depth cannot be measured from 2D sprites and is UNVERIFIED.

### 2.3 Face layout (battle head, 32×30 grid; [J] `Animations/SansHead/*`)

- **Skull shape:** a rounded rectangle ("squircle") with flat sides on rows 8–14, not an oval.
- **Eye sockets:** two black ovals, 10×7 px each, at x 3–12 and x 19–28 on rows 10–16.
  - Each is about 31% of head width and 23% of head height.
  - Their centres sit about 43% down from the top, with a 6 px gap between them.
- **Idle pupils:** 2×2 white dots, about 20% of socket width, set low and toward the nose.
- **Nose:** an inverted teardrop shape, 2–4 px wide, on rows 15–19.
- **Grin:** spans about 80% of head width on rows 19–26.
  - Five visible teeth, separated by vertical lines every 3–4 px, with diagonal creases at the corners.
  - The grin is fixed and never opens. Expressions come from the sockets and pupils only.
- **Head variants:** Default, LookLeft, Wink (his right eye becomes an arc), ClosedEyes, NoEyes (empty sockets, used for menace), BlueEye, Tired1/Tired2. Sweat has levels 0–3 ([J] `Documentation/Sans.md`).

### 2.4 Pose and animation inventory

- **Overworld [U]:** walking in 4 directions (hands in pockets, hood down), Laugh, Shrug, Sideways, Sleeping, Ice Cream.
- **Battle [J]/[U]:**
  - Idle bob and HeadBob.
  - Torso Default and Shrug.
  - Full-body HandUp/Down/Left/Right: an arm sweep that sets the direction of the SOUL slam.
  - Right Strike, Legs Standing/Sitting, Tired, Sweat.
  - A wounded torso with a red slash, `#ED1C24`.
- **Dodge [J]:** when the player picks FIGHT, his x position follows `320 − sin(t·225°)·100`. That is a 100 px slide left over 0.4 s, a hold until 1.1 s, then a return. A grey "MISS" appears, tinted to 75%, which gives `#BFBFBF`.

### 2.5 3D stylisation (recommendations, not sourced facts)

- **Silhouette:** big flat-fronted skull, a puffy trapezoid hoodie and short legs.
- **Sockets:** deep, non-reflective recesses with tiny emissive pupils. The attack eye should be an emissive ring with a PointLight, flickering between the two hex values in 2.1.
- **Grin:** an inset groove with tooth separators.
- **Outline:** use an outline pass (black Highlight with fill turned off, or an inverted hull) to echo the game's 1 px black outlines.
- **Faces without uploaded images:** draw the sockets, pupils and grin with SurfaceGui frames plus UICorner. Check the property names in the Roblox docs, which I could not reach.

## 3. Gaster Blaster

- **Design (from the [U] front sheet, 6 frames, and the [J] 57×44 side view):**
  - A long animal or dragon-like skull: a snout, two horn spikes at the back, cheek prongs and a central ridge.
  - Frames 0–2: mouth closed then slightly open, with small white diamond pupils.
  - Frames 3–5: the skull splits along its midline, the jaw drops wide, and the sockets go **hollow**.
  - In the original it is **pure white and black only**, with a white beam. Coloured beams and glows are a fan convention (UNVERIFIED).
- **Behaviour (all from [J] `Event sheets/Battle.xml`):**
  1. On spawn the charge sound plays, and the blaster flies to its end position.
  2. It rotates toward the target with an exponential ease: `Ang += (End−Ang)·dt·10`, a time constant of about 0.1 s.
  3. It waits a set time: 0.333 s for small blasters and 0.666 s for large ones in the intro.
  4. It plays the 5-frame "Fire" animation, and the beam appears 0.1 s later with screen shake.
- **Beam (from [J]):**
  - The beam is three stacked layers: `BaseSize`, `BaseSize/1.25` and `BaseSize/2`. Each also gets a sine wobble of `sin(t·20 rad)·BaseSize/4`, a period of about 0.31 s.
  - `BaseSize` ramps up to 35×scale over 4 frames.
  - It lasts the blast time: 0.27 s for small blasters and 0.5 s for large ones.
  - Afterwards `BaseSize` shrinks ×0.8 per frame and opacity drops 10% per frame.
  - The hitbox is 75% of `BaseSize`, and stops hurting below 80% opacity.
- **Recoil:** after firing, the blaster backs away, accelerating by 30 px/s per frame.
- **Damage:** 1 HP per frame, plus 10 KR on the first frame and 2 KR per frame after that.

## 4. Sans-fight mechanics ([J]; Undertale runs at 30 FPS, so the clone's px/s values are the original's per-frame values ×30, per `Documentation/Attacks.md`)

- **Attack colour rules:**
  - White always hurts.
  - **Blue `#14A9FF`** hurts only while the SOUL is moving.
  - **Orange `#FFA040`** hurts only while the SOUL is still.
  - These two colours come from the clone's tint values and were not checked against the original.
- **No invincibility frames:** contact deals damage every 1/30 s.
  - Bones and bone stabs deal 1 HP + 6 KR on the first frame, then +2 KR per frame.
  - The blaster beam deals 1 HP + 10 KR on the first frame, then +2 KR per frame.
- **KARMA (KR):**
  - KR is capped at 40 and clamped to HP − 1, so **KR cannot kill**.
  - While KR > 0 and HP > 1, the game drains 1 HP and 1 KR at an interval set by the KR level:

    | KR level | Drain interval |
    |---|---|
    | ≥ 40 | every 1 frame |
    | ≥ 30 | every 2 frames |
    | ≥ 20 | every 5 frames |
    | ≥ 10 | every 15 frames |
    | below 10 | every 30 frames |

- **Blue SOUL (`#003CFF`) gravity, in px/s at a 640×480 screen:**
  - Movement 150. Jump 180. Releasing the jump key caps upward speed at 30, so jump height varies.
  - Gravity changes with vertical speed: 540 while rising, 180 near the apex, 450 early in the fall, 180 when falling fast.
  - Maximum fall speed is 750. Gravity can point at any of the 4 walls, and the SOUL rotates to match.
- **Slam:** Sans's arm sweep sets the gravity wall and slams the SOUL into it. Slam damage only happens in the final attack, and there HP cannot drop below 1.
- **Bone stab:** a 1 px red (`#FF0000`) outlined warning rectangle shows for 0.17–0.6 s, then bones jut out of that wall.
- **Platforms:** one-way (you can jump up through them). Drawn as a white 1 px outline plus a dark green (`#2E5F2E`) outline offset by 4 px. They can move and reverse.
- **Bone sprite:** 10×24 white with knobbed ends, stretched to any length. Speeds range from 180 to 900 px/s.
- **Box sizes:**

  | Box | Size | Screen position |
  |---|---|---|
  | Menu / dialogue | 576×144 | (32,240)–(608,384) |
  | Sans square | 165×165 | (239,226)–(404,391) |
  | Blue-soul wide | 375×140 | (133,251)–(508,391) |

- **Menu bones:** in later turns, bones attack while you are choosing in the menu. They deal damage but cannot kill.
- **Fight order:**
  - Phase 1: intro → bonegap1 → bluebone → bonegap2 → platforms1–4 → platformblaster → platforms4hard → bonegap1fast → boneslideh → bonegap2 → platformblasterfast → random repeats → **spare offer**.
  - Phase 2: multi1 → randomblaster1 → multi2 → bonestab1–2 → randomblaster2 → boneslidev → multi3 → bonestab3 → random repeats → **final**.
- **Intro attack:** "ready?" → flash → slam down and a stab from the floor → a wave of bones with a sine-shaped gap → three volleys of 4 blasters (plus, X, plus) → 2 large blasters → "here we go."
- **"Bad time" final attack:**
  1. Four random slams, each with stabs.
  2. A long sideways-scrolling box containing a 900 px/s bone tunnel with a sine-shaped gap.
  3. Blackout flashes that teleport the SOUL, each followed by double stabs.
  4. An accelerating spiral of blasters around the box.
  5. 38 rapid random slams that deal damage and slow down as Sans tires (sweat 1 → 3, then the Tired faces).
  6. Sans falls asleep.
- **Escalating flavour beats:** tired → preparing something → special attack.
- **Stats in the clone:** Sans is "1 ATK 1 DEF". The player is LV 19 with 92 HP.

## 5. The seven human SOULs, as seven playable classes

| Trait | SOUL colour / damaged colour | Weapon (ATK) | Armour (DEF) | Omega Flowey phase sprites | Mode idea |
|---|---|---|---|---|---|
| Determination | `#FF0000` / `#800000` | Worn Dagger 15 / Real Knife 99 | Heart Locket 15 / The Locket 99 | n/a | free movement |
| Patience | `#42FCFF` / `#00A6C5` | Toy Knife 3 | Faded Ribbon 3 | knives + bandage | cyan "stay still" |
| Bravery | `#FCA600` / `#EC6F00` | Tough Glove 5 | Manly Bandanna 7 | punching gloves with a hit counter | orange "keep moving" |
| Integrity | icon `#001D7F`; gravity-mode SOUL `#003CFF` | Ballet Shoes 7 | Old Tutu 10 | ballet shoes, star, music note | blue gravity |
| Perseverance | `#D535D9` / `#8F1C93` | Torn Notebook 2 (raises invincibility time) | Cloudy Glasses 6 (raises invincibility time) | notebook + "HOPE" word projectiles | purple lines |
| Kindness | `#00C000` / `#008000` | Burnt Pan 10 | Stained Apron 11 | frying pan, flames, fried eggs | green shield |
| Justice | `#FFFF00` / `#F4D400` | Empty Gun 12 | Cowboy Hat 12 | revolver, bullets, crosshair, heart target | yellow shooter |

- **Colours:** sampled from [U] `HumanSouls.png` and from `PhotoshopFloweySprite.png`, whose sections are labelled "Human Soul Phases – Light Blue / Orange / Dark Blue / Purple / Green / Yellow Soul".
- **Stats:** from [C] `Documentation CYF 1.0/pages/item-list.html`.
- **Which weapon goes with which SOUL** is shown by those game sprites, so it is verified.
- **Which armour goes with which SOUL** is community consensus and UNVERIFIED.
- **Secondary item effects** (Burnt Pan improving healing, Apron regeneration, Cowboy Hat +ATK) are UNVERIFIED. CYF only notes the invincibility-time and healing-efficiency effects.
- **SOUL modes:** sprite sets exist for Blue (with the "San's Slam Attack" rotations), Green, Purple and Yellow (with "Shooter Mode" and "Bullets"). Which bosses use green, purple and yellow (Undyne, Muffet, Mettaton) is UNVERIFIED this session.

## 6. UI specification (640×480 logical screen; [J] `Layouts/BattleScreen.xml`)

- **Stats row:**
  - Name and LV ("CHARA LV19") at (32,402).
  - An "HP" label sprite (23×10, white, blocky) at x 224–247, bottom edge at y 416.
  - The bar at (256,400), **21 px tall, MaxHP × 1.2 px wide** (92 HP gives 110 px).
  - A "KR" label (23×10) right-aligned at x 400.
  - The HP text "HP / Max", with HP zero-padded to two digits, at (416,400).
- **HP bar colours:**
  - Background `#FF0000` ([C] `HPBar.prefab` colour {1,0,0}; [N] `c_red`). [J] uses `#BF0000`.
  - Fill `#FFFF00`.
  - KR is a magenta `#FF00FF` segment from HP−KR to HP. The HP numbers also turn magenta while KR > 0.
- **Buttons:**
  - 110×42 sprites at x 32, 184, 344 and 496, y 432.
  - A **2 px orange outline `#FF7F27`**, an icon (sword, sound waves, bag, X) and tall condensed capital letters.
  - When selected, the whole button turns `#FFFF00` ([N] uses `#FFFF40`) and the red SOUL replaces the icon ([J]; [N] `scr_battlefunctions.gml`).
- **Battle box:** a white border **5 px** wide on black ([N] `obj_battlebox` `line_size = 5`; [J] 9-patch).
- **Background grid:** [N] uses `#22B14C`.
- **Overworld text box:** 288×75 at the original 320×240 resolution, which is 576×150 at 640×480. Border 3 px (6 px at 2×). It sits at the top or the bottom of the screen. A portrait goes at +29,+18 and pushes the text right by 58 ([N] `obj_textbox/Other_11.gml`).
- **Text conventions:**
  - Every line starts with "* ", and wrapped lines are indented two spaces to align ([J] strings).
  - Typewriter speed is about 1 character per frame, roughly 30 per second ([N]).
- **Speech bubbles:** white, with black DotumChe text.
- **Fonts ([N]/[A] `.yy` files; [C] license and bitmap fonts):**

  | Use | Font |
  |---|---|
  | Main text | **8bitoperator JVE**, 12 pt (the Pixel Operator family by Jayvee Enaguas, SIL OFL 1.1) |
  | Battle stats row | **Mars Needs Cunnilingus** |
  | Tiny labels | **Crypt of Tomorrow** (UT variant), 4 pt |
  | Monster speech bubbles | **DotumChe Pixel**, 10 pt |
  | Sans | Comic Sans style, lowercase |
  | Papyrus | Papyrus style, all caps |

  CYF ships `sans.png` and `papyrus.png` bitmap fonts in those styles; I checked them visually. "Determination Mono" is a fan-made recreation, author UNVERIFIED.
- **SOUL sprite:** 16×16, 186 px filled, `#FF0000`.
  ```
  ..##........##..
  .#####....#####.
  #######..#######
  #######..#######
  ################  (rows 4-9 identical)
  ..############..
  ..############..
  ....########....
  ....########....
  ......####......
  ......####......
  ```
- **Built-in Roblox content, no uploads needed ([R]):**
  - `Enum.Font` includes `Arcade`, but has no Comic or Papyrus entry.
  - Font families in the client content, used as `Font.new("rbxasset://fonts/families/X.json")`:
    - `PressStart2P` for the pixel UI
    - `ComicNeueAngular` for Sans's speech
    - `Fondamento`, `Balthazar`, `AccanthisADFStd` as Papyrus-like options
    - `Inconsolata`, `RobotoMono`, `BuilderMono`, `Zekton` for monospaced text
  - Useful particle textures:
    - `rbxasset://textures/particles/SquareParticle.png` for pixel dust when a monster dies
    - `sparkles_main.dds`
    - `explosion01_shockwave_main.dds`
    - `forcefield_glow_main.dds`
    - `smoke_main.dds`

## 7. Underfell Sans and other AUs (all UNVERIFIED: no search budget left, wikis blocked)

The palettes below are rough art-direction values from memory, not sampled colours.

| Character | Creator usually credited | Look and palette | Typical fan-game attacks |
|---|---|---|---|
| Underfell Sans ("Fell", "Red") | disputed; often credited to Tumblr user loverofpiggies | black jacket with fur-trimmed hood (`#1C1C1C`, fur `#8A8A8A`), red sweater `#B5121B`, black shorts with a yellow stripe, spiked collar, gold tooth `#FFC83D`, red eye lights `#FF2A2A`; crude and paranoid personality in a "kill or be killed" world | sharp red bones, jagged red-eyed blasters, faster and more aggressive pace |
| Dust Sans | unknown | hood up, faded blue, grey dust streaks, split red/blue eye light | blasters and bones, the ghost of Papyrus |
| Horror Sans | Sour-Apple-Studios | heavy build, hole in the skull at upper left, single red pupil, sharp teeth, ragged hoodie, axe | axe strikes, slow heavy hits |
| Killer Sans | Rahafwabas | black hoodie, black "tear" streaks, red and white target-shaped SOUL on his chest, knife | knife slashes |
| Error Sans | loverofpiggies ("Crayon Queen") | black bones, red and yellow eye lights, blue streaks under the eyes, glitch text | blue strings, glitch blasters |
| Ink Sans | Comyet (Myebi) | brown scarf, ink stain, sash of paint vials, giant brush, pupils that change shape | brush swings, ink |
| Nightmare / Dream Sans | Jokublog | Nightmare: black goo, cyan eye, tentacles. Dream: gold cape, bow and arrows | tentacles / arrows |
| Swap Sans ("Blueberry") | popcornpr1nce | battle armour, blue bandana, star-shaped pupils | blue-heavy patterns |

- **Pages to check:** https://undertale-au.fandom.com/wiki/Underfell and https://fanlore.org/wiki/Underfell. Search results show these pages exist, but neither could be fetched.
- **Usage rules:** none could be verified. Some creators are reported to require credit and to ban commercial use or NSFW content.
- **Recommendation:** ship classic Sans plus original in-house "verdict" variants, and get creator permission before adding any named AU character.

## 8. What the owner could optionally do in Studio

1. Import sculpted Sans and Gaster Blaster meshes made in Blender as MeshParts. This is the biggest quality jump over parts built from primitives.
2. Upload face or eye decals and original sound effects. Avoid Undertale music, since Materia keeps claims on fan games that use it.
3. Upload custom fonts, if Roblox allows it now (UNVERIFIED).
4. Get written permission from AU creators before using their characters.

## 9. Still to verify once network and search access allow

- Creator names and usage rules for each AU.
- The Underfell palette.
- Whether Sans's pink slippers are canon.
- The blue and orange attack hex values and the KR thresholds, checked against the original decompiled code.
- The authors and licences of Mars Needs Cunnilingus and Crypt of Tomorrow.
- Whether Toby Fox's promised clearer guidelines were ever published.