# Ловцы Молний — архитектура кода

Roblox-проект собирается Rojo из `LightningCatchers/`. Код — Luau, везде `--!strict`, комментарии по-русски.
Игра двуязычная: английский — по умолчанию, русский — по локали Roblox или в настройках (раздел «Локализация» ниже);
текст для игрока пишется в коде по-русски (исходник и ключ словаря). Дизайн игры: `docs/DESIGN.md`. Все числа — только в `src/shared/Config.luau`.

```
LightningCatchers/
  default.project.json        дерево места (Remotes объявлены здесь)
  src/shared/   -> ReplicatedStorage.Shared   (чистая логика + контракты, общие для сервера/клиента/тестов)
  src/server/   -> ServerScriptService.Server (Main.server.luau + Services/*)
  src/client/   -> StarterPlayer.StarterPlayerScripts.Client (Main.client.luau, ClientState, Controllers/*, UI/*)
  src/map/Map.rbxmx -> Workspace.Map           (генерируется tools/gen_map.luau, не редактировать руками)
  tools/        сборка, тесты (Lune), анализ, превью-рендер карты
```

## Инструменты и проверки

Бинарники лежат в `/home/user/game/.tools` (`LightningCatchers/.tools` — ссылка на них).
```
cd LightningCatchers
tools/analyze.sh                         # строгий анализ типов всего src/ (должно быть 0 ошибок)
.tools/lune run tools/tests/run.luau     # юнит-тесты чистой логики
.tools/lune run tools/tests/balance.luau # симуляция баланса
.tools/lune run tools/gen_map.luau       # пересобрать src/map/Map.rbxmx
python3 tools/check_ui_props.py          # ключи таблиц UIKit.new/label/panel — настоящие свойства классов
python3 tools/check_loc.py               # локализация: переводы, плейсхолдеры, необёрнутые русские строки (0 ошибок)
.tools/rojo build default.project.json -o LightningCatchers.rbxl
.tools/lune run tools/verify_place.luau LightningCatchers.rbxl
# превью карты: tools/preview (dump_scene.luau -> render.mjs, см. README в папке)
```
Lune-тесты подключают модули через `tools/lib/loader.luau` (эмулирует `script.Parent` и `require`).

## Общие модули (src/shared) — уже написаны, это контракт

