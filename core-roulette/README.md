# ☢ CORE ROULETTE (Roblox)

Напряжённая настольная игра на 1–4 игроков в индустриальном бункере. Всё — комната, стол,
Ядро, ЭЛТ-мониторы, манипулятор, HUD, свет и эффекты — строится кодом. **Внешних ассетов нет**:
звуки берутся из встроенных файлов клиента Roblox (`rbxasset://sounds/...`), текстуры частиц —
из `rbxasset://textures/particles/...`.

## Как открыть

**Вариант А — готовый файл.** Скачай `CoreRoulette.rbxl`, открой в Roblox Studio → **Play** (F5).
Для мультиплеера: *Test → Clients and Servers → 2–4 игрока → Start*.

**Вариант Б — вставить скрипты в пустой Baseplate.** Создай объекты как в иерархии ниже и
вставь код из `src/`:

```
ReplicatedStorage
└── Spring                (ModuleScript)  ← src/ReplicatedStorage/Spring.luau
ServerScriptService
├── BunkerBuilder         (ModuleScript)  ← src/ServerScriptService/BunkerBuilder.luau
└── CoreServer            (Script)        ← src/ServerScriptService/CoreServer.server.luau
StarterPlayer
└── StarterPlayerScripts
    └── CoreClient        (LocalScript)   ← src/StarterPlayerScripts/CoreClient.client.luau
```

Всё остальное создаётся само при запуске:

```
Workspace
└── CoreRouletteBunker (Model, Persistent)
    ├── Structure   — пол, стены, колонны, трубы, гермодверь, светильники
    ├── Table       — восьмиугольный стол, обод, подсветка, таблички мест
    ├── Chairs      — Chair1..4 → Seat + ProximityPrompt "Sit at Table"
    ├── Core        — контейнмент, CoreNeon (+CoreLight, звуки), осколки, FuelRods/Rod1..3, Cap (искры, пар)
    ├── CRT         — Monitor1..2 → Screen → SurfaceGui "CRTScreen"
    ├── Manipulator — портал, ShoulderPivot, Sleeve, Piston, ManipulatorHead (ClawSparks, ArcLight), Finger1..3
    ├── Lamp        — Hinge (качается) → Bulb → SpotLight
    ├── Beacons     — 3 аварийных маяка
    └── BunkerSpawn
ReplicatedStorage
└── CoreRemotes: PlayerAction, GameStateUpdate, MicroGameStatus, CoreDetonate (RemoteEvent),
                 ReplicateManipulator (UnreliableRemoteEvent); баланс — в атрибутах папки
Lighting: CoreAtmosphere, CoreGrade, CoreBloom, CoreDepth, CoreFlash
PlayerGui: CoreHUD, CoreFX
```

> **Lighting → Technology = Future** нельзя выставить из скрипта во время игры. В `CoreRoulette.rbxl`
> это уже сделано; при варианте Б поставь вручную (в новых Baseplate обычно уже стоит Future).
>
> Сохранение банка (`Cash`, `Wins`) работает в опубликованной игре с включённым
> *Game Settings → Security → Enable Studio Access to API Services*. Без этого игра просто
> работает без сохранений.

## Как играть

1. Подойди к стулу → **[E] Sit at Table**. Матч стартует через 3 с, если сидит хотя бы 1 игрок.
2. Ход: прожектор-лампа разворачивается к тебе, на ЭЛТ — твоё имя, банк, нестабильность, множитель.
   10 секунд на выбор (клавиши **1 / 2 / 3** или кнопки):
   - **[EXTRACT FUEL ROD]** — мини-игра 7 с. Держи **ЛКМ / Space / палец**, чтобы тянуть тяжёлый
     курсор вверх, и держи его в движущейся зелёной «магнитной зоне». Внутри зоны растёт прогресс,
     снаружи — клешня скрежещет по Ядру, искры, тряска, нестабильность летит вверх.
     100% = `+$1,000 × OVERCLOCK` в банк стола и −10% нестабильности.
   - **[OVERCLOCK CORE]** — +15% нестабильности, +$500 в банк стола, множитель +0.5, а у следующего
     игрока дрожь ×2. Недоступно при нестабильности ≥ 85%.
   - **[EMERGENCY EJECT]** — забираешь 40% банка стола в свой `Cash` и вылетаешь со стула.
