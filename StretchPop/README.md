# STRETCH-POP

Физический мультяшный симулятор-платформер для Roblox: резиновые руки, рогатка по закону Гука, пружинный шар с рикошетами, пробитие стен по кинетической энергии, а в конце полосы Гонг Эволюции, после удара в который локация перерождается в новый тир.

## Как открыть

1. Скачай `build/StretchPop.rbxlx`.
2. В Roblox Studio выбери **File → Open from File…** и укажи этот файл.
3. Нажми **Play (F5)**.

Сохранения: в неопубликованном месте профиль живёт только одну сессию, в Output об этом будет предупреждение. Чтобы данные сохранялись, опубликуй место и включи *Game Settings → Security → Enable Studio Access to API Services*.

## Управление

| Ввод | Действие |
|---|---|
| ЛКМ / ПКМ (геймпад L2 / R2) | Выстрелить левой / правой рукой в точку под прицелом |
| Держать на земле | Рогатка: персонаж оттягивается назад, дуга показывает полёт |
| Отпустить | Запуск, v = √(2E/m), E = Σ½kx² |
| Держать в воздухе | Банджи: резинка укорачивается и тянет к точке |
| Пробел в полёте | Пружинный шар: рикошеты с сохранением импульса, каждый даёт +1 к комбо |
| TAB / ALT / кнопка «ПРОКАЧКА» (геймпад Y) | Панель прокачки и магазин перчаток; курсор освобождается |

Пробить стену можно, если ½·m·v² ≥ прочности. Удар по Гонгу засчитывается при скорости ≥ 140 и комбо ≥ 2 на первом тире; дальше пороги растут, они написаны на табличке над Гонгом.

## Структура

```
src/
  ReplicatedStorage/Shared/        общий код клиента и сервера
    Types.luau                     типы, в том числе профиль игрока
    Net.luau                       RemoteEvent'ы (объявлены в default.project.json)
    Config/{Physics,Level,Glove,Sound}Config.luau   SoundConfig: все ID звуков и частоты в одном месте
    Math/{Bezier,Spring}.luau      кривые Безье и пружины по закону Гука
    Physics/StretchPhysics.luau    резинки, запуск, энергия, отскоки (одни формулы для клиента и сервера)
    Data/ProfileTemplate.luau      шаблон профиля, санитайзер, миграции
    Util/Signal.luau
  ServerScriptService/Server/
    Main.server.luau
    Services/KineticLevelAndRebirthService.luau   пробитие, валидация, Гонг, мутация локации
    Services/PlayerDataService.luau               DataStore с сессионным замком
    Services/ProgressionService.luau              прокачка статов, перчатки, синхронизация профиля, антиспам
    Services/StretchReplicationService.luau       руки и шар других игроков
    Level/LevelBuilder.luau                       детерминированная генерация полос
  StarterPlayer/StarterPlayerScripts/Client/
    Main.client.luau
    Controllers/ElasticSlingshotController.luau   рогатка, руки на Безье, дуга траектории, шар
    Controllers/ShoulderCameraController.luau
    Controllers/KineticLevelClient.luau
    Controllers/StretchHUDController.luau         пружинный мультяшный HUD, панель прокачки, магазин
    Controllers/StretchAudioController.luau       процедурный звук: натяжение, ветер, пентатоника, резонанс
    Effects/KineticVFX.luau                       Squash & Stretch, обломки, волна перерождения
```

## Свои звуки

Все слоты лежат в `src/ReplicatedStorage/Shared/Config/SoundConfig.luau` → `Sounds`. Чтобы подставить свой ассет, поменяй `Id` на `"rbxassetid://<id>"`. Питч, громкость, фильтры, ноты и реверберацию задаёт процедурный слой контроллера, а не сам файл. По умолчанию в слотах стоят встроенные звуки клиента Roblox (`rbxasset://sounds/...`), поэтому всё звучит сразу после запуска.

## Разработка

- Сборка места: `rojo build default.project.json -o build/StretchPop.rbxlx`. Живая синхронизация со Studio: `rojo serve`.
- Тесты запускаются в [Lune](https://github.com/lune-org/lune) из корня `StretchPop`:
  - `lune run tests/compile_all.luau`: синтаксис всех файлов;
  - `lune run tests/run_tests.luau`: математика, физика, профиль, генерация полос, постройка полос настоящими Instance, SoundConfig, экономика прокачки;
  - `lune run tests/server_sim.luau`: сервер в мок-движке (вход, пробитие, античит, респаун, Гонг, Rebirth, прокачка, перчатки, синхронизация, спам);
  - `lune run tests/client_sim.luau`: клиент в мок-движке (рогатка, полёт, пробитие, шар, банджи, Гонг, пиры, камера, HUD, панель и покупки, аудио);
  - `lune run tests/place_check.luau`: структура собранного `.rbxlx`.