| Модуль | Что даёт |
|---|---|
| `Config` | все настройки: цвета молний, типы ударов, острова (`Config.Zones[i]`), улучшения, перегрузка, события, город, награды, коды |
| `Strikes` | `windows(rodLvl, bonusMs)`, `judge(dt, perfect, good)`, `comboMult`, `rollColor(zone, luck, roll, boostGold)`, `upgradedColor`, `rollKind`, `hitOffsets`, `overchargeRisk(fill, insLvl)`, `ringProgress(kind, t01)`, `runnerPosition` |
| `Economy` | `upgradeCost`, `rodMult`, `jarCapacity`, `walkSpeed`, `rateMult`, `extraRings`, `zapStun`, `effectText`, `catchCharge(zone,color,grade,combo,rodLvl,eventMult)`, `maxCharge`, `sellValue(charge,cap,mult)`, `multiplier(data, {friends, cityBoost, now})`, `petBonuses`, `fulgBonus`, `fulgRecordBonus`, `indexRows`, `petSlots`, `zoneCost`, `rebirthCost`, `rebirthMult`, `canRebirth`, `incomeMinutes(data, min)`, `updateIncomeRate` |
| `Zones` | геометрия: `Geo[i]` (Center, Dir, ToHub, Right, Entrance, Spawn, SellPad, Landmark, BridgeStart, BridgeEnd, Gate), `Hub` (Spawn, Tower, Shop, Hatchery, Gallery, Rebirth, Daily, BoardLeaders, BoardForecast), `zoneAt(pos)` (0 хаб, 1..5, nil), `inPlayArea`, `candidate`, `clampToPlay`, `groundY`, `spawnFor`, `flatDist`, `SellPadRadius`, `HubSellRadius` |
| `Pets` | виды, коконы, `roll(cocoon, roll, pity)`, `chances`, `totalBonus`, `bonusText`, `Rarities`, `RarityOrder`, `StarterPet`, `MaxInventory` |
| `Fulgurite` | `generate(seed, color, mut) -> Spec{Shape, ShapeName, Rarity, Bonus, Height, Parts{CFrame,Size,Kind,Shape}}`, `rollDrop`, `rollMutation`, `title`, `glassColor`, `Mutations`, `MaxInventory`, `MaxEquipped` |
| `BoltGeometry` | `build(seed, from, to, detail) -> {Segment{A,B,Width,Branch}}`, `segmentCFrame` |
| `Geom` | `axisCFrame(a, b) -> (CFrame, length)` — цилиндр между точками без сбоев на вертикали |
| `Prng` | детерминированный ГСЧ: `Prng.new(seed)` с `:next() :range() :int() :chance()`, `Prng.hash(a, b)` |
| `Rng` | `pick(weighted, roll)`, `chances` |
| `PlayerData` | тип `Data`, `default()`, `reconcile(raw)`, `serialize`, `onSessionStart`, `petKind`, `equippedKinds`, `findFulg` |
| `Quests` | `Pool`, `def(id)`, `dayNumber(t)`, `forDay(day, userId, zone)` |
| `Net` | типы сообщений `StrikeMsg`, `StrikeResultMsg`, `BoltMsg`, `ShardMsg`, `EffectMsg`; `Net.Actions`; `Net.event/unreliable/func(name)`; `Net.gameState()`; `Net.PlayerAttrs` |
| `SoundIds` | проверенные ID: `Sfx`, `Ambient`, `Music` |
| `Format` | `short(n)` (1.2K), `full`, `time`, `plural`, `mult`, `percent` |
| `Signal` | простой сигнал |
| `Loc` | локализация: `t`, `tl`, `plural`, `msg`, `pmsg`, `render`, `renderIn`, `setWorldText`, `worldText`, `encode`/`decode`, `pick`, `lang`/`setLang`, `upper` (см. «Локализация») |
| `Strings/*` | английские словари `{ ["русский исходник"] = "English" }`; `Strings/Shared.luau` — глоссарий |

## Сеть

RemoteEvent (в `ReplicatedStorage.Remotes`): `DataSync`, `StrikeSpawn`, `StrikeResult`, `Catch`, `ShardSpawn`, `ShardCollect`,
`Notify`, `Banner`, `Effect`; UnreliableRemoteEvent: `BoltFX`; RemoteFunction: `Request`.

| Событие | Направление | Аргументы |
|---|---|---|
| DataSync | S→C | `(data: PlayerData.Data)` — снимок, не чаще ~6 раз/с; неизменные тяжёлые разделы (`Pets`, `Fulgs`, `Index`) сервер может не прислать — тогда в снимке `Keep = { "Pets", ... }`, и клиент берёт их из прошлого снимка (полный — первый и не реже `Config.Server.FullSyncEvery` с) |
| StrikeSpawn | S→C | `(msg: Net.StrikeMsg)` |
| StrikeResult | S→C | `(msg: Net.StrikeResultMsg)` |
| Catch | C→S | `(strikeId: number, hit: number, tapTime: number)` — tapTime = `workspace:GetServerTimeNow()` в момент нажатия **уже с** поправкой задержки из настроек; сервер сам оценивает ближайший к tapTime неоценённый удар кольца (`hit` — только проверка), tapTime принимается в окне `[now − (2 × пинг + TapLateSlack), now + TapAheadSlack]` (± поправка) |
| ShardSpawn | S→C | `(msg: Net.ShardMsg)` |
| ShardCollect | C→S | `(shardId: number)` |
| Notify | S→C | `(text: Net.Text, kind: "info"|"good"|"bad"|"rare")` — короткий тост |
| Banner | S→all | `(text: Net.Text, kind: string, color: Color3?)` — баннер на весь сервер (редкая поимка, событие) |
| Effect | S→C/all | `(msg: Net.EffectMsg)` |
| BoltFX | S→C (ненадёжно) | `(msg: Net.BoltMsg)` — чужие молнии в той же зоне, только для красоты |
| Request | C→S RemoteFunction | `(action: string, payload: any) -> (ok: boolean, result: any)`; при `ok=false` result — текст ошибки (`Net.Text`) |

