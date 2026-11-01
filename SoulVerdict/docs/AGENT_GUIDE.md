# Guide for implementation agents (read fully before writing code)

Project root: `/home/user/game/SoulVerdict` (a Roblox game written entirely as code, built with Rojo).
Read `docs/SPEC.md` first — it defines every cross-module contract. Research notes: `docs/research/*.md`
(graphics.md = verified Roblox rendering facts & built-in texture paths; genre.md = genre conventions;
engine.md / undertale.md may appear later).

## Tools (Linux, offline Roblox emulation)
```
export PATH=/home/user/game/SoulVerdict/.tools/cargo/bin:$PATH     # lune, rojo, selene, stylua
cd /home/user/game/SoulVerdict
lune run tools/lune/run_tests.luau [filter]       # runs tools/lune/tests/*.spec.luau
rojo build default.project.json -o /tmp/x.rbxl    # builds the place
```
- `tools/lune/loader.luau` loads project modules under Lune with Roblox datatypes (`Instance.new`, CFrame,
  Vector3, Color3, Enum, UDim2, Font, NumberSequence, ...). Use `Loader.require("ReplicatedStorage.Shared.X.Y")`
  or `Loader.requirePath("src/shared/X/Y")`. Inside modules `script.Parent.X` works, `game:GetService` returns
  mocks (only ReplicatedStorage/ServerScriptService/StarterPlayer mounts + tiny RunService/Players/HttpService/
  TweenService mocks). Lune validates property names and enum items: setting a wrong property errors — great
  for catching API mistakes. Lune has no physics, no `workspace`, no `Model:ScaleTo`, no events firing.
  If the file tree changes during a run, call `Loader.rescan()`.
- Tests: add `tools/lune/tests/<area>.spec.luau` returning `{ testName = function(T, Loader) ... end }`
  (`T.ok(cond,msg)`, `T.eq(a,b,msg)`, `T.near(a,b,eps,msg)`, `T.noerror(fn,msg)`, `T.fails(fn,msg)`).
- Roblox API ground truth: `.tools/API-Dump.json` and `.tools/Full-API-Dump.json` (version 0.745). Check every
  class/property/method/enum you use against it when unsure (python3 one-liners are fine).
- Chromium + Playwright are preinstalled (`require('playwright')` works from any dir; `chromium.launch()`
  needs no options). Node 22. npm registry reachable. View your PNG renders with the Read tool and iterate.
- The machine has 4 CPU cores shared by several agents: avoid needless heavy work in loops.

## Coding rules (Luau)
- First line of every .luau file in `src/`: `--!strict`. Tabs for indentation. Clear names. Short header comment
  explaining the module's purpose and public API.
- No deprecated APIs: use `task.wait/spawn/delay/defer`, `workspace:Raycast`, `LinearVelocity`/`AlignOrientation`/
  `AlignPosition`/`VectorForce`, `TweenService`, `RunService.PreSimulation/PostSimulation/PreRender` (or Heartbeat).
  Never `wait()`, `spawn()`, `delay()`, `Instance.new(class, parent)`, `BodyVelocity`, `BodyGyro`, `BodyPosition`,
  `Humanoid:LoadAnimation`, `RenderStepped`, `FindPartOnRay`, `TweenPosition/TweenSize`.
- Configure instances fully, set `.Parent` last.
- Lune-safe modules (SPEC §2.1 marked [Lune-safe]) must not call `game:GetService`, use `workspace`, `RunService`,
  `TweenService` etc. at require time or inside builder functions; require siblings via `script.Parent...` only;
  use `Shared/Util/Rng.luau` instead of `Random`/`math.random` where determinism matters.
- All player-facing text via `Shared/Strings` (add your keys to YOUR OWN strings file in `src/shared/Strings/`,
  e.g. `Strings/Menu.luau`; every key needs `en` and `ru`; the merge list is in `Strings/init.luau` — if you create
  a new strings file whose name is not in that list, add it to the `SOURCES` list there).
- Validate every client→server payload on the server (types, ranges, rate limits).
- Performance: pool/reuse VFX parts, give every transient instance a lifetime, avoid per-frame allocations in hot loops.

## Ownership rules (several agents work in parallel in the same tree)
- Only create/edit files you own (listed in your task). Do NOT edit other agents' files. Do NOT reformat the tree.
- Shared foundation files (`Config.luau`, `Types.luau`, `Net.luau`, `Kits/**`, `Strings/init.luau`, `Strings/Core.luau`,
  `docs/SPEC.md`) are owned by the lead. If you truly need a change there (a missing type, a new remote, a tunable),
  make the smallest additive edit (append; never rename/remove existing fields) and list it under
  "Foundation edits" in your final report.
- Never run `git commit`/`git push`/`git checkout`/`git stash`/`git reset` — the lead handles git.
- If something you depend on does not exist yet, code against the SPEC contract and note it in your report.

## Quality bar
This game must look and feel like a top-tier Roblox experience. Every visual must be crafted (proportions,
silhouettes, colour harmony, layering of light and glow, motion with anticipation/overshoot), not placeholder.
Verify what you can: run the Lune tests, render previews and LOOK at them, re-check API names against the dump.

## Final report (your last message)
Return a concise report: files created; public API (signatures); how to use/run it; verification done
(commands + results); known limitations/TODOs; foundation edits; requests for other areas.
