# Aura Farmer — ролик в Roblox

Анимированная версия отрывка клипа «Aura Farmer» (15,6 с, 11 планов) целиком в Roblox Studio:
конь-«аурафармер» в фиолетовом костюме, люди на пляже, парк, спортзал с неоном, трон под прожектором,
субтитры как в клипе. Музыки и звуков в файле нет — их добавляешь сам.

## Как запустить

1. Скачай **`AuraFarmer.rbxl`** и открой в Roblox Studio (File → Open from File).
2. Нажми **Play** (F5). Через секунду чёрного экрана ролик пойдёт сам.
3. Для лучшей картинки: Studio Settings (Alt+S) → Rendering → **Editor Quality Level = Level 21** и **Quality Level = Level 21**,
   а во время Play в меню Roblox (Esc) → Settings → Graphics Quality — **ручной, максимум**.

### Клавиши во время Play

| Клавиша | Что делает |
|---|---|
| Пробел | пауза / продолжить |
| R | заново с начала |
| ← / → | назад / вперёд на 1 секунду |
| 1…9, 0, − | перейти к плану S01…S11 |
| T | субтитры вкл/выкл |
| B | чёрные рамки 16:9 (если окно другой формы) |
| L | повтор по кругу |
| H | таймкод и подсказка |

Shift+P в Play включает свободную камеру Roblox, если хочешь осмотреться.

## Музыка

1. Загрузи трек в Roblox (Creator Hub → Audio) и скопируй его ID.
2. В Studio: **SoundService → AuraFarmerMusic** → вставь ID в `SoundId` (вида `rbxassetid://123…`).
3. Если трек начинается раньше, чем этот отрывок, укажи атрибут **StartOffset** у звука — с какой секунды трека начинается ролик.
   Удобнее всего загрузить звук прямо из этого же видео — тогда StartOffset = 0.

Когда звук задан, ролик идёт строго по времени трека (синхронно). Темп песни ≈123 BPM, движения стоят на долях.

## Запись видео

В Studio нет встроенной записи длинного видео — используй OBS (захват окна, 60 к/с). Перед записью разверни окно
Studio на весь экран, нажми B, если экран не 16:9, и R для старта с начала.

## Что где лежит

| Где | Что |
|---|---|
| Workspace → AuraFarmer → Sets | декорации: Beach, Park, Gym, Throne |
| Workspace → AuraFarmer → Shots → S01…S11 | персонажи каждого плана, уже расставлены |
| ServerStorage → RBX_ANIMSAVES | **все анимации** (KeyframeSequence), по одной на персонажа плана |
| ReplicatedStorage → AuraFarmer → Shots | камера, свет и эффекты каждого плана (скрипты) |
| ReplicatedStorage → AuraFarmer → Lyrics | субтитры |
| SoundService → AuraFarmerMusic | сюда вставляешь музыку |

### Редактировать анимацию

Выдели персонажа (например `Shots → S04 → S04_Horse`), открой **Animation Editor** → «⋯» → Load → выбери анимацию плана.
После правки сохрани её (Save) с тем же именем — ролик подхватит изменения при следующем Play.

### Песок, вода и трава в редакторе

Terrain строится при запуске. Чтобы увидеть его без Play, выполни в Command Bar:

```lua
require(game.ServerScriptService.AuraFarmerServer.TerrainBuilder).build(workspace.AuraFarmer, true)
```

## Для разработчиков

Место целиком собирается кодом: `tools/build.sh` (Rojo + Lune), проверки — `tools/tests/run.luau`,
симуляция скриптов — `tools/tests/runtime_sim.luau`, превью кадров рядом с оригиналом — `tools/preview/film.sh`.
Подробности для исполнителей — `AGENTS.md`.