`Net.Text = string | Loc.Msg` — текст для игрока от сервера: строка-исходник или `Loc.msg(...)`; клиент рисует его через
`Loc.render` на своём языке (сервер языка игрока не знает и сам не переводит).

`Net.gameState()` — папка `ReplicatedStorage.GameState`, сервер создаёт её при старте и пишет атрибуты:
`CityPoints, CityTarget, CityLit (0..6), CityBoostUntil, Event ("", "supercell", "ball", "rainbow"), EventEnds,
NextSupercell, NextBall, NextRainbow, BallZone, BallHp, BallMaxHp, BallFrom, BallTo, BallStart, BallEnd`.
Все времена — серверные (`workspace:GetServerTimeNow()`).

Атрибуты игрока (`Player`), ставит сервер: `Zone, Combo, JarFill (0..1.5), Pets ("iskorka,luchik"), ZappedUntil, BestCombo,
Rebirths, Title, FriendCount, RodTier (0..5)`.

## Карта (src/map/Map.rbxmx → Workspace.Map)

Генерирует `tools/gen_map.luau` из `Zones`/`Config` (позиции совпадают с логикой). Все детали якорные; декор без коллизий и запросов.
Метки для кода — папка `Workspace.Map.Markers`, невидимые детали (Transparency 1, CanCollide/CanQuery/CanTouch false) с именами:
- `Spawn_0` (хаб), `Spawn_1..5` — точки появления.
- `SellPad_0` (кольцо вокруг Тесла-башни), `SellPad_1..5` — подстанции. Видимые подстанции — модели в `Map.Stations`.
- `Gate_2..5` — энергобарьер на мосту (видимый барьер — деталь `Map.Gates.Gate_N` с атрибутом `Zone`, материал ForceField; сервер не трогает, клиент прячет открытые барьеры для своего игрока; сервер не пускает игрока на закрытый остров).
- `Kiosk_Shop`, `Kiosk_Hatchery`, `Kiosk_Gallery`, `Kiosk_Rebirth`, `Kiosk_Daily` — где сервер ставит ProximityPrompt (открывают окна у клиента через атрибут/Effect).
- `Cocoon_meadow`, `Cocoon_ice`, `Cocoon_storm` — стойки коконов в инкубатории.
- `Pedestal_1..12` — пьедесталы галереи фульгуритов.
- `Board_Leaders`, `Board_Forecast`, `Board_Hall` — щиты с SurfaceGui (сервер заполняет текст).
- `Tower_Top` — верх Тесла-башни (для дуг), `Tower_Coil_1..4` — катушки.
- `City.District_1..6` — папки окон кварталов (детали с атрибутом `OnColor`), клиент их зажигает.
- `Clouds_1..5` — потолок туч островов (из него бьют молнии; высота = GroundY + Config.CloudHeight).

## Сервер (src/server)

`Main.server.luau` создаёт `GameState`, вызывает `start()` сервисов в порядке: Data → Player → Economy → Strike → Pet → Fulgurite →
Event → City → Daily → Leaderboard → Tutorial → Request (роутер). Сервисы — ModuleScript в `Services/`, у каждого `start()`.

