# Контракт строителей моделей (для разработчиков)

Модели катсцены собираются **кодом** (Lune при сборке места), а не руками в Studio. Каждый строитель —
ModuleScript в `src/shared/Builders/<Имя>.luau` с функцией `build(origin: CFrame): Model`.

## Общие правила

- Только встроенные детали: `Part` (Block/Ball/Cylinder), `WedgePart`, `SpecialMesh` с `MeshType = Sphere`
  (эллипсоид), `Beam`/`Attachment` для прядей, `ParticleEmitter`, `PointLight`. **Нельзя**: MeshPart, загруженные
  меши/текстуры по ID (кроме уже проверенных в `src/shared/Textures.luau`), CornerWedgePart, Union, Humanoid.
- Используйте помощники `Sculpt` (`src/shared/Builders/Sculpt.luau`): `newCharacter`, `ellipsoid`, `segment`,
  `box`, `wedge`, `cylinder`, `ball`, `capsule`, `strand`, `outline`, `light`, `hex`, `mix`.
- Координаты передаются **в осях кости в позе покоя**: X — вправо от персонажа, Y — вверх, −Z — вперёд (туда
  смотрит персонаж). Начало модели — на земле между стоп.
- Скелет (имена костей и пропорции) — `src/shared/Skeletons.luau`. Кости: Root, Hips, Spine, Chest, Neck, Head,
  (Jaw у Рики), ClavicleL/R, UpperArmL/R, LowerArmL/R, HandL/R, Index1..3L/R, Middle1..3, Ring1..3, Pinky1..3,
  Thumb1..3, UpperLegL/R, LowerLegL/R, FootL/R, ToeL/R, плюс особые: Katana (Юта), Pompadour (Рю), Mane (Рика).
  Позиция кости = сустав. Например геометрия плеча крепится к `UpperArmL` от (0,0,0) до (0,-upperArm,0).
- Каждая деталь крепится ровно к одной кости (атрибут `Bone` ставит Sculpt). Деталь, которая гнётся при
  сгибе сустава, лучше разбить на две, по одной на каждую кость, с перекрытием в суставе (сфера-«шарнир»).
- Ткань и мех, которые должны трепетать, — `opts.flutter = { amp = градусы, freq = Гц, hinge = точка шарнира
  в осях детали, axis = ось }`.
- Пряди (волосы, мех) — `Sculpt.strand(ctx, bone, points, opts)`: точки в осях кости, от корня к кончику;
  аниматор сам колышет их (вес точки растёт к кончику).
- Аниме-контур — `Sculpt.outline(ctx, цвет)` (один Highlight на модель).
- Обязательные имена: `SoleL`/`SoleR` — подошвы (для пыли от шагов). Рика: `Eye` (Neon, красный) и
  `PointLight` с именем `EyeLight` (через `Sculpt.light`). Рю: невидимая деталь `EnergyAnchor` у передней части
  помпадура (на кости Pompadour), её −Z смотрит вперёд.
- Бюджет деталей: Рика ≤ 1600, Рю ≤ 900, Юта ≤ 500, окружение ≤ 3500. Пряди: Рика ≤ 140, Рю ≤ 60, Юта ≤ 40.

## Проверка

```bash
../.tools/lune run tools/view_model.luau Rika /tmp/r.json walk Head
python3 tools/previz_render.py /tmp/r.json /tmp/rview --w 400 --h 400 --sheet 4
```

Превиз — грубая трассировка лучей (эллипсоиды, блоки, клинья, цилиндры, лучи-пряди, контур): он нужен,
чтобы видеть пропорции, силуэт и позы без Studio. Тестовые позы — `tools/test_poses.luau`.