3. 100% нестабильности или не успел за 7 с → **детонация**: сирена, вспышки, ударная волна,
   тебя отбрасывает, 30% банка стола сгорает, ты выбываешь из матча. Через 4 с Ядро остывает.
4. После 5 полных кругов выжившие делят банк стола и получают +1 `Wins`.
   Севшие посреди матча вступают со следующего круга.

## Game Feel Tuning Guide

Все ручки — в начале файлов, в таблицах `CONFIG` (сервер, баланс) и `FEEL` (клиент, ощущения).
Баланс сервер публикует клиенту атрибутами `CoreRemotes`, поэтому цифры на кнопках обновляются сами.

### Сложность мини-игры

| Где | Переменная | По умолчанию | Эффект |
|---|---|---|---|
| CoreServer | `SweetHalfWidth` | 0.13 | Полуширина зоны. Меньше = сложнее |
| CoreServer | `SweetBaseSpeed` | 1.0 | Скорость движения зоны |
| CoreServer | `ProgressRate` | 0.30 | Прогресс в секунду внутри зоны (≈3.3 с чистого удержания) |
| CoreServer | `ScrapeRate` | 18 | +% нестабильности в секунду при скрежете — главный «страх» |
| CoreServer | `MicroGameTime` / `MicroGameGrace` | 7 / 0.8 | Длительность и время на захват без штрафа |
| CoreServer | `OverclockDrift`, `OverclockSpeedFactor`, `OverclockWidthFactor` | 2 / 0.15 / 0 | Насколько OVERCLOCK усложняет ход следующего |
| CoreServer | `TurnHeat` | 4 | Нагрев Ядра в начале каждого хода |
| CoreClient | `CursorLift` / `CursorGravity` | 5.4 / 2.6 | Тяга вверх при удержании / «вес» курсора |
| CoreClient | `CursorDamping` | 2.0 | Вязкость: больше = курсор «тяжелее», меньше перелетает |
| CoreClient | `TremorBase` | 0.5 | Дрожь курсора (× дрожь от оверклока × нестабильность) |

Если меняешь физику курсора, держи `FEEL.CursorMaxSpeed` (2.0) **ниже** `CONFIG.CursorMaxSpeed`
(2.4) — иначе античит сервера начнёт «обрезать» честные движения.
`tests/run.luau` прогоняет бота: сейчас «умелый» игрок выигрывает ~98% при 20% нестабильности,
~46% при 60%, ~35% после чужого оверклока, а беспорядочное закликивание — ~1%.

### Камера и «сок»

| Переменная (`FEEL`) | По умолчанию | Эффект |
|---|---|---|
| `CameraSpeed` / `CameraFocusSpeed` | 7.5 / 10 | Жёсткость пружин камеры (больше = резче переходы) |
| `FovSeated` / `FovExtract` / `FovSpectateExtract` | 62 / 46 / 54 | Поле зрения за столом / в крупном плане / при наблюдении |
| `ParallaxStrength` | 1.4 | Параллакс от мыши за столом |
| `ShakeMaxAngle` / `ShakeFrequency` | 4.5° / 22 | Амплитуда и частота тряски (trauma²) |
| `TraumaDecay` | 1.3 | Как быстро тряска затухает |
| `ScrapeTrauma` | 0.9 | Тряска в секунду при скрежете |
| `FovPunchDetonation` / `FovPunchScrape` | 140 / 30 | Импульс FOV-«удара» |
| `RodLift` / `HeadTremble` | 3.2 / 0.4 | Насколько поднимается стержень и дрожит клешня |
| `HoverScale` / `PressImpulse` | 1.07 / −3.5 | Пружинный отклик кнопок |

Демпфирование пружин: `Damper = 1` — без перелёта, `< 1` — «пружинит» (лампа 0.22, кнопки 0.3–0.45).

## Разработка

```bash
../tools/setup.sh     # rojo, lune, luau-lsp в ../.tools
./build.sh            # строгий анализ типов -> тесты Lune -> CoreRoulette.rbxl
```