| Сервис | Ответственность и API для других сервисов |
|---|---|
| `DataService` (готов) | `get(p)`, `update(p, fn)`, `markChanged(p)`, `waitFor(p)`, `Loaded`, `Changed`, `BeforeSave`, `addBeforeSave`, `isPersistent` |
| `SyncService` | на `DataService.Changed` — отправить `DataSync` (троттлинг 0.15 с) |
| `RequestService` | `RequestService.handle(action, fn(player, payload) -> (ok, result))`; лимит ~10 запросов/с на игрока; pcall вокруг обработчиков |
| `PlayerService` | персонаж: скорость `Economy.walkSpeed`, громоотвод (Tool, ManualActivationOnly, хват вертикально), банка на спине (стекло + неоновое ядро; клиент сам масштабирует ядро по `JarFill`), табличка над головой (ник, титул — атрибут `Title` из достижений: Перун, радужная, золотая, перезапуски; рекорд серии), свечение громоотвода — цвет перезапуска, дуги Перуна у поймавших Чёрную; слежение за зоной (атрибут `Zone`, `data.LastZone`), запрет входа на закрытые острова (отбросить к барьеру; у барьера следующего острова — цена, хватает Вольт — `Effect openWindow` «Shop:islands»), после появления/телепорта/возврата — `Effect face` (камера за спину), возврат при падении ниже `Config.VoidY`, появление на `Zones.spawnFor(LastZone)` (новичок — остров 1). API: `getZone(p): number`, `getRoot(p): BasePart?`, `zap(p, stun)`, `teleport(p, zone)`, `refreshStats(p)`, `ZoneChanged: Signal<Player, number, number>` |
| `EconomyService` | банка и Вольты. API: `addCharge(p, amount, zone) -> (added, burst, lost)` (учитывает перегрузку, риск через `Strikes.overchargeRisk`, `Config.Zones[z].Overcharge`), `capacity(p)`, `fill(p)`, `sell(p, source)` (подстанции: проверка позиции раз в 0.25 с; дрон — `Config.Drone.TripTime` задержка), `multiplierFor(p)`, `grantVolts(p, amount, reason)`, `grantShards(p, amount)`; обработчики Request: BuyUpgrade, UnlockZone, BuyDrone, ToggleDrone, Rebirth, Teleport; отслеживает доход в минуту (`IncomeRate`), атрибут `JarFill`; сигналы `Sold: Signal<Player, number volts, number fill>`, `Purchased` |
| `StrikeService` | потоки ударов каждого игрока в зоне 1..5 (не в хабе): интервал `Interval / (rateMult × eventRate)`, лимит `MaxActive + extraRings (+ event)`, позиция через `Zones.candidate` + `inPlayArea` + зазор между кольцами + достижимость (расстояние/скорость < предупреждения × 0.85); первое кольцо новичку через `FirstStrikeDelay` прямо перед ним (мягкое кольцо предлагается снова, пока новичок не поймал первую молнию). Цвет: `Strikes.rollColor` с удачей питомцев и бустом золота события; 5% «переливаются». Чёрная молния Перуна на острове 5 с шансом `Config.Events.Perun.Chance`. Обработка `Catch`: проверки (удар свой/общий и активен, этот hit ещё не оценён, `|tap − now| ≤ MaxTapAge`, позиция в радиусе + допуск), оценка `Strikes.judge`, заряд `Economy.catchCharge` → `EconomyService.addCharge`; комбо и его таймаут; МИМО/ШАРАХНУЛО по правилам зоны; после последнего удара без нажатия: игрок в кольце → zap (если `Penalties`), вне кольца → осколок (`ShardSpawn`), собирать — `ShardCollect` с проверкой расстояния. Цепная молния. Молниедекс (`data.Index["z:color"]`). Рассылка `BoltFX` игрокам той же зоны. Шанс фульгурита → `FulguriteService.tryDrop` (радужная/чёрная — при любой поимке, до `StrikeResult`). API для событий: `spawnShared(zone, pos, color, opts) -> id` (общий удар для всех в зоне), `CatchResolved: Signal<Player, info>` (для заданий/событий: grade, color, zone, combo, shared tag) |
| `PetService` | Request: Hatch (осколки, остров, инвентарь, pity, `Pets.roll`), EquipPet/UnequipPet (лимит `Economy.petSlots`), DeletePet, EquipBest; атрибут игрока `Pets`; стартовый питомец после первой сдачи; баннер за легендарного+ |
| `FulguriteService` | `tryDrop(p, color, zone, eventTag) -> FulgRecord?` (seed = `Prng.hash(userId, serial)`), Request: EquipFulg/UnequipFulg/DeleteFulg (удалить → осколки по редкости); пьедесталы галереи: лучший надетый фульгурит каждого игрока строится из `Fulgurite.generate` на `Pedestal_N` с табличкой |
| `EventService` | расписание по серверному времени: Суперячейка (модификаторы `rateMult()`, `chargeMult()`, `goldBoost()`), Шаровая молния (остров с макс. игроков, путь по `Zones.clampToPlay`, общие кольца каждые `HitInterval`, HP = игроки × HpPerPlayer, награда по вкладу), Радужная молния (`Effect rainbowWarn` за `Announce` с, затем огромное общее кольцо на каждом острове с игроками (все в хабе — на острове 1); награда — `RewardMinutes` дохода + гарантированный радужный фульгурит каждому поймавшему), Перун (баннер «бьёт рядом с …», `Effect perun` всем; поймали — баннер с ловцом и «Я видел!» тем, кто в радиусе; не поймали — «ушла»). Атрибуты GameState. API: `rateMult()`, `chargeMult()`, `goldBoost()`, `current(): string` |
| `CityService` | на `EconomyService.Sold`: очки = заполнение банки (≤1.5); цель `PointsBase + PointsPerPlayer × игроки`; `CityLit` = доля × 6; при заполнении — `CityBoostUntil = now + CityBoostDuration`, баннер, `Effect cityLit`; после буста — сброс с плавным гашением. API: `boostActive(): boolean` |
| `DailyService` | календарь (`Config.DailyRewards`, серия, прощённый 1 день), задания (`Quests.forDay`, прогресс от `StrikeService.CatchResolved`, `EconomyService.Sold`, вылуплений, осколков), коды (`Config.Codes`, регистр не важен), офлайн-доход (`Welcome`, Request ClaimWelcome), бусты ×2 (`data.Boosts.Volts2x`) |
| `LeaderboardService` | leaderstats (NumberValue `Volts` и IntValue `Rebirths`, исходник имени — атрибут `Loc_Name`, значения ищутся по классу), глобальная таблица `OrderedDataStore` по `TotalVolts` (обновление раз в 3 мин, в pcall), заполнение `Board_Leaders`, `Board_Hall` (радужные ловцы сервера), `FriendCount` (друзья на сервере, `Player:IsFriendsWith` в pcall с кэшем) |
| `TutorialService` | Request TutorialStep (флаги в `data.Tutorial`: "catch", "sell", "shop", "pet", "zone2", "overcharge"); выдача стартового питомца |

