# Pixel icon sheets (owner generates them with ChatGPT, the lead integrates)

Each sheet: 1024x1024 PNG, 4x4 grid, 256 px cells, 32x32 pixel art upscaled x8, background magenta #FF00FF.
Integration plan: slice cells -> snap to the 32x32 grid -> quantize to the shared palette -> PixelArt modules
(merged runs, like src/shared/PixelArt/SansHead.luau) -> draw in the UI (no Roblox uploads needed).
Cells are numbered 1..16 row by row. Targets below = where each icon goes.

| Sheet | Cell | Target |
|---|---|---|
| 1 | 1-4 | ClassicSans skins Default, Midnight, Judge, Monochrome |
| 1 | 5-7 | FellSans skins Default, Ash, Royal |
| 1 | 8-10 | EclipseSans skins Default, Solar, Aurora |
| 1 | 11-16 | UI: Gold (coin), GoldPile, Exp (star), Quests (scroll), Trophy, Shop (bag) |
| 2 | 1-3 | Determination skins Default (Real Knife), Storyshift (Worn Dagger), Crimson |
| 2 | 4-5 | Patience Default (toy knife + faded ribbon), Frost |
| 2 | 6-7 | Bravery Default (Tough Glove), Champion |
| 2 | 8-9 | Integrity Default (ballet slippers), Swan |
| 2 | 10-11 | Perseverance Default (torn notebook), Midnight |
| 2 | 12-13 | Kindness Default (burnt pan), Chef |
| 2 | 14-16 | Justice Default (old revolver), Sheriff; 16 = cowboy hat (spare / Justice default alt) |
| 3 | 1-10 | Kit portraits: ClassicSans, FellSans, EclipseSans, Determination, Patience, Bravery, Integrity, Perseverance, Kindness, Justice |
| 3 | 11-12 | Red SOUL, Blue SOUL |
| 3 | 13-16 | Rarity badges Common, Rare, Epic, Legendary |
| 4 | 1-7 | ClassicSans abilities BoneJab, GasterBlaster, BlueSoul, BoneZone, BoneWall, Shortcut, BadTime |
| 4 | 8-14 | FellSans abilities BoneCleaver, CrimsonBlaster, ChainGrab, BoneRush, Bloodlust, Lunge, Execution |
| 4 | 15-16 | Verdict Box, Dodge |
| 5 | 1-7 | EclipseSans abilities VoidLash, RiftBlaster, GravityWell, Starfall, RiftTrap, VoidStep, TotalEclipse |
| 5 | 8-11 | Determination abilities KnifeCombo, LungingStrike, Afterimage, DeterminationUlt |
| 5 | 12-15 | Patience abilities ToyKnife, RibbonSnare, Patience, WaitingGame |
| 5 | 16 | Revive |
| 6 | 1-4 | Bravery abilities ToughPunches, GutsCharge, BraveStand, BurningCourage |
| 6 | 5-8 | Integrity abilities BalletKicks, GrandJete, Pirouette, Encore |
| 6 | 9-12 | Perseverance abilities NotebookSwat, SpellboundPages, Rewrite, FinalChapter |
| 6 | 13-16 | Kindness abilities PanBonk, HomeCooking, KindShield, ButterscotchFeast |
| 7 | 1-4 | Justice abilities Revolver, FanTheHammer, QuickRoll, FinalVerdict |
| 7 | 5-16 | UI: Dash, Block, Parry, Emote, SaveStar, Collapse, Phase2, Practice, Admin (crown), Music, Settings, Loadout |
