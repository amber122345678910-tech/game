# Страница игры на Roblox: название, описание, локализация

Основной язык страницы и игры — **английский** (аудитория — весь Roblox). Русский — перевод для игроков
с русским языком: им Roblox покажет русские название и описание, а игра сама включит русский интерфейс.

## Английский (основной: Game Settings → Basic Info)

**Name** (до 50 символов):
```
⚡ Lightning Catchers
```
Вариант с тегом для обновлений: `[NEW] ⚡ Lightning Catchers`

**Description** (до 1000 символов):
```
⚡ A never-ending storm rages over the floating islands, and lightning is the ultimate treasure!

Step into a glowing ring and hit CATCH at the exact moment the bolt strikes. Nail it for a PERFECT catch, double charge and a growing combo. Miss, and you get a hilarious shock with your hair standing on end!

🫙 Fill the jar on your back and sell the charge at a Substation for Volts
🏝️ Unlock 5 islands: Storm Meadow, Copper Hills, Glass Dunes, Frost Peak and the Eye of the Storm
🌈 7 lightning colors, from Blue to the legendary Black Lightning of Perun (1 in 6,000!)
🐾 Hatch 21 Sparklings from cocoons
💎 Collect Fulgurites: every one is unique and numbered
🌩️ Server events: Supercell, Ball Lightning boss, Rainbow Lightning
🏙️ Light up Voltville together with your server for ×2 Volts
🔁 Rebirth, daily rewards and quests

Not a mindless clicker: it takes timing and quick feet!

🎁 CODES: LIGHTNING, PERUN, STORM

👍 Like and favorite for new islands!
```

**Иконка и обложка:** [`art/icon_512.png`](../art/icon_512.png), [`art/thumbnail_1920x1080.png`](../art/thumbnail_1920x1080.png) (английский логотип).
Русские версии: [`art/ru/`](../art/ru/).

## Русский (перевод: Creator Dashboard → игра → Localization → Russian → Experience Information)

**Название:**
```
⚡ Ловцы Молний
```

**Описание:**
```
⚡ Над летающими островами бушует вечная гроза, и молния здесь — настоящее сокровище!

Вбегай в светящееся кольцо и жми ЛОВИ ровно в момент удара. Попал идеально — двойной заряд и комбо. Промахнулся — смешной удар током, волосы дыбом!

🫙 Копи заряд в банке за спиной и сдавай его на подстанции за Вольты
🏝️ Открой 5 островов: Грозовой Луг, Медные Холмы, Стеклянные Дюны, Ледяной Пик и Око Бури
🌈 7 цветов молний, от голубой до легендарной Чёрной молнии Перуна (1 из 6000!)
🐾 21 питомец-искрёнок из коконов
💎 Собирай фульгуриты — у каждого свой номер, двух одинаковых нет
🌩️ События сервера: Суперячейка, Шаровая молния, Радужная молния
🏙️ Зажигайте город Электроград всем сервером и получайте ×2 Вольт
🔁 Перерождение, ежедневные награды и задания

Это не простое кликанье: нужны реакция и чувство ритма!

🎁 КОДЫ: МОЛНИЯ, ПЕРУН, ГРОЗА (или LIGHTNING, PERUN, STORM)

👍 Ставь лайк и добавляй в избранное — скоро новые острова!
```

## Настройки локализации

1. **Creator Dashboard → игра → Localization → Settings**: исходный язык (Source language) — **English**.
2. Добавь язык **Russian** и впиши русские название и описание (выше). Иконку и обложку тоже можно задать отдельно
   для русского языка — файлы в `art/ru/`.
3. Интерфейс игры переводить в Roblox не нужно: английский и русский встроены (`src/shared/Strings/`), язык выбирается
   по языку аккаунта, а в Настройках есть переключатель English / Русский.
4. По желанию: включить **автоматический перевод** Roblox для остальных языков (испанский, португальский и т. д.):
   Roblox переведёт английские надписи сам. Перевод машинный и не всегда точный для строк с числами — проверь его
   перед включением на популярных языках.