Правила сервера: сервер — единственный источник правды (Вольты, заряд, оценки, награды). Клиенту никогда не доверяем
суммы, позиции колец, цвета. Все обработчики Remote — с проверкой типов аргументов и в pcall. Без `wait()/spawn()/delay()` —
только `task.*`. Без устаревших API.

## Клиент (src/client)

`Main.client.luau` запускает: ClientState → выбор языка (`Loc.setLang`, до запуска модулей) → Sounds → Juice → WorldFX → WorldText →
StrikeController → CatchController → CharacterFX → PetsFX → UI (HUD, Notifications, окна) → Tutorial.

| Модуль | Ответственность |
|---|---|
| `ClientState` | зеркало данных: `data`, `Changed: Signal<Data>`, `get()`, `waitForData()`, `zone()` (атрибут Zone), `multiplier()`, `capacity()`, `windows()`, `request(action, payload) -> (ok, result)` (вызов Request с тостом ошибки), сигналы `StrikeSpawned`, `StrikeResolved`, `Effect`, `ComboChanged` |
| `Controllers/Sounds` (готов) | `play(name, pitch, vol, vary)`, `ladderPitch(step)`, `playMusic(name)`, `setAmbient(name, on)`, `setMusicEnabled`, `setSfxEnabled` |
| `Controllers/Juice` (готов) | `popup(pos, text, color, big)`, `shake(amount)`, `fovPunch(deg)`, `flash(color, strength)` |
| `Controllers/StrikeController` | рисует кольца (диск со значком цвета, сжимающееся внешнее кольцо по `Strikes.ringProgress`, туча над ним разгорается, «ниточка» в последние 0.3 с, переливание цвета на `UpgradeAt`, бегущее кольцо ползёт), молнии (`BoltGeometry`, пул неоновых цилиндров: белое ядро + цветная оболочка, видны 0.15 с, гаснут 0.3 с), вспышку света (≤3 PointLight одновременно, «мягкие вспышки» из настроек), ударную волну, искры (встроенные текстуры частиц), осколки на земле (сбор по расстоянию → `ShardCollect`), чужие молнии `BoltFX` (упрощённо), стрелки к кольцам за краем экрана; API: `activeStrikes()`, `targetFor(rootPos, tapTime) -> (id?, hit?, inside)`, `UntappedHit` (стоял в кольце и не нажал) |
| `Controllers/CatchController` | кнопка ⚡ ЛОВИ (её рисует HUD, контроллер подписывается), E/ЛКМ на ПК, R2/R1 на геймпаде (Пробел — прыжок, X — подсказкам); выбор цели (ближайший по времени неоценённый удар); отправка `Catch` с поправкой задержки; мгновенная локальная оценка той же `Strikes.judge` (звук и надпись без ожидания сервера), результат сервера уточняет (и поправляет надпись); стоял в кольце и не нажал — «ШАРАХНУЛО» сразу у себя (с зоны 2), в зоне 1 подсказка; лесенка звука по комбо; автоподстройка задержки (средняя ошибка последних 10 нажатий) |
| `Controllers/CharacterFX` | банка на спине каждого игрока: ядро по `JarFill`, краснеет и трещит при перегрузке; свечение громоотвода по `Combo`; «Шарахнуло» по `ZappedUntil` (сажа через Highlight, искры над головой); дуги цепной молнии |
| `Controllers/PetsFX` | питомцы всех игроков по атрибуту `Pets`: модели из `Models.pet(kind)`, парят и кружат (BulkMoveTo), у чужих — упрощённо |
| `Controllers/WorldFX` | освещение по зоне (`Config.Zones[i].Sky` / `Config.Hub.Sky`, плавный твин Atmosphere/ColorCorrection/Ambient), дождь у камеры, далёкие вспышки в тучах, дрейф туч, дуги Тесла-башни, барьеры открытых островов прячутся, кварталы города (`CityLit`) зажигаются волной от центра, настроение событий (Суперячейка — зелёное небо), вспышка Перуна, музыка и фон по зоне/событию |
| `Controllers/WorldText` | надписи в мире на русском клиенте: таблички, табло, подписи над головой, ProximityPrompt и столбцы leaderstats — подменяет свойство локально по атрибуту `Loc_<свойство>` (на английском клиенте ничего не делает) |
| `Controllers/Tutorial` | стрелка-луч к цели и короткая подсказка: встань в круг → жми ⚡ → сдай банку → купи улучшение → питомец → мост на остров 2; шаги по флагам `data.Tutorial` и событиям |
| `Fonts` (src/shared/Fonts.luau) | шрифты игры (docs/STYLE.md §8.3), один источник для UI и серверных табличек: `Display` (Montserrat Black Italic), `DisplayFlat`, `Number` (Oswald Bold), `Body` / `BodyHeavy` (Nunito 700/800), `All` для прогрева в Main.client. У всех полная кириллица; BuilderSans кириллицы не имеет |
| `Models` (src/shared/Models.luau) | строители моделей из примитивов (для сервера, клиента и Lune-превью): `rod(tier)`, `jar()`, `pet(kind)`, `cocoon(id)`, `fulgurite(spec, glassColor)`, `station()`, `ballLightning()` (детали якорные, без сварки — их крутит EventFX), рецепты пулов StrikeController `strikeCloudRecipe()` и `shardRecipe()`. Возвращают Model/Tool, не родительствуют |
| `UI/*` | `HUD` (Вольты/осколки, полоса банки с перегрузкой и риском, кнопка ЛОВИ, комбо, таймер события, шкала города, кнопки меню слева выше джойстика, надписи оценки, тосты), `Notifications` (тосты + баннеры), `ShopUI`, `PetsUI` (+ анимация вылупления), `CollectionUI` (фульгуриты с ViewportFrame + Молниедекс), `TeleportUI`, `RebirthUI`, `DailyUI` (календарь, задания, коды), `SettingsUI` (язык, музыка, звуки, мягкие вспышки, тряска, задержка), `WelcomeUI` |

