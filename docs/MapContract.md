# Контракт карты (Workspace.House / Workspace.Lobby)

Генератор `tools/gen_map.luau` (Lune) пишет `src/map/House.rbxmx` и `src/map/Lobby.rbxmx`.
Скрипты находят объекты **по именам папок и атрибутам** — не по позициям. Все BasePart `Anchored = true`.
Декор без взаимодействия: `CanCollide=false, CanQuery=false, CanTouch=false` (кроме мебели-укрытий: CanCollide=true).

```
Workspace.House (Folder)
├─ Structure (Folder)            стены, полы, потолки, крыша, лестницы, забор, улица, соседние дома, фургон (декор)
├─ Furniture (Folder)            мебель: CanCollide=true, CanQuery=true (за ней можно присесть), CanTouch=false
├─ Rooms (Folder)                Part'ы-объёмы (Transparency 1, CanCollide/CanQuery/CanTouch=false)
│    атрибуты: RoomName (string), Floor (number: 0 подвал, 1, 2, 3 двор/улица), Outdoor (bool)
├─ Lights (Folder)
│    <RoomName> (Model)  атрибуты: RoomName, On=true
│       ├─ Bulb (Part, Material Neon когда включено; сервер меняет Material/Color)
│       │    └─ Light (PointLight, Range 18, Brightness 1.2, Shadows=true)
│       ├─ Switch (Part 0.4x0.6x0.2 у двери)  └─ Prompt (ProximityPrompt ActionText "Light", ObjectText "Switch")
│       └─ Candle (Part, Transparency 1 по умолчанию; с апгрейдом Candles сервер показывает) └─ Light (PointLight Range 9, Brightness 0.6, Color тёплый, Enabled=false)
├─ Doors (Folder)
│    <DoorId> (Model)  атрибуты: DoorId, Kind ("Entry"|"Interior"), Open=false, Locked=false, LockHP=100, Room A/B: RoomA, RoomB (string)
│       ├─ Hinge (Part невидимый, в точке петли; ориентация = закрытая дверь)
│       ├─ Panel (Part дверное полотно, CanCollide=true)  — поворачивается вокруг Hinge на ±100°
│       ├─ Prompt (ProximityPrompt в Panel: ActionText "Open", ObjectText "Door")
│       └─ LockPrompt (ProximityPrompt только у Entry: ActionText "Lock", HoldDuration 1, KeyboardKeyCode F)
│    DoorId: FrontDoor, BackDoor, GarageSide, GarageKitchen, LaundryDoor, BasementDoor, KidRoomDoor, ParentsRoomDoor, OfficeDoor, BathroomDoor
├─ Windows (Folder)
│    <WindowId> (Model) атрибуты: WindowId, Boards=0, Broken=false, Room (string)
│       ├─ Glass (Part, Transparency 0.55, Material Glass, CanCollide=true)
│       ├─ Board1, Board2, Board3 (Part доски, Transparency 1 по умолчанию, CanCollide=false)
│       ├─ Entry (Part невидимый снаружи окна — точка, откуда пациент ломает окно)
│       └─ Prompt (ProximityPrompt в Glass: ActionText "Board up", ObjectText "Window", HoldDuration 0.8)
│    WindowId: Living1, Living2, Kitchen1, Dining1, Laundry1  (все 1-й этаж). Окна 2-го этажа — декор без модели.
├─ HidingSpots (Folder)
│    <HideId> (Model) атрибуты: HideId, Kind ("Closet"|"Bed"|"Boxes"|"Shed"), Room (string), Occupied=""
│       ├─ HidePoint (Part невидимый, CFrame где стоит игрок внутри)
│       ├─ CamPoint (Part невидимый, CFrame камеры: смотрит наружу через щель)
│       ├─ Body (Part/Model видимая часть: шкаф, кровать, коробки)
│       ├─ Door (Part дверца шкафа, опционально)
│       └─ Prompt (ProximityPrompt: ActionText "Hide", ObjectText "Closet", HoldDuration 0)
│    HideId: ClosetKid, ClosetParents, ClosetOffice, BedKid, BoxesBasement, Shed
├─ Trees (Folder)
│    Slot1..Slot8 (Part невидимый, атрибут Slot=n, Planted=(n<=3))
│       └─ Tree (Model: Trunk, Crown) — у Slot1..3 есть сразу; у остальных создаёт сервер клоном `House.Templates.Tree`
│       └─ AppleSpots (Folder с 3 Attachment'ами: позиции яблок)
├─ Templates (Folder)   Tree (Model), Apple (Part Ball 1.2, красный, с PointLight нет), Plank (Part), BearTrap (Model), GlueTrap (Part), MotionLight (Model), Candle
├─ Shop (Model) атрибуты: Room="Garage"
│    ├─ Counter (Part), Sign (Part + SurfaceGui "RAY'S GARAGE")
│    ├─ Ray (Model: простой NPC из деталей, без Humanoid)
│    └─ Prompt (ProximityPrompt в Counter: ActionText "Shop", ObjectText "Ray", MaxActivationDistance 10)
├─ TV (Model) ├─ Screen (Part с SurfaceGui "Screen": Frame "Static" + TextLabel "Text"), атрибут On=false
├─ Radio (Model) ├─ Body (Part) — декор + точка звука
├─ Phone (Model) ├─ Body (Part) ├─ Prompt (ActionText "Answer")
├─ Fusebox (Model) атрибуты: On=true ├─ Box (Part) ├─ Prompt (ActionText "Power", HoldDuration 0.6)
├─ Nav (Folder)
│    ├─ Waypoints (Folder): Part'ы невидимые, атрибуты Room (string), Floor (number)   — центры комнат и точки в коридорах (≥ 25 штук)
│    ├─ Entries (Folder): Part'ы невидимые снаружи дома, атрибуты EntryId, Kind ("Door"|"Window"), TargetId (DoorId/WindowId), Room (куда ведёт)
│    ├─ InmateSpawns (Folder): Part'ы невидимые на улице/у калитки (≥ 3)
│    └─ VesperSpots (Folder): Part'ы в комнатах, где может сесть Веспер (атрибут Room)
├─ Spawns (Folder): Part'ы невидимые в гостиной/холле (≥ 8) — точки появления игроков в доме
└─ MotionLights (Folder): Part'ы-позиции прожекторов во дворе (атрибут Index), с выключенным SpotLight и Beeper (Sound без SoundId)

Workspace.Lobby (Folder) — вся зона смещена на Config.Map.LobbyOrigin = (0, 0, 400)
├─ Structure, Furniture (декор: блокпост, лента, фонари, доска)
├─ Spawns (Folder): SpawnLocation'ы (≥ 8, Neutral=true, Duration 0)
├─ ReadyPad (Part, площадка; атрибут нет) + Prompt (ProximityPrompt "Ready")  — дублирует кнопку в UI
├─ PerkKiosk (Model) ├─ Prompt (ActionText "Perks")
├─ Board (Model) ├─ Screen (Part + SurfaceGui с текстом HowToPlay EN)
└─ Leaderboard (Model) ├─ Screen (Part + SurfaceGui: TextLabel "Rows")
```

Двор, улица: лужайка `Material Grass`, дорога `Asphalt`, тротуар `Concrete`. Фонари улицы: 4 столба, у трёх PointLight (Range 30, тёплый), четвёртый (у тупика, x≈95) без света. Фургон у тупика: модель из деталей (серый, без надписей). Небо ночное. Луна видна.

Свет в доме: по одной модели на комнату в `Lights` для: Foyer, Living, Kitchen, Dining, Laundry, BackHall, Garage, KidRoom, ParentsRoom, UpperHall, Office, Bathroom, Basement, Porch (крыльцо, снаружи), Shed. Внутри дома лампы — потолочные плафоны; в подвале — голая лампочка; крыльцо — фонарь у двери.

Размеры: см. docs/GDD.md §3 (комнаты, этажи, двор). Высота этажа 11, толщина стен 1, дверные проёмы 4×7.5, окна 5×4 на высоте 3.5.
