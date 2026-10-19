# Превью карты и моделей (офлайн-рендер)

Рендерер приближённо показывает, как сцена выглядит в Roblox: детали (Block/Ball/Cylinder/Wedge/CornerWedge),
неон со свечением (bloom), стекло, ForceField, точечные источники света, тени, туман атмосферы,
ночное небо со звёздами. **Не рисует** частицы, лучи (Beam), террейн и текст SurfaceGui
(таблички выглядят тёмными прямоугольниками — в игре на них будет текст).

Все команды — из папки `LightningCatchers/`. Бинарники лежат в `.tools/` (`lune`, `rojo`).

## Один раз

```
cd tools/preview && npm install --silent && cd ../..
```

## Карта

```
.tools/lune run tools/gen_map.luau                    # пересобрать src/map/Map.rbxmx (печатает число деталей)
.tools/lune run tools/preview/check_map.luau          # проверка: метки, игровые зоны, стены, бюджет деталей
.tools/lune run tools/preview/count_parts.luau src/map/Map.rbxmx 4   # где больше всего деталей
```

Рендер:

```
.tools/lune run tools/preview/cams_map.luau /tmp/cams.json all      # камеры из Zones: islands | hub | bridges | overview | all
cd tools/preview
../../.tools/lune run dump_scene.luau /tmp/map.json --project=../../default.project.json ../../src/map/Map.rbxmx
node render.mjs /tmp/map.json /tmp/map /tmp/cams.json 1280 720     # -> /tmp/map_<имя камеры>.png
```

* `--project=…` — взять освещение (Lighting, Atmosphere, Bloom) из Rojo-проекта; без него у `.rbxmx` нет освещения.
* `--sky=N` — освещение зоны, как его ставит клиент (WorldFX): Ambient, OutdoorAmbient, Atmosphere, Tint и Saturation
  из `Config.Zones[N].Sky` (`0` — `Config.Hub.Sky`), плюс цветокоррекция. Для видов с острова N берите `--sky=N`.
* `--cc` — добавить цветокоррекцию из проекта (ColorCorrection: Tint, Saturation, Contrast, Brightness).
* `--skip=Clouds_1,Clouds_2` — не выгружать экземпляры с такими именами (например, убрать тучи для вида сверху).
* `--only=Hub` — выгрузить только поддерево с этим именем.
* Можно рендерить и собранное место: `dump_scene.luau out.json LightningCatchers.rbxl` (освещение берётся из места).

Файл камер — JSON-массив:

```json
[{"name": "hub", "pos": [110, 70, 130], "look": [0, 10, 0], "fov": 60, "clockTime": 19.6}]
```

`clockTime` 19.6 — вечерняя гроза, как в игре (ночное освещение откалибровано под OutdoorAmbient Roblox).
Переменная `PREVIEW_TMP` задаёт папку для временных файлов (по умолчанию системная `/tmp`).

## Лист пропов (docs/STYLE.md §12, п. 2)

```
.tools/lune run tools/preview/props_sheet.luau /tmp/props.rbxmx     # деревья, ели, кусты, камни, кристаллы, фонарь, примитивы
cd tools/preview
../../.tools/lune run dump_scene.luau /tmp/props.json /tmp/props.rbxmx
node render.mjs /tmp/props.json /tmp/props /tmp/props_cams.json 1280 720
```

Лист проверяет и «кирпичики» стиля из `tools/lib/builder.luau` (GemCube, Pyramid4, HexPrism, HexPlate, Lobe, SkewPlate, Zigzag).
Высокий угол CornerWedge — локальный (+X, +Y, −Z): так считает рендерер, и так же у Roblox (WedgePart: высокая грань сзади, +Z; CornerWedgePart: верхняя вершина (+X, +Y, −Z)). Если в Studio пирамиды всё же выйдут «звёздами», поправьте `B.CORNER_YAW`.

## Модели (Models.luau)

```
.tools/lune run tools/preview/models_sheet.luau /tmp/sheet.rbxmx    # питомцы, коконы, громоотводы, банка, фульгуриты, тучка удара, шаровая молния
cd tools/preview
../../.tools/lune run dump_scene.luau /tmp/sheet.json /tmp/sheet.rbxmx
node render.mjs /tmp/sheet.json /tmp/sheet /tmp/sheet_cams.json 1280 720
```

`models_sheet.luau` сам пишет файл камер `<имя>_cams.json` рядом с `.rbxmx` (виды: archetypes, archetypes34, archetypesback,
archetypes12 — игровой масштаб, close_* и mark_* — крупные планы, pets, rarity, silhouette — тест силуэта, petsgame, cocoons,
cocoonclose, rods, rodheads, fulg, fulgclose, strike, shards, ball) и печатает число деталей, шаров и неона у каждой модели.
Второй аргумент — другая папка shared (копия «до»): так снимаются кадры «до/после» с теми же камерами.

## Как смотреть результат

PNG открывается любым просмотрщиком (или инструментом Read у агента). Несколько видов удобно склеить
в один лист через Pillow (`Image.paste` уменьшенных копий 2×2) — так быстрее сравнивать итерации.

## Правила детализации (что проверять на рендерах)

* 5–8 базовых цветов на остров + один акцент (он же у колец и коллекционных вещей); разброс HSV у каждой детали.
* Тени со сдвигом оттенка: чем ниже скала, тем темнее и холоднее (к сине-фиолетовому).
* Силуэт 60% / отделка 30% / мелочь 10%; ничего не стоит по сетке; один высокий светящийся ориентир на остров.
* Неон — только акценты. Декор: якорный, без CanCollide/CanQuery/CanTouch; тени только у крупных деталей.
* Внутри PlayRadius земля ровная (GroundY): только мелкие цветы/травинки без коллизий и плоские пятна не выше +0.05.
* Бюджет всей карты для телефонов — цель ≤ 7600, потолок 8000 деталей (`check_map.luau` следит, docs/STYLE.md §11).