Правила клиента: всё визуальное — только на клиенте; сервер не создаёт эффектов. Пулы деталей, лимиты частиц, `CastShadow=false`
у мелочи, `CanQuery/CanTouch=false` у эффектов. Не перекрывать левые 40% нижних 2/3 экрана (джойстик) и кнопку прыжка.
Кнопки ≥ 56 px. Тексты короткие. Числа — `Format.short`.

## Локализация

Игра для всего мира: **английский — язык по умолчанию**, русский — у игроков с русской локалью Roblox или выбравших его
в настройках. Ядро — `src/shared/Loc.luau` (правила — в его шапке), словари — `src/shared/Strings/*.luau`.

**Исходник — русский.** Строка для игрока пишется в коде по-русски и сразу оборачивается в `Loc.*`; эта русская строка —
и текст для русского игрока (ровно как раньше), и ключ словаря. Английский перевод лежит в словаре:
`["Банка: %d / %d"] = "Jar: %d / %d",` (одна запись на строку, `"` экранируется `\"`).

**Язык игрока.** `Loc.pick(Settings.Lang, локаль)`: настройка `"en"`/`"ru"` важнее локали; пустая настройка — по локали Roblox
(`LocalizationService.RobloxLocaleId`, иначе `Player.LocaleId`): `ru*` → русский, всё остальное (`en-us`, `pt-br`, пусто) → английский.
`Main.client` выбирает язык до запуска контроллеров и окон (ждёт данные до 6 с), поэтому тексты можно строить один раз при старте
модуля. Смена языка в настройках (`SettingsUI`, `Settings.Lang`) применяется после перезахода.

