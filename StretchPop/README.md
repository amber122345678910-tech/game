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
| ALT | Освободить или снова захватить курсор |

Пробить стену можно, если ½·m·v² ≥ прочности. Удар по Гонгу засчитывается при скорости ≥ 140 и комбо ≥ 2 на первом тире; дальше пороги растут, они написаны на табличке над Гонгом.

## Структура

```
src/
  ReplicatedStorage/Shared/        общий код клиента и сервера
    Types.luau                     типы, в том числе профиль игрока
    Net.luau                       RemoteEvent'ы (объявлены в default.project.json)
    Config/{Physics,Level,Glove}Config.luau
    Math/{Bezier,Spring}.luau      кривые Безье и пружины по закону Гука
    Physics/StretchPhysics.luau    резинки, запуск, энергия, отскоки (одни формулы для клиента и сервера)
    Data/ProfileTemplate.luau      шаблон профиля, санитайзер, миграции
    Util/Signal.luau
  ServerScriptService/Server/
    Main.server.luau
    Services/KineticLevelAndRebirthService.luau   пробитие, валидация, Гонг, мутация локации
    Services/PlayerDataService.luau               DataStore с сессионным замком
    Services/StretchReplicationService.luau       руки и шар других игроков
    Level/LevelBuilder.luau                       детерминированная генерация полос
  StarterPlayer/StarterPlayerScripts/Client/
    Main.client.luau
    Controllers/ElasticSlingshotController.luau   рогатка, руки на Безье, дуга траектории, шар
    Controllers/ShoulderCameraController.luau
    Controllers/KineticLevelClient.luau
    Effects/KineticVFX.luau                       Squash & Stretch, обломки, волна перерождения
```

## Разработка

- Сборка места: `rojo build default.project.json -o build/StretchPop.rbxlx`. Живая синхронизация со Studio: `rojo serve`.
- Тесты запускаются в [Lune](https://github.com/lune-org/lune) из корня `StretchPop`:
  - `lune run tests/compile_all.luau`: синтаксис всех файлов;
  - `lune run tests/run_tests.luau`: математика, физика, профиль, генерация полос, постройка полос настоящими Instance;
  - `lune run tests/server_sim.luau`: сервер в мок-движке (вход, пробитие, античит, респаун, Гонг, Rebirth);
  - `lune run tests/client_sim.luau`: клиентский контроллер в мок-движке (рогатка, полёт, пробитие, шар, банджи, Гонг, пиры, камера);
  - `lune run tests/place_check.luau`: структура собранного `.rbxlx`.
