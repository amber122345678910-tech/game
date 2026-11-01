# Research report: the Roblox "Undertale AU asymmetric battle" genre (for an original game)

## 0. How this was researched, and limits

- **Fetching pages was blocked.** WebFetch and curl both failed with "host not resolvable / outside allowed network domains" for www.roblox.com, *.fandom.com, devforum.roblox.com, en.namu.wiki and commonsensegamer.com. Every fact below comes from WebSearch result snippets of those pages, not from reading the full pages. Treat exact numbers as "what the page said when it was indexed". To verify further, the session needs `*.fandom.com`, `devforum.roblox.com`, `create.roblox.com`, `www.roblox.com` and `en.namu.wiki` allowed in its network settings.
- **Most mechanics come from community wikis** (Fandom and NamuWiki). They are often dated and sometimes contradict each other. Conflicts are flagged inline.
- **Status of the main games as of 2026-11-01:**
  - **Undertale: Last Corridor (ULC):** the active leader of the genre. Peak of about 6,813 concurrent players on Jan 24 2026 ([rolimons](https://www.rolimons.com/game/10982620122)). It is ranked #1 among Undertale experiences by player count in Oct 2026 ([robipedia](https://robipedia.com/tag/undertale)). Sans reworks were still shipping in March 2026 ([YouTube](https://www.youtube.com/watch?v=oCpIYkqM9qM)).
  - **Undertale: Judgement Day (UJD):** effectively finished. There is a "FINAL UPDATE" Shattered Dream rework video ([YouTube](https://www.youtube.com/watch?v=6qayycjL_7c)), NamuWiki says there were no updates for about 1.5 years after the "Lazy Update" ([namu](https://en.namu.wiki/w/Undertale:%20Judgement%20Day)), and the wiki says there will be no more events ([wiki](https://judgement-day-roblox.fandom.com/wiki/Current_Events:)).
  - **Undertale: Final Showdown (UFS):** frozen. Its game page says no more content because a full remaster is in progress ([rolimons](https://www.rolimons.com/game/9062331853)).
  - **Sans Multiversal Battles (SMB):** the original by flygeil is no longer updated. Fan remasters exist ([SMB Remastered wiki](https://sans-multiversal-battles-remastered.fandom.com/wiki/Sans_Multiversal_Battles_Remastered_Wiki)).
  - **"Undertale: Last Breath":** I found no Roblox game by that name. "Last Breath Sans" only appears as a character inside UJD, ULC and other games ([UJD](https://judgement-day-roblox.fandom.com/wiki/Last_Breath!_Sans), [ULC](https://undertalelastcorridor.fandom.com/wiki/Last_Breath_Sans)). Whether a standalone game exists is UNVERIFIED.

---

## 1. Round structure

| Game | Format | Monster selection | Round flow / win condition |
|---|---|---|---|
| UJD | Chara Team (N humans) vs Sans/Papyrus Team ([wiki home](https://judgement-day-roblox.fandom.com/wiki/Undertale:_Judgement_Day_(Roblox)_Wiki)) | Plain queue: the top player becomes Sans, then moves to the back of the line ([namu](https://en.namu.wiki/w/Undertale:%20Judgement%20Day)) | About 27 s lobby countdown, then a round ([Lobby](https://judgement-day-roblox.fandom.com/wiki/Lobby)). Humans win by depleting the monster's "dodges" and then its HP. Monster wins by killing all humans. Some monsters invert this: Ultra! Sans has no dodges or HP, and humans must **survive 2 minutes** ([Ultra! Sans](https://judgement-day-roblox.fandom.com/wiki/Ultra!_Sans)). Round timer default: UNVERIFIED (NamuWiki lists "Time: 200 seconds" for an early Sans ([namu](https://en.namu.wiki/w/Undertale:%20Judgement%20Day))). |
| UJD servers | Split by win count: low 1–100, mid 100–400. A high-win server existed and was removed ([Lobby](https://judgement-day-roblox.fandom.com/wiki/Lobby), [Category:Mid Wins](https://judgement-day-roblox.fandom.com/wiki/Category:Mid_Wins)) | You enter via signs next to spawn if you have enough wins | Players asked for the mid limit to be raised to 600–700 ([forum](https://judgement-day-roblox.fandom.com/f/p/4400000000000085739/r/4400000000000259040)) |
| ULC | 1 Sans vs up to 3 Charas ([Fan Tutorial](https://undertalelastcorridor.fandom.com/wiki/Fan_Tutorial)) | Queue order at round start ([Fan Tutorial](https://undertalelastcorridor.fandom.com/wiki/Fan_Tutorial), [namu](https://en.namu.wiki/w/Undertale:%20Last%20Corridor)) | Default round length: UNVERIFIED. Private-server owners can change it with `/timer (Amount)`, and private servers give no Wins/EXP ([Private Servers](https://undertalelastcorridor.fandom.com/wiki/Private_Servers)) |
| ULC Silly Mode | 6-player servers, one random modifier per match (e.g. "Tiny Terror": tiny and very fast). Wins/EXP are lost on leave, and the wiki calls it "very buggy" ([Gamemodes](https://undertalelastcorridor.fandom.com/wiki/Gamemodes)) | same | — |
| UFS | Sans Team vs Chara Team. Humans pick an equipment loadout and a SOUL passive ([wiki](https://undertale-final-showdown.fandom.com/wiki/UnderTale_Final_Showdown_Wiki)) | UNVERIFIED | Sans Team must kill the Chara Team |
| UTPR | Mostly 1v1 arena fighter, modelled on SoulShatters ([Game Mechanics](https://undertale-test-place-reborn.fandom.com/wiki/Game_Mechanics)) | n/a | — |
| SMB | Free-for-all brawl, up to 20 players ([rolimons](https://www.rolimons.com/game/4620729627)) | n/a | — |

**Selection systems in the wider asymmetric genre (good references):**
- **Murder Mystery 2:** chance grows each round you are not the murderer and resets to 2% after you are picked ([DevForum](https://devforum.roblox.com/t/how-do-chance-of-murderer-percentages-work/825298)).
- **Forsaken:** "Malice" goes up with each round played as a survivor and resets to 1 after you play killer. It is shown on the pre-round leaderboard. A paid +15 boost for 200 Robux is reported by third-party guides only ([deltiasgaming](https://deltiasgaming.com/?p=229961), [rblxguide](https://rblxguide.com/games/forsaken)). This is not an official formula.
- **Common DevForum pattern:** each player's weight starts at 1, goes up by 1 each round they are not picked, and resets when picked. The monster is chosen by weighted random ([DevForum](https://devforum.roblox.com/t/building-a-chance-increase-system/1781471)).

---

## 2. Typical mechanics

### 2a. Monster ("Sans") defense: dodges as a shield layer, then 1 HP
- **UJD Sans:** 15 Dodges and 1 HP, needs 20 wins. A badge cuts it to 5 dodges ([Sans](https://judgement-day-roblox.fandom.com/wiki/Sans)). Other variants differ: Venom 13 dodges/10 HP, Pacifist 15 dodges ([Venom](https://judgement-day-roblox.fandom.com/wiki/Venom!_Sans), [Characters/Sans](https://roblox-undertale-judgement-day.fandom.com/wiki/Characters/Sans)).
- **UTPR:** "Dodge HP" is a shield layer for Sans, StoryShift Chara and Gerson. When it breaks, base HP takes damage ([Game Mechanics](https://undertale-test-place-reborn.fandom.com/wiki/Game_Mechanics)).
- **Alternate Battlegrounds (AB):** Sans auto-dodges everything while his dodge bar lasts. The bar has 200 HP, incoming damage is divided by 6.9, it does **not** regenerate mid-fight, and after it breaks he has 1 HP ([AB Sans](https://alternate-battlegrounds.fandom.com/wiki/AB_Sans)).
- **SMB2 Sans:** 20 dodges, 1 HP, unlocked at 2100 LOVE. His teleport makes him invisible and faster for a while ([smb2 wiki](https://smb2.fandom.com/wiki/Sans)).
- **Undertale 3D Boss Battles:** Sans takes no normal damage. Hits make him dodge, he counters in later phases, and he can only be hurt once fully "exhausted" ([3DBB Sans](https://undertale-3d-boss-battles-roblox.fandom.com/wiki/Sans)). ULC's 3DBB Sans gets **stronger the lower his stamina** ([ULC 3DBB Sans](https://undertalelastcorridor.fandom.com/wiki/3DBB_Sans)).

### 2b. Monster resource: stamina
- **ULC:** moves cost stamina. Pre-rework Pacifist Sans: Bone Rush 3, Bone Zone 4 ([prerework page](https://undertalelastcorridor.fandom.com/wiki/Prerework_Undertale_Sans_(Pacifist))). Pacifist Sans regains stamina with "Ketchup", usable 5 times; the 6th use throws the bottle and leaves slowing puddles ([Pacifist Sans](https://undertalelastcorridor.fandom.com/wiki/Pacifist_Sans)). Upgraded Insanity Sans regains 15 stamina per Chara killed ([Insanity Sans](https://undertalelastcorridor.fandom.com/wiki/Insanity_Sans)).
- **UJD:** NamuWiki criticises that stamina is shown as "NULL", so players cannot see how much is left ([namu](https://en.namu.wiki/w/Undertale:%20Judgement%20Day)).

### 2c. KR / Karma
- **Original Undertale:**
  - Sans's hits drain 1 HP per frame through KARMA and can land many weak hits quickly ([undertale.wiki Sans/In battle](https://undertale.wiki/w/Sans/In_battle)).
  - KR is capped at 40 and **cannot bring HP below 1**. The more KR builds up, the faster it drains.
  - While KR is above 0, a pink-purple bar overlaps the yellow HP bar, and the HP number turns pink-purple ([undertale.wiki KR](https://undertale.wiki/w/KR)).
  - It cancels the usual invulnerability frames ([Giant Bomb](https://www.giantbomb.com/sans/3005-32801/)).
- **UJD KR V2:** drains a **percentage** of HP. Usually 1%; Venom 2%; "True KR" 1.5% ([KR V2](https://judgement-day-roblox.fandom.com/wiki/KR_V2/Rework)). Legacy KR cannot kill, except True! Dust at 1 HP. Purple HP numbers mean KR is active ([KR Legacy](https://judgement-day-roblox.fandom.com/wiki/KR_(Legacy))). Counters such as Kindness and "Karma Negation" exist, but "True KR" ignores them ([Chara strategy](https://judgement-day-roblox.fandom.com/wiki/Blog:Chara_Team/Strategy)).
- **AB:** every Sans attack applies Karma. It ticks faster as stacks grow, and physical damage passes through except at 1 HP ([AB Sans](https://alternate-battlegrounds.fandom.com/wiki/AB_Sans)).
- **ULC:** attacks carry a KR icon in their descriptions ([Outertale](https://undertalelastcorridor.fandom.com/wiki/Outertale_Sans), [Underfell](https://undertalelastcorridor.fandom.com/wiki/Underfell_Sans)).

### 2d. Colour rules and gravity (from Undertale)
- **Light-blue attacks** only hurt if you move. **Orange attacks** only hurt if you stand still ([undertale.wiki Bravery](https://undertale.wiki/w/Bravery)).
- **Blue SOUL** means gravity: you fall to the bottom of the box after a jump. Sans uses blue mode for the first half of his fight ([undertale.wiki Blaster](https://undertale.wiki/w/Blaster)).
- **UJD Ink! Sans** with the Cyan vial turns every move into a "blue attack" ([Ink! Sans](https://judgement-day-roblox.fandom.com/wiki/Ink!_Sans)).

### 2e. Standard attacks (UJD base Sans)
- **Bone Zone:** a red square telegraph, then bones rise inside it.
- **Gaster Blaster:** a white beam aimed where the player clicks. **Quad Blaster** is a four-blaster version.
- **Bone Throw:** white and blue bones thrown in the facing direction.
- All carry KR, and attacks are aimed by mouse ([Sans](https://judgement-day-roblox.fandom.com/wiki/Sans)).
- Variants:
  - Dust's "Karmic Retribution" covers the whole floor in purple bones ([Dust High LV](https://judgement-day-roblox.fandom.com/wiki/Dust!_Sans-_High_LV)).
  - LB Sans's blasters auto-aim at the Chara Team; phase 2 adds a "Force" push-away ([Last Breath!](https://judgement-day-roblox.fandom.com/wiki/Last_Breath!_Sans)).
  - DustDust blasters have a 60% chance per blaster to turn dark-blue/red and fire a red beam ([DustDust](https://judgement-day-roblox.fandom.com/wiki/DustDust_Sans)).
  - A ULC Sans has a teleport that does no damage and applies no karma ([namu Sans Team](https://en.namu.wiki/w/Undertale:%20Last%20Corridor/%EC%BA%90%EB%A6%AD%ED%84%B0/%EC%83%8C%EC%A6%88%20%ED%8C%80)).
- **Telekinesis / blue-soul grab** as a 3D move: UNVERIFIED in these games. No page found.

### 2f. Phases (the "special phase" climax)
- **UJD definition:** a phase triggers when the monster would normally lose. Instead of dying, it changes, and each phase has its own model, attacks, dodges and HP ([Phases](https://judgement-day-roblox.fandom.com/wiki/Phases)).
- **Example chain:** Sans phase 2 ("Sans + Papyrus") triggers at 10 dodges if conditions are met. Killing him in phase 2 (15 dodges) leads to phase 3 "Rejuvenation". LB Sans phase 2 has 10 dodges and 0.01 HP ([Phases](https://judgement-day-roblox.fandom.com/wiki/Phases), [LB](https://judgement-day-roblox.fandom.com/wiki/Last_Breath!_Sans)).
- **ULC Aftertale:** in phase 2, "DT" acts as functional HP with **no i-frames** ([Aftertale](https://undertalelastcorridor.fandom.com/wiki/Aftertale_Sans)).
- **UTPR:** phases change moveset, walkspeed and other mechanics heavily ([Game Mechanics](https://undertale-test-place-reborn.fandom.com/wiki/Game_Mechanics)).

### 2g. How humans fight back
- **UJD souls + items:**
  - The Determination Soul passive adds +50 max HP, +25 melee damage and a bigger slash every 30 s ([Determination Soul](https://judgement-day-roblox.fandom.com/wiki/Determination_Soul)).
  - Real Knife + Determination + Locket + 5 LOVE gives 1%/s regen, immunity to void and bleed, and 3–6 lives depending on LOVE ([Real Knife](https://judgement-day-roblox.fandom.com/wiki/Real_Knife)).
  - The Frisk combo needs 1200 wins plus the Reset badge and gives 555 HP ([Soul Combos](https://judgement-day-roblox.fandom.com/wiki/Soul_Combos)).
  - Kindness makes a team dome that blocks most attacks and stops KR ([Kindness Soul](https://judgement-day-roblox.fandom.com/wiki/Kindness_Soul)).
  - Patience heals while you stand still ([Patience blog](https://judgement-day-roblox.fandom.com/wiki/User_blog:Zeeveemc/Patience_Combo)).
  - Bravery adds damage and speed; its combo summons a giant fist ([SOUL](https://roblox-undertale-judgement-day.fandom.com/wiki/SOUL)).
  - Justice is camp-and-shoot ([Soul Combos](https://judgement-day-roblox.fandom.com/wiki/Soul_Combos)).
- **ULC:** default Chara weapons are Real Knife, Spinning knives and Side knives ([Chara Team forum](https://undertalelastcorridor.fandom.com/f/t/Chara%20Team)). Chaos Sabers give the whole team speed and damage that scale with the number of active SOULs ([Chaos Sabers](https://undertalelastcorridor.fandom.com/wiki/Chaos_Sabers)). Weapons are swapped at Killer Sans's kiosk ([namu ULC](https://en.namu.wiki/w/Undertale:%20Last%20Corridor)).
- **ULC/sandbox SOULs:**
  - Integrity: a high double jump on a cooldown; speed and jump grow the longer you avoid damage ([sandbox](https://undertale-last-corridor-sandbox.fandom.com/wiki/Chara_Team)).
  - Historical Justice: the last human alive gets a second life with 48 HP.
  - Historical Perseverance: i-frames after each hit ([Soul Scythe](https://undertalelastcorridor.fandom.com/wiki/Soul_Scythe)).
- **UFS:** per-SOUL passives, plus weapon/armor/food bought in Chara's Shop ([Chara's Shop](https://undertale-final-showdown.fandom.com/wiki/Chara's_Shop)).

### 2h. Brawler layer: block, parry, dash, M1
- **UTPR:**
  - Blocking reduces most hits to 1 damage or less.
  - Perfect block has a very tight window shown by a blue outline and has a cooldown. It knocks both players back, stuns both briefly with i-frames, and gives the blocker +10 stamina ([Combat system](https://undertale-test-place-reborn.fandom.com/wiki/Combat_system)).
  - The window is quoted as about 1–10 ms on one page and about 0.5 s (untested) in the Sans guide. These CONFLICT ([Sans guide](https://undertale-test-place-reborn.fandom.com/wiki/Sans/Pre-Rework/Guide)).
  - Stamina pool is 20. Running in combat drains it. Dash is double-tap WASD or C ([namu UTPR](https://en.namu.wiki/w/Undertale%20Test%20Place%20Reborn)).
  - Mana was removed in the Combat Rework.
- **AB:** perfect block is timed to the M1 hitbox. The window went from 0.2 s to 0.18 s and was later loosened. It stuns the attacker for 2.5 s (another page says about 1 s). Block-breaking M1s cannot be perfect-blocked. Blocking right after an enemy teleports is a standard counter ([AB Mechanics](https://alternate-battlegrounds.fandom.com/wiki/AB_Mechanics), [AB Sans](https://alternate-battlegrounds.fandom.com/wiki/AB_Sans)).
- **Ragdoll / hit-stun durations** in these Undertale games: UNVERIFIED. Nothing found.

### 2i. Controls the genre expects
- **ULC defaults:** Q/E/R/Z/X/C = abilities 1–6, F/G = soul abilities, CTRL = dash ([Settings](https://undertalelastcorridor.fandom.com/wiki/Settings)).
- **AB/SoulShatters lineage:** LMB melee, F block, R teleport, 1–9 skills, Shift run, L or middle mouse lock-on, double-tap dash ([AB Roblox page via search](https://www.roblox.com/games/8573962925/Alternate-Battlegrounds-Skins-Ults), [gamepretty](https://gamepretty.com/?p=17606)).
- **UJD:** select an attack in the inventory, aim with the mouse, click ([Sans](https://judgement-day-roblox.fandom.com/wiki/Sans)).

---

## 3. Long-term interest: progression systems and Robux ties

| System | Where | Details | Robux-tied? |
|---|---|---|---|
| Wins as main currency, unlocking monster characters | UJD, ULC, UFS | UJD: Sans needs 20 wins; Error 404 needs 10,000 ([namu](https://en.namu.wiki/w/Undertale:%20Judgement%20Day)). ULC: wins unlock characters and weapons; Pacifist Sans needs 2 wins ([namu ULC](https://en.namu.wiki/w/Undertale:%20Last%20Corridor)) | No (but see gamepass row) |
| Kills converted to wins | UJD | 8 kills = 1 win at Sans in the lobby ([Lobby](https://judgement-day-roblox.fandom.com/wiki/Lobby)) | No |
| EXP and LOVE levels | UJD, ULC, 3DBB | UJD EXP can be traded for LOVE, Evolution Points, Wins, Kills or Coins ([EXP](https://judgement-day-roblox.fandom.com/wiki/EXP), [LOVE](https://judgement-day-roblox.fandom.com/wiki/LOVE)). 3DBB: max LV 50, max EXP 1,250,000 ([Progression](https://undertale-3d-boss-battles-roblox.fandom.com/wiki/Progression)) | No |
| Gamepass monsters with their own evolution track | UJD | Evolution Geno/Dust go up via "Broken Code"/"Dust", 1–5 per kill at random, **independent of wins** ([Evolution Points](https://judgement-day-roblox.fandom.com/wiki/Evolution_Points_(Training,_Code,_and_Dust))) | **Yes** |
| Gamepass Sans characters | ULC | 3 purchasable ([namu ULC](https://en.namu.wiki/w/Undertale:%20Last%20Corridor)). Possession Sans needs 125 wins + Robux ([Possession](https://undertalelastcorridor.fandom.com/wiki/Possession_Sans)). Underswap moved from gamepass to the main cast in the Casino Update ([forum](https://undertalelastcorridor.fandom.com/f/t/Underswap%20Sans)) | **Yes** |
| Reset (prestige) | ULC, UFS, UJD | ULC: at 1000 wins; removes 1000 wins and unlocks reset-only content (wiki vs fan guide CONFLICT on whether all wins are lost) ([True Reset](https://undertalelastcorridor.fandom.com/wiki/True_Reset), [Badges](https://undertalelastcorridor.fandom.com/wiki/Badges)). UFS: each reset adds +2 to the level cap, max 3 resets (20 LV + 50k G, 22 LV + 60k, 24 LV + 70k), unlocking weapons ([Stats](https://undertale-final-showdown.fandom.com/wiki/Stats)) | No |
| Skill tree | UFS | 2 points per level. Respec costs 30,000 G **or 300 Robux** ([Character Upgrades](https://undertale-final-showdown.fandom.com/wiki/Character_Upgrades)) | Partially |
| Quests | UFS | NPC Spamton offers 3 quests that refresh every 12 h (e.g. "kill 10 Charas", "win 3 times as Sans", "land the final blow with a weapon ability"). "Important" quests unlock at win thresholds. Rewards: soul fragments, materials, gold, EXP ([Quests](https://undertale-final-showdown.fandom.com/wiki/Quests)) | No |
| Daily cosmetic shop + casino lobby | ULC | Skin rotation every 24 h, paid in chips (300 common up to 10,000 legendary), at least one legendary per day ([Lobby](https://undertalelastcorridor.fandom.com/wiki/Lobby)) | Chips source beyond play: UNVERIFIED |
| Daily login "paycheck" | ULC | Chips, a 30-min EXP boost, wins. Missing the window resets the streak to 1 ([Fan Tutorial](https://undertalelastcorridor.fandom.com/wiki/Fan_Tutorial)) | No |
| Titles | ULC | 10k EXP on one weapon gives a title in that weapon's colour; titles also come from achievements or a shop ([Titles](https://undertalelastcorridor.fandom.com/wiki/Titles)) | No |
| Singleplayer bosses | ULC, UJD, 3DBB | ULC: beating Underswap gives 1 win, a badge and multiplayer access to that character; Dust gives 10 wins ([Badges](https://undertalelastcorridor.fandom.com/wiki/Badges)). 3DBB is a full PvE ladder with a boss-rush "Tem Trials" gated at LV 40 ([Tem Trials](https://undertale-3d-boss-battles-roblox.fandom.com/wiki/Tem_Trials)). The 3DBB lobby shows 7 SOULs that disappear as bosses are beaten, a visible progress board ([Determined 7](https://undertale-3d-boss-battles-roblox.fandom.com/wiki/Determined_7)) | No |
| Events | UJD, UFS | UJD past events: Gaster, Sudden Changes, Insanity, December, Death ([Events](https://roblox-undertale-judgement-day.fandom.com/wiki/Events)). UFS: HorrorTale event; April Fools 2024 RNG mode (e.g. Gaster Blaster at 1/250) ([Rng Gamemode](https://undertale-final-showdown.fandom.com/wiki/Rng_Gamemode)) | No |

**Platform context, recent change.** On June 15, 2026 Roblox widened "Recommended For You" from a 7-day to a **28-day retention** view and split "qualified play-through" into separate signals ([Roblox newsroom](https://about.roblox.com/newsroom/2026/06/optimizing-discovery-great-games-reach-millions-players-roblox)). The Discovery docs list play-through rate, **first-play bounce rate** and **play days per user** as "most important", and **intentional co-play days** and qualified play sessions as "important" ([create.roblox.com/docs/discovery](https://create.roblox.com/docs/discovery)). For design this means:
- get a new player into action fast,
- give reasons to come back on several days,
- make playing with friends worthwhile.

---

## 4. Player complaints, and what the better games do

| Complaint | Evidence |
|---|---|
| Huge win-count gaps, unbalanced roster, and a point where "the Sans team just ALWAYS wins" | UJD forum "Problems with UJD" ([link](https://judgement-day-roblox.fandom.com/f/p/4400000000000085700)). NamuWiki: higher win gates widen the balance gap, and there are too many characters to balance ([namu](https://en.namu.wiki/w/Undertale:%20Judgement%20Day)) |
| High-win combos "busted"; winning became "IMPOSSIBLE" | ([forum](https://judgement-day-roblox.fandom.com/f/p/4400000000000085739)) |
| Semi-forced grind to get good options | ([namu](https://en.namu.wiki/w/Undertale:%20Judgement%20Day)) |
| Hidden information (stamina shows as NULL) | ([namu](https://en.namu.wiki/w/Undertale:%20Judgement%20Day)) |
| Hitboxes bigger than the model | ([ERROR 404](https://judgement-day-roblox.fandom.com/wiki/ERROR_404)). Massive bone-jump hitboxes ([LOVE](https://judgement-day-roblox.fandom.com/wiki/LOVE)) |
| Monster too complex or miserable to play; reworks that make a character "unbearable" | ULC Last Breath complaints ([Sans Team forum](https://undertalelastcorridor.fandom.com/f/t/Sans%20Team)) |
| Human weapons too strong, ruining the monster side | ([Chara Team forum](https://undertalelastcorridor.fandom.com/f/t/Chara%20Team)) |
| Stall play (long-lasting attacks used to stall) | 3DBB Sans in ULC ([3DBB Sans](https://undertalelastcorridor.fandom.com/wiki/3DBB_Sans)). Insanity Sans "stalls while building stamina" ([Insanity](https://undertalelastcorridor.fandom.com/wiki/Insanity_Sans)) |
| Buggy side modes where progress doesn't count | ULC Silly Mode ([Gamemodes](https://undertalelastcorridor.fandom.com/wiki/Gamemodes)) |
| Bugged low-tier servers | Aug 2025 forum report ([forum](https://judgement-day-roblox.fandom.com/f/p/4400000000000085739/r/4400000000000259040)) |
| Content removed over controversy | Negatale Sans in ULC ([Negatale](https://undertalelastcorridor.fandom.com/wiki/Negatale_Sans)) |
| Lag from beam VFX | "Undertale Fighting" rebuilt Blaster beam animations to reduce lag ([game page via search](https://www.roblox.com/games/5458733686/Undertale-Fighting)). General Roblox fighting-game advice: client-side hit detection with server validation, and play feedback locally to hide latency ([DevForum](https://devforum.roblox.com/t/how-do-combat-games-achieve-no-lag/3371389), [DevForum](https://devforum.roblox.com/t/how-to-handle-responsiveness-in-a-combat-system-with-high-ping/4257883)) |
| Bullet-box SOUL too big, so attacks feel undodgeable | Player feedback on a Roblox Undertale project ([DevForum](https://devforum.roblox.com/t/insanely-awesome-high-quality-game-need-thoughts-on-gameplay-and-design/2460734)) |
| "Never get to be the monster" | No direct thread found. UNVERIFIED as a documented complaint, but the plain FIFO queues (UJD/ULC) do nothing for players who join late |

**What the leaders do differently (synthesis, not a quote).**
- ULC keeps reworking overpowered or awkward characters, and a 2026 video notes reworks are "becoming more balanced" ([YouTube](https://www.youtube.com/watch?v=T-z2ixR42fs)).
- ULC added a social casino lobby, a daily shop, titles and dailies.
- UTPR/AB add a skill layer (perfect block, stamina, dash), so humans don't win just by having better stats.
- UJD's win-tier servers are an early attempt at matchmaking, but it gated content behind 10k wins, which is exactly what players complained about.

---

## 5. Visual and UI conventions

**What players expect (the Undertale visual language):**
- A pixel font. Undertale uses 8-bit Operator JVE, and the fan clone "Determination Mono/Sans" ([fontsinuse](https://fontsinuse.com/uses/51307/undertale-dialogue-and-interfaces)) has unclear licensing.
- A white-outlined black battle box.
- A red heart SOUL (blue in gravity mode).
- An HP bar: yellow fill on red, with a magenta "KR" overlay and magenta HP text when karma is active ([undertale.wiki KR](https://undertale.wiki/w/KR)).
- Colour-coded attack rules: white = normal, light-blue = don't move, orange = move ([Bravery](https://undertale.wiki/w/Bravery)).
- Monster wiki pages show KR icons per move, so players expect move-level labels.

**What reads as "cheap" (from the complaints above):**
- hitboxes larger than the visuals,
- hidden or "NULL" resources,
- an oversized SOUL,
- laggy beams,
- buggy modes.

**What reads as "high quality" (inference):**
- every attack has a visible telegraph, like UJD's red square before Bone Zone,
- consistent colour semantics,
- readable resource bars,
- phase transitions with their own model and attacks (UJD Phases).

**Built-in, no-upload building blocks verified here:**
- **Font:** `Enum.Font.Arcade` = Press Start 2P, `rbxasset://fonts/families/PressStart2P.json`, enum value 13 ([DevForum font UI](https://devforum.roblox.com/t/new-font-ui-live/1967004), [Font enum](https://create.roblox.com/docs/reference/engine/enums/Font)). Usable as `Font.new("rbxasset://fonts/families/PressStart2P.json")`. Roblox "cloud fonts" load with `Font.fromId(id)` ([Font datatype](https://create.roblox.com/docs/reference/engine/datatypes/Font)). A pixel font called "Silkscreen" is named in a third-party catalog, but its asset ID is UNVERIFIED ([bloxodes](https://bloxodes.com/catalog/roblox-font-ids)).
- **Vector shapes such as the heart:** `Path2D` is fully released. Its `Closed` property loops the path, closed paths fill with a solid colour, and a child `UIGradient` overrides the fill. It does not clip natively, so parent it to a `CanvasGroup` for clipping ([Path2D full release](https://devforum.roblox.com/t/path2d-full-release/3027288), [Path2D docs](https://create.roblox.com/docs/reference/engine/classes/Path2D.md)). Exact fill behaviour should be checked in Studio. A heart can also be drawn from a grid of `Frame` "pixels" with no API risk.
- **Runtime pixel art:** `AssetService:CreateEditableImage()` plus pixel writes. It is blocked by default in published games and needs the owner to be 13+ and ID-verified, plus "Enable/Allow Mesh / Image APIs" turned on in Creator Dashboard or Game Settings > Security ([EditableImage docs](https://create.roblox.com/docs/en-us/reference/engine/classes/EditableImage.md), [DevForum](https://devforum.roblox.com/t/client-beta-in-experience-mesh-image-apis-now-available-in-published-experiences/3267293)). **Recently changed:** Release Notes 741 list "Remove ID verification and age 13+ requirements for Mesh & Texture APIs", but a reply says it was still pending ([Release Notes 741](https://devforum.roblox.com/t/release-notes-for-741/4906281)). Status is UNVERIFIED and needs checking in Studio.
- **Network-friendly VFX:** `UnreliableRemoteEvent` payloads are capped at 900 bytes (larger ones are dropped). It is meant for short-lived effects, so design effects so a lost packet does no harm ([docs](https://create.roblox.com/docs/reference/engine/classes/UnreliableRemoteEvent)).

**Optional things the owner can do in Studio:**
1. ID-verify and enable Mesh/Image APIs, which allows runtime-generated pixel sprites.
2. Pick music from Roblox's licensed library. Tracks marked "by Roblox" (APM) are licensed for on-platform use ([DevForum](https://devforum.roblox.com/t/upcoming-music-changes-and-copyright-related-action/130570)), and about 180k DistroKid tracks have been added since Sept 2024 ([DevForum](https://devforum.roblox.com/t/amplify-your-experiences-with-new-music/3164792)). Those are existing assets referenced by ID, so we upload nothing. Specific track IDs are UNVERIFIED and must be chosen in the Toolbox.

**IP caution:**
- A DevForum reply notes all Undertale content is Toby Fox's work ([DevForum](https://devforum.roblox.com/t/how-strict-is-undertale-in-terms-of-copyright/799869)).
- Unlicensed music leads to DMCA takedowns on Roblox ([DMCA guidelines](https://create.roblox.com/docs/production/publishing/dmca-guidelines)).
- Toby Fox is publicly supportive of fans ([GamesRadar](https://gamesradar.com/undertales-toby-fox-says-fans-should-be-supported-at-every-opportunity-amid-debate-over-music-rights-in-fanmade-prequel)), but music rights were disputed for Undertale Yellow in Oct 2025.
- Recommendation: original characters, names and music that are "genre-inspired". No Megalovania, no ripped sprites. This also matches the brief to build an original game.

---

## 6. Original design ideas that would make a new game stand out (22)

1. **A transparent fair monster queue.** Each round as a human adds weight. The chosen player resets to 1 (the MM2/Forsaken pattern). Show everyone's % on the pre-round board. Add a **pity rule**: guaranteed monster after N rounds without it. Never sell the chance.
2. **Role preference toggle** (Monster / Human / Either). Players who opt out give their weight to others, so nobody is forced into the role.
3. **Unlocks are sidegrades, not power.** Every unlocked monster or weapon fits a fixed power budget. This removes the "10k-win" balance cliff UJD players hated. Strength comes from a skill rating, not win count.
4. **Hidden skill rating per role** (separate ratings for monster and human). Matchmaking or server balance uses it, plus **automatic scaling**: monster dodges scale with the number of humans and their average rating.
5. **All information visible.** Stamina, dodges, KR, cooldowns and the phase threshold are always shown, which fixes UJD's "NULL stamina" problem. Hitboxes always match the visuals, with an optional debug outline in settings.
6. **Telegraph contract.** Every attack shows a 0.35–0.8 s ground or air telegraph in its colour rule (white / cyan = freeze / orange = move / magenta = KR). Add a colourblind pattern overlay, like Undertale's v1.001 blue-shade fix.
7. **"Verdict Box" 3D-to-2D grab.** The monster's signature move pulls one human into a 5–8 s 2D bullet-hell box in the ScreenGui (heart SOUL, gravity mode, colour rules). Survive and you return with a short buff. Getting hit adds KR. This is the genre's identity done in a new way, and it is all built-in UI.
8. **KR that rewards aggression.** KR can't kill on its own (Undertale rule) but drains faster as it stacks. Humans **cleanse** KR by landing hits or by a teammate's assist, which turns poison into pressure to attack instead of hide.
9. **Two-sided climaxes.** The monster gets a desperation phase at low dodges (UJD Phases). The **last human alive** gets a "Second Wind" with a small HP buffer and a speed boost (inspired by UFS/ULC Justice). Transitions are under 2.5 s with i-frames on both sides, so no cheap deaths.
10. **Anti-stall overtime.** After the timer, a "Collapse" phase starts: the arena shrinks, lights dim, and damage on both sides rises. Stall-heavy kits (ULC 3DBB/Insanity complaints) can't run out the clock.
11. **Human objectives besides "hit the monster".** Charge 3 "SAVE points" around the map while the monster defends. Each charged point removes 1 monster dodge or unlocks a team ability. This gives weaker players a meaningful job.
12. **Downed and revive instead of instant elimination**, with a limited revive budget per round. Encourages co-op and reduces spectating.
13. **Spectators still matter.** Eliminated humans become "Echoes" that can ping incoming telegraphs for teammates, or play a 2D micro-box challenge to earn one revive token for the team. This fixes waiting-room boredom.
14. **A shared player-driven team buff.** Like ULC's Chaos Sabers (team buff by number of active SOULs), humans who pick different SOULs get a "Harmony" bonus. This encourages variety without forcing metas.
15. **Brawler skill layer for humans.** Visible-window perfect parry (about 0.18–0.2 s, AB range) that refunds stamina (UTPR +10 stamina). Block-break heavies. A dash with i-frames. Monster auto-dodge only uses up its dodges when a human lands a *committed* hit, so spam doesn't count.
16. **Free mastery tracks per character.** Play either role to earn titles (ULC: 10k EXP on a weapon gives a title), intro poses, kill and death effects, coloured trails, battle-box frame skins. Purely cosmetic.
17. **Quests on a 12 h / weekly refresh** (UFS model) that rotate role-specific goals: "Parry 5 bones", "Win as monster without phase 2", "Revive 3 allies". Streaks **decay softly** instead of ULC's hard reset to 1.
18. **Free daily cosmetic shop** with a guaranteed rare (ULC's model) paid only with an earned currency. No Robux path at all; state this in the game description.
19. **Seasons ("Timelines") of about 8 weeks.** A seasonal leaderboard reset, a free season track, one new original AU monster per season, and a weekly modifier playlist (Silly Mode, but stable and progress counts).
20. **Fast onboarding against first-play bounce.** Under 30 s from join to a tutorial fight against a bot monster that teaches the colour rules, parry and the Verdict Box. A PvE boss gauntlet (3DBB/ULC singleplayer) unlocks monster kits by **demonstrated mastery**, not by grinding wins.
21. **Friends bonus (co-play signal).** Party queue that keeps friends on the same team, a small shared-XP bonus, and a "duo-monster" event mode (two weaker monsters vs more humans).
22. **Round recap and public balance notes.** End-of-round card with MVP, best dodge streak, parries and KR dealt. An in-lobby patch-notes board. Planned, publicly listed rework cycles (ULC's main strength) instead of silent nerfs.
23. **Netcode built for bullet-hell.** Client-side hit detection for dodges, server validation with ping-scaled tolerance, and projectile patterns generated on each client from a server seed sent over `UnreliableRemoteEvent` (under 900 bytes). Beams look smooth on every client, and a dropped packet never kills anyone.
24. **Original IP throughout.** An original "judge" monster cast and setting, licensed or Roblox-library music, and only Undertale's *mechanic* language (SOUL colours, KR, battle box). Lower DMCA risk and a distinct brand.