**Клиент** рисует текст сам:
- `Loc.t("Банка полна!")`, с аргументами `Loc.t("Банка: %d / %d", a, b)` — плейсхолдеры и их порядок в переводе те же;
- строковые аргументы, которые сами есть в словаре (имена питомцев, островов, цветов, редкостей), переводятся автоматически:
  `Loc.t("Вылупился %s!", def.Name)`; данные показываются через `Loc.t(def.Name)`;
- множественное число — одной строкой: `Loc.plural(n, "минута|минуты|минут")` ↔ `"minute|minutes"` (3 формы → 2);
- одна русская строка с двумя разными переводами — ключ с контекстом `"ctx::Исходник"`
  (`"kind::Обычный"` = Normal, а редкость `"Обычный"` = Common); по-русски показывается часть после `::`.

**Сервер** языка игрока не знает и `Loc.t` не вызывает. Текст для клиента (Notify, Banner, ответы и ошибки Request, любые
показываемые поля сообщений) — `Loc.msg("Исходник %s", аргументы...)` (таблица `{ fmt, ... }`) или простая строка-исходник;
клиент рисует его через `Loc.render(x)`. Множественное число внутри — аргумент `Loc.pmsg(n, "минуту|минуты|минут")`,
вложенные `Loc.msg` тоже можно. В общих модулях есть пары «клиент/сервер»: `Quests.text`/`Quests.msg`,
`Pets.bonusText`/`Pets.bonusMsg`, `Fulgurite.title`/`Fulgurite.titleMsg`.

**Надписи в мире** видят игроки на разных языках сразу. Сервер ставит их через `Loc.setWorldText(inst, "Text", "Исходник %s", ...)`:
в свойство (`Text`, `ActionText`, `ObjectText`, у leaderstats — `Name`) пишется английский, в атрибут `Loc_<свойство>` —
исходник (`Loc.encode`). Русский клиент подменяет свойство локально (`Controllers/WorldText`, следит и за атрибутом, и за
свойством). Заглавные — атрибут `LocUpper = true` до вызова. Таблички карты делает `B.text` (`tools/lib/builder.luau`):
в `tools/map/*` поле `Text` — русский исходник (или `Loc.msg(...)`), переводы — в `Strings/Map.luau`.

**Правила** (их проверяет `python3 tools/check_loc.py`, он же входит в `tools/build.sh`):
1. `Loc.t / msg / plural / pmsg / setWorldText` — всегда прямой вызов со строковым литералом-исходником (без псевдонимов
   `local L = Loc.t` и без склейки ключа); динамический ключ — только для имён из данных (`Loc.t(def.Name)`, `Loc.t("kind::" .. name)`).
2. Склейку `"Ловец: " .. name` заменять форматом `Loc.t("Ловец: %s", name)`.
3. Не переводятся: логи (`warn/print/error`), имена объектов для поиска, атрибуты, имена действий и окон, ключи DataStore, id
   данных, строки для сравнения в логике (сравнивать id, не текст). Строку не для игрока можно пометить `-- noloc` в конце строки кода.
4. Чекер падает, если: у ключа нет перевода; плейсхолдеры перевода не совпадают с исходником; у множественного числа не 2 формы;
   один ключ в двух словарях переведён по-разному (общий ключ — тот же перевод или `ctx::`); в переводе кириллица; русская строка
   в коде не обёрнута в `Loc.*` и не помечена `-- noloc`; имя/описание в данных `src/shared` или табличка карты без перевода.

**Словари** (`src/shared/Strings/`, все подключает `Loc.luau`): `Shared` — глоссарий и данные (Config, Pets, Quests, Fulgurite,
Economy), `Server`/`Server2` — тексты сервисов, `HUD`, `ShopPets`, `Windows`, `Windows2`, `Controllers` — клиент, `Map` — таблички.
Английские термины игры — только из глоссария (Volts, Shards, Jar, Charge, Combo, Overcharge, Substation, Sparklings, Boltdex,
Rebirth, острова и события).

**Как добавить строку:** написать в коде `Loc.t("Новая строка %d", n)` (на сервере — `Loc.msg(...)`), добавить
`["Новая строка %d"] = "New line %d",` в словарь своей области, запустить `python3 tools/check_loc.py` (должно быть 0 ошибок).
Английский — короткий и живой (аудитория 9–16 лет), не длиннее русского: окна рассчитаны на русский текст.

**Проверки:** юнит-тесты `Loc` в `tools/tests/run.luau` (поиск, `ctx::`, множественное число, вложенные сообщения,
`encode/decode`, `pick`, сломанный перевод); `tools/tests/server_sim.luau` сверяет тексты сервера по-русски
(`Loc.renderIn("ru", x)`) и по-английски, проверяет, что всё показанное игрокам переводится; эмулятор (`tools/sim`, сценарий `core`):
BotTwo — с локалью `ru-ru` (русский интерфейс и надписи в мире), остальные — `en-us`; у английских ботов в интерфейсе не должно
появиться ни одной кириллической строки, BotTwo переключает язык в настройках и после перезахода играет по-английски.
