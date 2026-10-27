-- Мини-Roblox: эмуляция части API Roblox для песочницы в игре.
-- Код игрока запускается внутри корутин, поэтому wait() работает как в Roblox.

local __out, __clock = __out, __clock
__startTime = __clock()
__dirty = true
local co_create, co_resume, co_status, co_yield, co_running =
  coroutine.create, coroutine.resume, coroutine.status, coroutine.yield, coroutine.running
local sethook = debug.sethook
local unpack = table.unpack

-------------------------------------------------------------- вывод
local raw_tostring = tostring
local function fmtnum(v)
  if math.type(v) == "float" and v == math.floor(v) and math.abs(v) < 1e15 then
    return string.format("%d", v)
  end
  return raw_tostring(v)
end
function tostring(v)
  if type(v) == "number" then return fmtnum(v) end
  return raw_tostring(v)
end
local function joinargs(...)
  local n = select("#", ...)
  local t = {}
  for i = 1, n do t[i] = tostring((select(i, ...))) end
  return table.concat(t, " ")
end
-- сколько строк напечатано без паузы: print в цикле без wait() вешает страницу
local printed = 0
local PRINT_LIMIT = 2000
local function countPrint()
  printed = printed + 1
  if printed > PRINT_LIMIT then error("__PRINT_FLOOD__", 0) end
end
function print(...) countPrint() __out("print", joinargs(...)) end
function warn(...) countPrint() __out("warn", joinargs(...)) end

-------------------------------------------------------------- Luau-дополнения
function math.clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
function math.sign(x) if x > 0 then return 1 elseif x < 0 then return -1 end return 0 end
function math.round(x) return math.floor(x + 0.5) end
function table.find(t, v) for i = 1, #t do if t[i] == v then return i end end return nil end
function table.clear(t) for k in pairs(t) do t[k] = nil end end
function string.split(s, sep)
  sep = sep or ","
  local out, i = {}, 1
  if sep == "" then for c in s:gmatch(".") do out[#out + 1] = c end return out end
  while true do
    local a, b = string.find(s, sep, i, true)
    if not a then out[#out + 1] = s:sub(i) break end
    out[#out + 1] = s:sub(i, a - 1)
    i = b + 1
  end
  return out
end
function tick() return __clock() end
function time() return __clock() - __startTime end
os.clock = function() return __clock() end

-------------------------------------------------------------- планировщик
local tasks = {}
local budget = 0
local LIMIT = 400 -- x 10000 инструкций без wait()
local TIME_LIMIT = 0.4 -- или 0.4 секунды настоящего времени (на медленном телефоне это наступит раньше)
local rnow = __rnow or function() return 0 end
local resumedAt = 0

local function hook()
  budget = budget + 1
  if budget > LIMIT or rnow() - resumedAt > TIME_LIMIT then
    budget = 0
    error("__TOO_LONG__", 0)
  end
end

local function spawn(fn, ...)
  local co = co_create(fn)
  sethook(co, hook, "", 10000)
  tasks[#tasks + 1] = { co = co, wake = 0, args = table.pack(...), started = false, since = 0 }
  return co
end
__spawn = spawn

function wait(n)
  n = tonumber(n) or 0
  if n < 0.03 then n = 0.03 end
  if not co_running() then return n end
  local got = co_yield(n)
  return got or n, __clock()
end

task = {
  wait = wait,
  spawn = function(fn, ...)
    if type(fn) ~= "function" then error("task.spawn ждёт функцию", 2) end
    spawn(fn, ...)
  end,
  delay = function(t, fn, ...)
    local args = table.pack(...)
    spawn(function() wait(t) fn(unpack(args, 1, args.n)) end)
  end,
  defer = function(fn, ...) spawn(fn, ...) end,
}
delay = task.delay

local physics -- объявим ниже

function __tick(now)
  local i = 1
  while i <= #tasks do
    local t = tasks[i]
    if t.wake <= now then
      budget = 0
      printed = 0
      resumedAt = rnow()
      local ok, res
      if not t.started then
        t.started = true
        ok, res = co_resume(t.co, unpack(t.args, 1, t.args.n))
      else
        ok, res = co_resume(t.co, now - t.since)
      end
      if not ok then
        __out("error", raw_tostring(res))
        table.remove(tasks, i)
      elseif co_status(t.co) == "dead" then
        table.remove(tasks, i)
      else
        t.since = now
        t.wake = now + (tonumber(res) or 0.03)
        i = i + 1
      end
    else
      i = i + 1
    end
  end
  physics(now)
  local dirty = __dirty
  __dirty = false
  return #tasks, dirty
end

-------------------------------------------------------------- Signal
local Signal = {}
Signal.__index = Signal
local function newSignal(name)
  return setmetatable({ _h = {}, _name = name }, Signal)
end
function Signal:Connect(fn)
  if type(fn) ~= "function" then error("Connect ждёт функцию: :Connect(function(...) ... end)", 2) end
  local h = { fn = fn, on = true }
  table.insert(self._h, h)
  local c = { Connected = true }
  function c:Disconnect() h.on = false; self.Connected = false end
  c.disconnect = c.Disconnect
  return c
end
Signal.connect = Signal.Connect
function Signal:Once(fn)
  local c
  c = self:Connect(function(...) c:Disconnect() fn(...) end)
  return c
end
function Signal:Fire(...)
  for _, h in ipairs(self._h) do
    if h.on then spawn(h.fn, ...) end
  end
end
function Signal:Wait()
  local done, res = false, nil
  local c
  c = self:Connect(function(...) done = true; res = table.pack(...); c:Disconnect() end)
  while not done do wait() end
  return unpack(res, 1, res.n)
end
Signal.wait = Signal.Wait

-------------------------------------------------------------- Vector3
local V3 = {}
local function isV3(v) return getmetatable(v) == V3 end
Vector3 = {}
function Vector3.new(x, y, z)
  return setmetatable({ __x = tonumber(x) or 0, __y = tonumber(y) or 0, __z = tonumber(z) or 0 }, V3)
end
V3.__index = function(v, k)
  if k == "X" or k == "x" then return v.__x end
  if k == "Y" or k == "y" then return v.__y end
  if k == "Z" or k == "z" then return v.__z end
  if k == "Magnitude" or k == "magnitude" then return math.sqrt(v.__x ^ 2 + v.__y ^ 2 + v.__z ^ 2) end
  if k == "Unit" or k == "unit" then
    local m = math.sqrt(v.__x ^ 2 + v.__y ^ 2 + v.__z ^ 2)
    if m == 0 then return Vector3.new(0, 0, 0) end
    return Vector3.new(v.__x / m, v.__y / m, v.__z / m)
  end
  if k == "Lerp" then
    return function(a, b, t) return Vector3.new(a.__x + (b.__x - a.__x) * t, a.__y + (b.__y - a.__y) * t, a.__z + (b.__z - a.__z) * t) end
  end
  if k == "Dot" then return function(a, b) return a.__x * b.__x + a.__y * b.__y + a.__z * b.__z end end
  error("У Vector3 нет поля «" .. tostring(k) .. "» (есть X, Y, Z, Magnitude, Unit)", 2)
end
V3.__newindex = function(_, k)
  error("Нельзя менять " .. tostring(k) .. " у Vector3 по отдельности. Пиши: part.Position = Vector3.new(x, y, z)", 2)
end
V3.__add = function(a, b) return Vector3.new(a.__x + b.__x, a.__y + b.__y, a.__z + b.__z) end
V3.__sub = function(a, b) return Vector3.new(a.__x - b.__x, a.__y - b.__y, a.__z - b.__z) end
V3.__mul = function(a, b)
  if type(a) == "number" then return Vector3.new(a * b.__x, a * b.__y, a * b.__z) end
  if type(b) == "number" then return Vector3.new(a.__x * b, a.__y * b, a.__z * b) end
  return Vector3.new(a.__x * b.__x, a.__y * b.__y, a.__z * b.__z)
end
V3.__div = function(a, b)
  if type(b) == "number" then return Vector3.new(a.__x / b, a.__y / b, a.__z / b) end
  return Vector3.new(a.__x / b.__x, a.__y / b.__y, a.__z / b.__z)
end
V3.__unm = function(a) return Vector3.new(-a.__x, -a.__y, -a.__z) end
V3.__eq = function(a, b) return a.__x == b.__x and a.__y == b.__y and a.__z == b.__z end
V3.__tostring = function(v) return tostring(v.__x) .. ", " .. tostring(v.__y) .. ", " .. tostring(v.__z) end
Vector3.zero = Vector3.new(0, 0, 0)
Vector3.one = Vector3.new(1, 1, 1)
Vector3.xAxis = Vector3.new(1, 0, 0)
Vector3.yAxis = Vector3.new(0, 1, 0)
Vector3.zAxis = Vector3.new(0, 0, 1)

-------------------------------------------------------------- CFrame (только позиция)
local CF = {}
local function isCF(v) return getmetatable(v) == CF end
CFrame = {}
function CFrame.new(x, y, z)
  if isV3(x) then return setmetatable({ __p = x }, CF) end
  return setmetatable({ __p = Vector3.new(x, y, z) }, CF)
end
function CFrame.Angles() return setmetatable({ __p = Vector3.new(0, 0, 0), __rot = true }, CF) end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
CF.__index = function(c, k)
  if k == "Position" or k == "p" then return c.__p end
  if k == "X" or k == "Y" or k == "Z" then return c.__p[k] end
  error("У CFrame нет поля «" .. tostring(k) .. "»", 2)
end
CF.__mul = function(a, b)
  if isCF(b) then return CFrame.new(a.__p + b.__p) end
  if isV3(b) then return a.__p + b end
  error("CFrame можно умножать только на CFrame или Vector3", 2)
end
CF.__add = function(a, b) return CFrame.new(a.__p + b) end
CF.__sub = function(a, b) return CFrame.new(a.__p - b) end
CF.__tostring = function(c) return tostring(c.__p) .. ", 1, 0, 0, 0, 1, 0, 0, 0, 1" end

-------------------------------------------------------------- Color3
local C3 = {}
local function isC3(v) return getmetatable(v) == C3 end
Color3 = {}
local function clamp01(v) v = tonumber(v) or 0 if v < 0 then return 0 elseif v > 1 then return 1 end return v end
function Color3.new(r, g, b) return setmetatable({ __r = clamp01(r), __g = clamp01(g), __b = clamp01(b) }, C3) end
function Color3.fromRGB(r, g, b) return Color3.new((tonumber(r) or 0) / 255, (tonumber(g) or 0) / 255, (tonumber(b) or 0) / 255) end
function Color3.fromHSV(h, s, v)
  h, s, v = clamp01(h), clamp01(s), clamp01(v)
  local i = math.floor(h * 6) % 6
  local f = h * 6 - math.floor(h * 6)
  local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
  local r, g, b
  if i == 0 then r, g, b = v, t, p elseif i == 1 then r, g, b = q, v, p elseif i == 2 then r, g, b = p, v, t
  elseif i == 3 then r, g, b = p, q, v elseif i == 4 then r, g, b = t, p, v else r, g, b = v, p, q end
  return Color3.new(r, g, b)
end
function Color3.fromHex(hex)
  hex = tostring(hex):gsub("#", "")
  return Color3.fromRGB(tonumber(hex:sub(1, 2), 16) or 0, tonumber(hex:sub(3, 4), 16) or 0, tonumber(hex:sub(5, 6), 16) or 0)
end
C3.__index = function(c, k)
  if k == "R" or k == "r" then return c.__r end
  if k == "G" or k == "g" then return c.__g end
  if k == "B" or k == "b" then return c.__b end
  if k == "Lerp" then
    return function(a, b, t) return Color3.new(a.__r + (b.__r - a.__r) * t, a.__g + (b.__g - a.__g) * t, a.__b + (b.__b - a.__b) * t) end
  end
  error("У Color3 нет поля «" .. tostring(k) .. "» (есть R, G, B)", 2)
end
C3.__newindex = function() error("Цвет нельзя менять по частям. Пиши: part.Color = Color3.fromRGB(255, 0, 0)", 2) end
C3.__eq = function(a, b) return a.__r == b.__r and a.__g == b.__g and a.__b == b.__b end
C3.__tostring = function(c) return tostring(c.__r) .. ", " .. tostring(c.__g) .. ", " .. tostring(c.__b) end

-------------------------------------------------------------- BrickColor
local BRICK = {
  ["White"] = { 242, 243, 243 }, ["Institutional white"] = { 248, 248, 248 }, ["Black"] = { 27, 42, 53 },
  ["Really black"] = { 17, 17, 17 }, ["Medium stone grey"] = { 163, 162, 165 }, ["Dark stone grey"] = { 99, 95, 98 },
  ["Bright red"] = { 196, 40, 28 }, ["Really red"] = { 255, 0, 0 }, ["Bright blue"] = { 13, 105, 172 },
  ["Really blue"] = { 0, 0, 255 }, ["Bright green"] = { 75, 151, 75 }, ["Lime green"] = { 0, 255, 0 },
  ["Bright yellow"] = { 245, 205, 48 }, ["New Yeller"] = { 255, 255, 0 }, ["Bright orange"] = { 218, 133, 65 },
  ["Deep orange"] = { 255, 176, 0 }, ["Hot pink"] = { 255, 102, 204 }, ["Pink"] = { 255, 102, 204 },
  ["Royal purple"] = { 98, 37, 209 }, ["Bright violet"] = { 107, 50, 124 }, ["Magenta"] = { 170, 0, 170 },
  ["Cyan"] = { 4, 175, 236 }, ["Toothpaste"] = { 0, 255, 255 }, ["Pastel blue"] = { 128, 187, 219 },
  ["Brown"] = { 124, 92, 70 }, ["Reddish brown"] = { 105, 64, 40 }, ["Gold"] = { 239, 184, 56 },
  ["Sand green"] = { 120, 144, 130 }, ["Teal"] = { 18, 238, 212 }, ["Electric blue"] = { 9, 137, 207 },
}
local BRICK_NAMES = {}
for k in pairs(BRICK) do BRICK_NAMES[#BRICK_NAMES + 1] = k end
table.sort(BRICK_NAMES)
local BC = {}
local function isBC(v) return getmetatable(v) == BC end
BrickColor = {}
local function makeBC(name)
  local c = BRICK[name]
  return setmetatable({ Name = name, Color = Color3.fromRGB(c[1], c[2], c[3]) }, BC)
end
function BrickColor.new(name, g, b)
  if type(name) == "number" and g then
    return BrickColor.nearest(Color3.new(name, g, b))
  end
  if isC3(name) then return BrickColor.nearest(name) end
  name = tostring(name)
  if not BRICK[name] then
    warn("Цвет «" .. name .. "» мне неизвестен, беру серый. Примеры: \"Bright red\", \"Lime green\", \"Really blue\"")
    name = "Medium stone grey"
  end
  return makeBC(name)
end
function BrickColor.nearest(c3)
  local best, bd = "Medium stone grey", 1e9
  for name, c in pairs(BRICK) do
    local d = (c[1] / 255 - c3.R) ^ 2 + (c[2] / 255 - c3.G) ^ 2 + (c[3] / 255 - c3.B) ^ 2
    if d < bd then best, bd = name, d end
  end
  return makeBC(best)
end
function BrickColor.Random() return makeBC(BRICK_NAMES[math.random(1, #BRICK_NAMES)]) end
function BrickColor.Red() return makeBC("Bright red") end
function BrickColor.Blue() return makeBC("Bright blue") end
function BrickColor.Green() return makeBC("Bright green") end
function BrickColor.Yellow() return makeBC("Bright yellow") end
function BrickColor.White() return makeBC("White") end
function BrickColor.Black() return makeBC("Black") end
function BrickColor.Gray() return makeBC("Medium stone grey") end
BC.__tostring = function(b) return b.Name end
BC.__eq = function(a, b) return a.Name == b.Name end

-------------------------------------------------------------- Enum
local function enumGroup(groupName, items)
  local g = {}
  for i, n in ipairs(items) do
    g[n] = setmetatable({ Name = n, Value = i - 1, EnumType = groupName }, {
      __tostring = function() return "Enum." .. groupName .. "." .. n end,
    })
  end
  return setmetatable(g, {
    __index = function(_, k) error("В Enum." .. groupName .. " нет «" .. tostring(k) .. "»", 2) end,
  })
end
Enum = {
  Material = enumGroup("Material", { "Plastic", "SmoothPlastic", "Neon", "Wood", "WoodPlanks", "Grass", "Brick", "Glass", "Metal", "DiamondPlate", "ForceField", "Ice", "Sand", "Slate", "Concrete", "Marble", "Granite", "Fabric", "Foil" }),
  PartType = enumGroup("PartType", { "Block", "Ball", "Cylinder", "Wedge" }),
  EasingStyle = enumGroup("EasingStyle", { "Linear", "Sine", "Quad", "Back", "Bounce", "Elastic", "Cubic", "Quart", "Exponential" }),
  EasingDirection = enumGroup("EasingDirection", { "In", "Out", "InOut" }),
  HumanoidStateType = enumGroup("HumanoidStateType", { "Dead", "Running", "Jumping" }),
}

-------------------------------------------------------------- Instance
local nextId = 0
local byId = {}
local Inst = {}      -- методы
local IMT = {}       -- метатаблица
local function D(o) return rawget(o, "__d") end
local function isInst(v) return type(v) == "table" and getmetatable(v) == IMT end

local BASEPART = { Part = true, SpawnLocation = true, WedgePart = true, MeshPart = true, TrussPart = true }
local VALUES = { IntValue = 0, NumberValue = 0, StringValue = "", BoolValue = false, ObjectValue = false, Color3Value = false, Vector3Value = false }
local isA = {
  BasePart = function(c) return BASEPART[c] end,
  ValueBase = function(c) return VALUES[c] ~= nil end,
  Instance = function() return true end,
  PVInstance = function(c) return BASEPART[c] or c == "Model" end,
}

local function defaultsFor(class)
  local p = { Name = class, ClassName = class, Archivable = true }
  if BASEPART[class] then
    p.Size = Vector3.new(4, 1, 2)
    p.Position = Vector3.new(0, 0.5, 0)
    p.Color = Color3.fromRGB(163, 162, 165)
    p.Transparency = 0
    p.Reflectance = 0
    p.Anchored = false
    p.CanCollide = true
    p.CanTouch = true
    p.Locked = false
    p.Material = Enum.Material.Plastic
    p.Shape = Enum.PartType.Block
    p.Velocity = Vector3.new(0, 0, 0)
    if class == "SpawnLocation" then p.Size = Vector3.new(12, 1, 12); p.Anchored = true; p.Color = Color3.fromRGB(99, 95, 98) end
    if class == "WedgePart" then p.Shape = Enum.PartType.Wedge end
  elseif VALUES[class] ~= nil then
    if class == "ObjectValue" then p.Value = nil
    elseif class == "Color3Value" then p.Value = Color3.new(0, 0, 0)
    elseif class == "Vector3Value" then p.Value = Vector3.new(0, 0, 0)
    else p.Value = VALUES[class] end
  elseif class == "Humanoid" then
    p.Health = 100; p.MaxHealth = 100; p.WalkSpeed = 16; p.JumpPower = 50; p.JumpHeight = 7.2; p.DisplayName = ""
  elseif class == "ClickDetector" then
    p.MaxActivationDistance = 32
  elseif class == "PointLight" or class == "SpotLight" then
    p.Brightness = 1; p.Range = 8; p.Color = Color3.new(1, 1, 1); p.Enabled = true
  elseif class == "Sound" then
    p.SoundId = ""; p.Volume = 0.5; p.Playing = false; p.Looped = false
  elseif class == "Script" or class == "LocalScript" or class == "ModuleScript" then
    p.Disabled = false; p.Enabled = true
  elseif class == "Lighting" then
    p.ClockTime = 14; p.Brightness = 2; p.Ambient = Color3.fromRGB(70, 70, 70); p.FogEnd = 100000
  elseif class == "Workspace" then
    p.Gravity = 196.2
  end
  return p
end

local function newInstance(class)
  nextId = nextId + 1
  local d = {
    id = nextId, props = defaultsFor(class), children = {}, parent = nil, events = {},
    destroyed = false, vy = 0,
  }
  d.events.Changed = newSignal("Changed")
  d.events.ChildAdded = newSignal("ChildAdded")
  d.events.ChildRemoved = newSignal("ChildRemoved")
  d.events.AncestryChanged = newSignal("AncestryChanged")
  d.events.Destroying = newSignal("Destroying")
  d.propSignals = {}
  if BASEPART[class] then
    d.events.Touched = newSignal("Touched")
    d.events.TouchEnded = newSignal("TouchEnded")
  elseif class == "ClickDetector" then
    d.events.MouseClick = newSignal("MouseClick")
    d.events.MouseHoverEnter = newSignal("MouseHoverEnter")
    d.events.MouseHoverLeave = newSignal("MouseHoverLeave")
  elseif class == "Humanoid" then
    d.events.Died = newSignal("Died")
    d.events.HealthChanged = newSignal("HealthChanged")
  elseif class == "Players" then
    d.events.PlayerAdded = newSignal("PlayerAdded")
    d.events.PlayerRemoving = newSignal("PlayerRemoving")
  elseif class == "Player" then
    d.events.CharacterAdded = newSignal("CharacterAdded")
    d.events.Chatted = newSignal("Chatted")
  elseif class == "RunService" then
    d.events.Heartbeat = newSignal("Heartbeat")
    d.events.Stepped = newSignal("Stepped")
    d.events.RenderStepped = d.events.Heartbeat
  elseif class == "BindableEvent" then
    d.events.Event = newSignal("Event")
  elseif class == "RemoteEvent" then
    d.events.OnServerEvent = newSignal("OnServerEvent")
    d.events.OnClientEvent = newSignal("OnClientEvent")
  end
  local o = setmetatable({ __d = d }, IMT)
  byId[nextId] = o
  return o
end

local function fullName(o)
  local d = D(o)
  if not d.parent or d.props.ClassName == "DataModel" then return d.props.Name end
  if D(d.parent).props.ClassName == "DataModel" then return d.props.Name end
  return fullName(d.parent) .. "." .. d.props.Name
end

local function isDescendantOf(o, anc)
  local p = D(o).parent
  while p do
    if p == anc then return true end
    p = D(p).parent
  end
  return false
end

local function method(o, name, fn)
  local d = D(o)
  d.methods = d.methods or {}
  d.methods[name] = fn
end

-- учёт деталей в мире: их число ограничено, иначе страница зависнет
local treeVer = 0      -- растёт, когда меняется дерево объектов
local wsCount = 0      -- сколько деталей сейчас в workspace
local MAX_PARTS = 600
local warnedMax = false
local function countParts(o)
  local d = D(o)
  local n = (BASEPART[d.props.ClassName] and not d.avatar) and 1 or 0
  for _, c in ipairs(d.children) do n = n + countParts(c) end
  return n
end
-- деталь (и всё внутри) сдвинули или убрали: будим тех, кто на ней лежит
local function bumpGeo(o)
  local d = D(o)
  d.geo = (d.geo or 0) + 1
  d.ver = (d.ver or 0) + 1
  d.sleeping = nil
  for _, c in ipairs(d.children) do bumpGeo(c) end
end
local wsRoot = nil      -- сам workspace (запомним, когда создадим)
local function inWorkspace(p)
  return p ~= nil and wsRoot ~= nil and (p == wsRoot or isDescendantOf(p, wsRoot))
end

local function setParent(o, p)
  local d = D(o)
  if d.destroyed then error("Объект «" .. d.props.Name .. "» уже уничтожен (Destroy), его нельзя вернуть", 3) end
  if p ~= nil and not isInst(p) then error("Parent должен быть объектом (например, workspace), а не " .. type(p), 3) end
  if p == o or (p and isDescendantOf(p, o)) then error("Нельзя положить объект сам в себя", 3) end
  local old = d.parent
  if old == p then return end
  local wasIn, willIn = inWorkspace(old), inWorkspace(p)
  if wasIn ~= willIn then
    local n = countParts(o)
    if willIn and n > 0 and wsCount + n > MAX_PARTS then
      if not warnedMax then
        warnedMax = true
        warn("В мире уже " .. wsCount .. " деталей — это предел. Новые детали я не ставлю, иначе игра начнёт тормозить. Сделай цикл поменьше.")
      end
      return
    end
    wsCount = wsCount + (willIn and n or -n)
  end
  treeVer = treeVer + 1
  bumpGeo(o)
  if old then D(old).ver = (D(old).ver or 0) + 1 end
  if p then D(p).ver = (D(p).ver or 0) + 1 end
  if old then
    local oc = D(old).children
    for i = #oc, 1, -1 do if oc[i] == o then table.remove(oc, i) end end
    D(old).events.ChildRemoved:Fire(o)
  end
  d.parent = p
  if p then
    table.insert(D(p).children, o)
    D(p).events.ChildAdded:Fire(o)
  end
  d.events.AncestryChanged:Fire(o, p)
  __dirty = true
end

local function findChild(o, name)
  for _, c in ipairs(D(o).children) do
    if D(c).props.Name == name then return c end
  end
  return nil
end

local typeCheck = {
  Position = isV3, Size = isV3, Velocity = isV3,
  Color = isC3, Ambient = isC3,
}
local numberProps = {
  Transparency = true, Reflectance = true, Health = true, MaxHealth = true, WalkSpeed = true, JumpPower = true,
  JumpHeight = true, ClockTime = true, Brightness = true, Range = true, Volume = true, Gravity = true,
  MaxActivationDistance = true, FogEnd = true,
}
local boolProps = { Anchored = true, CanCollide = true, CanTouch = true, Locked = true, Enabled = true, Disabled = true, Playing = true, Looped = true, Archivable = true }
-- свойства, после которых деталь может начать падать (или опора — исчезнуть)
local GEO = { Position = true, Size = true, CFrame = true, Anchored = true, CanCollide = true }

IMT.__index = function(o, k)
  local d = D(o)
  if k == "Parent" then return d.parent end
  if k == "CFrame" and d.props.Position then return CFrame.new(d.props.Position) end
  if k == "BrickColor" and d.props.Color then return BrickColor.nearest(d.props.Color) end
  if k == "Orientation" or k == "Rotation" then return Vector3.new(0, 0, 0) end
  local v = d.props[k]
  if v ~= nil then return v end
  local m = d.methods and d.methods[k]
  if m then return m end
  if Inst[k] then return Inst[k] end
  local ev = d.events[k]
  if ev then return ev end
  if k == "Value" and VALUES[d.props.ClassName] ~= nil then return nil end
  if k == "Character" and d.props.ClassName == "Player" then return nil end
  local c = findChild(o, k)
  if c then return c end
  error("«" .. tostring(k) .. "» не найден в " .. fullName(o) .. " (is not a valid member). Проверь имя и большие/маленькие буквы", 2)
end

IMT.__newindex = function(o, k, v)
  local d = D(o)
  local class = d.props.ClassName
  if k == "Parent" then setParent(o, v) return end
  if k == "ClassName" then error("ClassName менять нельзя", 2) end
  if k == "Name" then
    d.props.Name = tostring(v)
  elseif k == "CFrame" and d.props.Position then
    if isCF(v) then d.props.Position = v.Position
    else error("CFrame должен быть CFrame.new(x, y, z)", 2) end
    d.vy = 0
  elseif k == "BrickColor" and d.props.Color then
    if isBC(v) then d.props.Color = v.Color
    elseif type(v) == "string" then d.props.Color = BrickColor.new(v).Color
    else error("BrickColor должен быть BrickColor.new(\"Bright red\")", 2) end
  elseif k == "Material" and d.props.Material then
    if type(v) == "string" then v = Enum.Material[v] end
    if type(v) ~= "table" or not v.EnumType then error("Material: пиши Enum.Material.Neon", 2) end
    d.props.Material = v
  elseif k == "Shape" and d.props.Shape then
    if type(v) == "string" then v = Enum.PartType[v] end
    d.props.Shape = v
  elseif k == "Orientation" or k == "Rotation" then
    -- вращение в песочнице не рисуем, но ошибки не даём
  elseif k == "Value" and VALUES[class] ~= nil then
    if class == "IntValue" then
      local n = tonumber(v)
      if n == nil then error("IntValue.Value должен быть числом", 2) end
      v = math.floor(n)
    elseif class == "NumberValue" then
      v = tonumber(v)
      if v == nil then error("NumberValue.Value должен быть числом", 2) end
    elseif class == "StringValue" then v = tostring(v)
    elseif class == "BoolValue" then v = not not v end
    local changed = d.props.Value ~= v
    d.props.Value = v
    if changed then d.events.Changed:Fire(v) end
    __dirty = true
    return
  elseif typeCheck[k] and d.props[k] ~= nil then
    if not typeCheck[k](v) then
      local hint = (k == "Color" or k == "Ambient") and "Color3.fromRGB(255, 0, 0)" or "Vector3.new(0, 5, 0)"
      error(k .. " нужно задавать так: " .. hint, 2)
    end
    if k == "Size" then
      v = Vector3.new(math.max(0.05, v.X), math.max(0.05, v.Y), math.max(0.05, v.Z))
    end
    if k == "Position" then d.vy = 0 end
    d.props[k] = v
  elseif numberProps[k] and d.props[k] ~= nil then
    local n = tonumber(v)
    if n == nil then error(k .. " должен быть числом", 2) end
    if k == "Transparency" or k == "Reflectance" then n = math.clamp(n, 0, 1) end
    if class == "Humanoid" and k == "Health" then
      local old = d.props.Health
      n = math.clamp(n, 0, d.props.MaxHealth)
      d.props.Health = n
      if n ~= old then d.events.HealthChanged:Fire(n) end
      if old > 0 and n <= 0 then d.events.Died:Fire() end
      __dirty = true
      return
    end
    d.props[k] = n
  elseif boolProps[k] and d.props[k] ~= nil then
    d.props[k] = not not v
    if k == "Anchored" then d.vy = 0 end
  elseif d.props[k] ~= nil then
    d.props[k] = v
  else
    error("У " .. class .. " нет свойства «" .. tostring(k) .. "». Проверь написание", 2)
  end
  d.ver = (d.ver or 0) + 1
  if GEO[k] then
    d.geo = (d.geo or 0) + 1
    d.sleeping = nil
  end
  local ps = d.propSignals[k]
  if ps then ps:Fire() end
  d.events.Changed:Fire(k)
  __dirty = true
end
IMT.__tostring = function(o) return D(o).props.Name end
IMT.__eq = function(a, b) return rawequal(a, b) end

function Inst.Destroy(o)
  local d = D(o)
  if d.destroyed then return end
  d.events.Destroying:Fire()
  for i = #d.children, 1, -1 do Inst.Destroy(d.children[i]) end
  if d.parent then setParent(o, nil) end
  d.destroyed = true
  __dirty = true
end
Inst.destroy = Inst.Destroy
Inst.Remove = Inst.Destroy
function Inst.ClearAllChildren(o)
  local d = D(o)
  for i = #d.children, 1, -1 do Inst.Destroy(d.children[i]) end
end
function Inst.Clone(o)
  local d = D(o)
  local c = newInstance(d.props.ClassName)
  local cd = D(c)
  for k, v in pairs(d.props) do cd.props[k] = v end
  for _, ch in ipairs(d.children) do
    local cc = Inst.Clone(ch)
    setParent(cc, c)
  end
  return c
end
function Inst.GetChildren(o)
  local t = {}
  for i, c in ipairs(D(o).children) do t[i] = c end
  return t
end
Inst.getChildren = Inst.GetChildren
Inst.children = Inst.GetChildren
function Inst.GetDescendants(o)
  local t = {}
  local function walk(x)
    for _, c in ipairs(D(x).children) do t[#t + 1] = c; walk(c) end
  end
  walk(o)
  return t
end
function Inst.FindFirstChild(o, name, recursive)
  local c = findChild(o, name)
  if c or not recursive then return c end
  for _, ch in ipairs(D(o).children) do
    local r = Inst.FindFirstChild(ch, name, true)
    if r then return r end
  end
  return nil
end
Inst.findFirstChild = Inst.FindFirstChild
function Inst.FindFirstChildOfClass(o, class)
  for _, c in ipairs(D(o).children) do if D(c).props.ClassName == class then return c end end
  return nil
end
function Inst.IsA(o, class)
  local c = D(o).props.ClassName
  if c == class then return true end
  local f = isA[class]
  return f and f(c) and true or false
end
function Inst.FindFirstChildWhichIsA(o, class)
  for _, c in ipairs(D(o).children) do if Inst.IsA(c, class) then return c end end
  return nil
end
function Inst.FindFirstAncestor(o, name)
  local p = D(o).parent
  while p do if D(p).props.Name == name then return p end p = D(p).parent end
  return nil
end
function Inst.FindFirstAncestorOfClass(o, class)
  local p = D(o).parent
  while p do if D(p).props.ClassName == class then return p end p = D(p).parent end
  return nil
end
function Inst.WaitForChild(o, name, timeout)
  local t0 = __clock()
  local warned = false
  while true do
    local c = findChild(o, name)
    if c then return c end
    if timeout and __clock() - t0 > timeout then return nil end
    if not warned and __clock() - t0 > 5 then
      warned = true
      warn("WaitForChild всё ещё ждёт «" .. tostring(name) .. "» в " .. fullName(o) .. "…")
    end
    wait(0.05)
  end
end
function Inst.GetFullName(o) return fullName(o) end
function Inst.IsDescendantOf(o, anc) return isDescendantOf(o, anc) end
function Inst.IsAncestorOf(o, desc) return isDescendantOf(desc, o) end
function Inst.GetPropertyChangedSignal(o, prop)
  local d = D(o)
  if not d.propSignals[prop] then d.propSignals[prop] = newSignal(prop .. "Changed") end
  return d.propSignals[prop]
end
function Inst.GetAttribute(o, name) local a = D(o).attrs return a and a[name] end
function Inst.SetAttribute(o, name, v) local d = D(o) d.attrs = d.attrs or {} d.attrs[name] = v end
function Inst.GetAttributes(o) return D(o).attrs or {} end
function Inst.Fire(o, ...)
  local d = D(o)
  if d.events.Event then d.events.Event:Fire(...) else error("Fire есть только у BindableEvent", 2) end
end
function Inst.FireServer(o, ...)
  local d = D(o)
  if not d.events.OnServerEvent then error("FireServer есть только у RemoteEvent", 2) end
  d.events.OnServerEvent:Fire(__player, ...)
end
function Inst.FireClient(o, _, ...) local d = D(o) d.events.OnClientEvent:Fire(...) end
function Inst.FireAllClients(o, ...) local d = D(o) d.events.OnClientEvent:Fire(...) end
function Inst.Play(o) local d = D(o) if d.props.ClassName == "Sound" then d.props.Playing = true __out("sound", d.props.Name) end end
function Inst.Stop(o) local d = D(o) if d.props.ClassName == "Sound" then d.props.Playing = false end end
function Inst.Kill() end

Instance = {}
function Instance.new(class, parent)
  if type(class) ~= "string" then error("Instance.new ждёт название класса в кавычках, например Instance.new(\"Part\")", 2) end
  local o = newInstance(class)
  if parent ~= nil then setParent(o, parent) end
  return o
end

-------------------------------------------------------------- мир
game = newInstance("DataModel")
D(game).props.Name = "Game"
local services = {}
local function service(class)
  local s = newInstance(class)
  D(s).props.Name = class
  setParent(s, game)
  services[class] = s
  return s
end
workspace = service("Workspace")
Workspace = workspace
wsRoot = workspace
local Players = service("Players")
local Lighting = service("Lighting")
service("ReplicatedStorage"); service("ServerStorage"); service("ServerScriptService")
service("StarterGui"); service("StarterPack"); service("SoundService"); service("Teams")
local RunService = service("RunService")
local TweenService = service("TweenService")
local Debris = service("Debris")
service("UserInputService"); service("Chat")

function Inst.GetService(o, name)
  local s = services[name]
  if not s then error("Сервис «" .. tostring(name) .. "» в песочнице не поддерживается", 2) end
  return s
end
Inst.getService = Inst.GetService
Inst.service = Inst.GetService

method(RunService, "IsServer", function() return true end)
method(RunService, "IsClient", function() return true end)
method(RunService, "IsStudio", function() return true end)

local base = Instance.new("Part")
base.Name = "Baseplate"
base.Size = Vector3.new(512, 16, 512)
base.Position = Vector3.new(0, -8, 0)
base.Anchored = true
base.Color = Color3.fromRGB(91, 93, 105)
base.Locked = true
base.Parent = workspace
local spawnPad = Instance.new("SpawnLocation")
spawnPad.Name = "SpawnLocation"
spawnPad.Position = Vector3.new(0, 0.5, 0)
spawnPad.Parent = workspace

-------------------------------------------------------------- игрок и персонаж
local player = newInstance("Player")
D(player).props.Name = __playerName or "Player"
D(player).props.DisplayName = __playerName or "Player"
D(player).props.UserId = 1
D(player).props.Team = false
__player = player

local char = newInstance("Model")
D(char).props.Name = D(player).props.Name
local hum = Instance.new("Humanoid")
hum.Parent = char
local function bodyPart(name, size, off)
  local p = Instance.new("Part")
  p.Name = name
  p.Size = size
  p.Anchored = true
  p.CanCollide = false
  D(p).avatar = off
  p.Parent = char
  return p
end
local root = bodyPart("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(0, 0, 0))
D(root).props.Transparency = 1
bodyPart("Head", Vector3.new(2, 1, 1), Vector3.new(0, 1.5, 0))
bodyPart("Torso", Vector3.new(2, 2, 1), Vector3.new(0, 0, 0))
local foot = bodyPart("LeftFoot", Vector3.new(1, 1, 1), Vector3.new(-0.5, -2.5, 0))
bodyPart("RightFoot", Vector3.new(1, 1, 1), Vector3.new(0.5, -2.5, 0))
D(char).props.PrimaryPart = root
D(player).props.Character = char

local avatar = { x = 0, z = 6, y = 3, tx = nil, tz = nil, target = nil, dead = false, deadAt = 0, joined = false }

local function placeAvatar()
  for _, c in ipairs(D(char).children) do
    local off = D(c).avatar
    if off then D(c).props.Position = Vector3.new(avatar.x + off.X, avatar.y + off.Y, avatar.z + off.Z) end
  end
end
placeAvatar()

method(Players, "GetPlayers", function() if avatar.joined then return { player } end return {} end)
method(Players, "GetPlayerFromCharacter", function(_, model)
  if model == char then return player end
  return nil
end)
method(Players, "FindFirstChild", function(o, name)
  if avatar.joined and name == D(player).props.Name then return player end
  return Inst.FindFirstChild(o, name)
end)
D(Players).props.LocalPlayer = player
D(Players).props.MaxPlayers = 1

local function join()
  avatar.joined = true
  setParent(player, Players)
  setParent(char, workspace)
  D(Players).events.PlayerAdded:Fire(player)
  D(player).events.CharacterAdded:Fire(char)
  __dirty = true
end

local function respawn()
  avatar.dead = false
  avatar.x, avatar.z, avatar.y = 0, 6, 3
  avatar.tx, avatar.tz, avatar.target = nil, nil, nil
  D(hum).props.Health = D(hum).props.MaxHealth
  placeAvatar()
  D(player).events.CharacterAdded:Fire(char)
  __dirty = true
end

-------------------------------------------------------------- твины
local function lerpVal(a, b, t)
  if type(a) == "number" then return a + (b - a) * t end
  if isV3(a) then return a:Lerp(b, t) end
  if isC3(a) then return a:Lerp(b, t) end
  if isCF(a) then return CFrame.new(a.Position:Lerp(b.Position, t)) end
  return t < 1 and a or b
end
local function ease(style, dir, t)
  local name = style and style.Name or "Quad"
  local f
  if name == "Linear" then f = function(x) return x end
  elseif name == "Sine" then f = function(x) return 1 - math.cos(x * math.pi / 2) end
  elseif name == "Back" then f = function(x) return x * x * (2.70158 * x - 1.70158) end
  elseif name == "Bounce" then
    f = function(x)
      x = 1 - x
      local r
      if x < 1 / 2.75 then r = 7.5625 * x * x
      elseif x < 2 / 2.75 then x = x - 1.5 / 2.75 r = 7.5625 * x * x + 0.75
      elseif x < 2.5 / 2.75 then x = x - 2.25 / 2.75 r = 7.5625 * x * x + 0.9375
      else x = x - 2.625 / 2.75 r = 7.5625 * x * x + 0.984375 end
      return 1 - r
    end
  elseif name == "Elastic" then f = function(x) if x == 0 or x == 1 then return x end return -(2 ^ (10 * x - 10)) * math.sin((x * 10 - 10.75) * (2 * math.pi) / 3) end
  else f = function(x) return x * x end end
  local d = dir and dir.Name or "Out"
  if d == "In" then return f(t) end
  if d == "Out" then return 1 - f(1 - t) end
  if t < 0.5 then return f(t * 2) / 2 end
  return 1 - f((1 - t) * 2) / 2
end
TweenInfo = {}
function TweenInfo.new(time, style, dir, repeatCount, reverses, delayTime)
  return { Time = tonumber(time) or 1, EasingStyle = style, EasingDirection = dir, RepeatCount = repeatCount or 0, Reverses = reverses or false, DelayTime = delayTime or 0 }
end
method(TweenService, "Create", function(_, obj, info, goals)
  if not isInst(obj) then error("TweenService:Create(деталь, TweenInfo.new(1), {Свойство = значение})", 2) end
  if type(info) ~= "table" or not info.Time then info = TweenInfo.new(1) end
  local tw = { Completed = newSignal("Completed"), PlaybackState = "Begin" }
  local playing = false
  function tw:Play()
    if playing then return end
    playing = true
    spawn(function()
      if info.DelayTime > 0 then wait(info.DelayTime) end
      local reps = info.RepeatCount
      local loops = 0
      repeat
        local from = {}
        for k in pairs(goals) do from[k] = obj[k] end
        local passes = info.Reverses and 2 or 1
        for pass = 1, passes do
          local t0 = __clock()
          while playing do
            local t = math.min(1, (__clock() - t0) / math.max(0.01, info.Time))
            local e = ease(info.EasingStyle, info.EasingDirection, pass == 1 and t or 1 - t)
            for k, g in pairs(goals) do obj[k] = lerpVal(from[k], g, e) end
            if t >= 1 then break end
            wait(0.03)
          end
        end
        loops = loops + 1
      until not playing or (reps >= 0 and loops > reps)
      playing = false
      tw.PlaybackState = "Completed"
      tw.Completed:Fire("Completed")
    end)
  end
  function tw:Cancel() playing = false end
  tw.Pause = tw.Cancel
  return tw
end)
method(Debris, "AddItem", function(_, obj, t)
  spawn(function() wait(t or 10) if isInst(obj) then Inst.Destroy(obj) end end)
end)

-------------------------------------------------------------- физика
local function partsInWorkspace()
  local t = {}
  local function walk(x)
    for _, c in ipairs(D(x).children) do
      local cd = D(c)
      if BASEPART[cd.props.ClassName] and not cd.avatar then t[#t + 1] = c end
      walk(c)
    end
  end
  walk(wsRoot)
  return t
end
-- список деталей пересобираем, только когда меняется дерево объектов
local partsList, partsVer = {}, -1
local function wsParts()
  if partsVer ~= treeVer then
    partsList = partsInWorkspace()
    partsVer = treeVer
  end
  return partsList
end
-- Физика сделана «дешёвой», потому что Lua тут работает внутри браузера и он медленный:
-- * лежащие детали засыпают, пока их опора не сдвинется;
-- * опору ищем в сетке по X/Z, а не среди всех деталей;
-- * на шаг физики есть лимит настоящего времени.
-- Поля Vector3 читаем напрямую (__x, __y, __z) — так намного быстрее, чем через .X
local CELL = 4
local HALF = CELL / 2   -- границы клеток сдвинуты на полклетки: деталь в (0, y, 0) попадает в одну клетку
local BIG = 64          -- деталь больше 64 клеток (например, Baseplate) проверяем отдельно
local QK = 8192         -- в клетке лежат числа «верх × QK + номер детали»: они сортируются без своей функции
local SORT_MIN = 8      -- маленькие клетки не сортируем, а просто смотрим целиком

local function buildGrid(parts)
  local grid, big = {}, {}
  for i = 1, #parts do
    local q = parts[i]
    local qp = q.__d.props
    if qp.CanCollide then
      local pos, size = qp.Position, qp.Size
      -- 0.005: детали, которые только касаются краями, друг на друга не опираются
      local hx, hz = size.__x / 2 - 0.005, size.__z / 2 - 0.005
      if hx < 0 then hx = 0 end
      if hz < 0 then hz = 0 end
      local x, z = pos.__x + HALF, pos.__z + HALF
      local x0, x1, z0, z1 = (x - hx) // CELL, (x + hx) // CELL, (z - hz) // CELL, (z + hz) // CELL
      if i >= QK or not ((x1 - x0 + 1) * (z1 - z0 + 1) <= BIG) then
        big[#big + 1] = q
      else
        local t = pos.__y + size.__y / 2
        if t ~= t or t < -1e9 then t = -1e9 elseif t > 1e9 then t = 1e9 end
        local key = -((-t * 1024) // 1) * QK + i -- верх округляем вверх
        for cx = x0, x1 do
          for cz = z0, z1 do
            local ck = cx * 65536 + cz
            local cell = grid[ck]
            if cell then cell[#cell + 1] = key else grid[ck] = { key } end
          end
        end
      end
    end
  end
  -- в больших клетках: снизу вверх по верхней грани
  for _, cell in pairs(grid) do
    if #cell > SORT_MIN then table.sort(cell) end
  end
  return grid, big
end

-- самая высокая опора в клетке: верх не выше lim, и деталь перекрывает p по X/Z.
-- pd — данные детали p: сравниваем их, а не сами детали (у деталей сравнение — медленный __eq)
local function scanCell(cell, parts, pd, ax, az, hx, hz, lim, bound, floor, floorPart)
  local n = #cell
  local j, stop = n, false
  if n > SORT_MIN then
    -- двоичный поиск: последняя деталь, чей верх не выше низа p
    local lo, hi = 1, n
    j = 0
    while lo <= hi do
      local mid = (lo + hi) // 2
      if cell[mid] < bound then j = mid; lo = mid + 1 else hi = mid - 1 end
    end
    stop = true
  end
  for k = j, 1, -1 do
    local key = cell[k]
    local i = key % QK
    -- в отсортированной клетке ниже искать нечего: за шаг детали только опускались
    if stop and (key - i) // QK <= floor * 1024 then break end
    local q = parts[i]
    local qd = q.__d
    if qd ~= pd then
      local qp = qd.props
      local pb, sb = qp.Position, qp.Size
      local dx, dz = ax - pb.__x, az - pb.__z
      if dx < 0 then dx = -dx end
      if dz < 0 then dz = -dz end
      if dx < hx + sb.__x / 2 and dz < hz + sb.__z / 2 then
        local top = pb.__y + sb.__y / 2
        if top <= lim and top > floor then floor, floorPart = top, q end
      end
    end
  end
  return floor, floorPart
end

local function findFloor(parts, pd, pr, lim, grid, big)
  local floor, floorPart = -1e9, nil
  if lim ~= lim then return floor, floorPart end -- NaN
  local pa, sa = pr.Position, pr.Size
  local ax, az = pa.__x, pa.__z
  local hx, hz = sa.__x / 2 - 0.01, sa.__z / 2 - 0.01
  for i = 1, #big do
    local q = big[i]
    local qd = q.__d
    if qd ~= pd then
      local qp = qd.props
      local pb, sb = qp.Position, qp.Size
      local dx, dz = ax - pb.__x, az - pb.__z
      if dx < 0 then dx = -dx end
      if dz < 0 then dz = -dz end
      if dx < hx + sb.__x / 2 and dz < hz + sb.__z / 2 then
        local top = pb.__y + sb.__y / 2
        if top <= lim and top > floor then floor, floorPart = top, q end
      end
    end
  end
  local l = lim
  if l > 1e9 then l = 1e9 elseif l < -1e9 then l = -1e9 end
  local bound = (-((-l * 1024) // 1) + 1) * QK
  local ex, ez = hx + 0.005, hz + 0.005
  if ex < 0 then ex = 0 end
  if ez < 0 then ez = 0 end
  local x, z = ax + HALF, az + HALF
  local x0, x1, z0, z1 = (x - ex) // CELL, (x + ex) // CELL, (z - ez) // CELL, (z + ez) // CELL
  if not ((x1 - x0 + 1) * (z1 - z0 + 1) <= BIG) then
    -- сама деталь огромная: смотрим все клетки
    for _, cell in pairs(grid) do floor, floorPart = scanCell(cell, parts, pd, ax, az, hx, hz, lim, bound, floor, floorPart) end
  else
    for cx = x0, x1 do
      for cz = z0, z1 do
        local cell = grid[cx * 65536 + cz]
        if cell then floor, floorPart = scanCell(cell, parts, pd, ax, az, hx, hz, lim, bound, floor, floorPart) end
      end
    end
  end
  return floor, floorPart
end

local function stepPart(parts, p, d, now, dt, g, grid, big)
  local pr = d.props
  local pdt = now - (d.pt or (now - dt))
  if pdt > 0.1 then pdt = 0.1 end
  d.pt = now
  local pos, size = pr.Position, pr.Size
  local bottom = pos.__y - size.__y / 2
  -- ищем, на что можно упасть
  local floor, floorPart = -1e9, nil
  if pr.CanCollide then floor, floorPart = findFloor(parts, d, pr, bottom + 0.05, grid, big) end
  local vy = (d.vy or 0) - g * pdt
  local nb = bottom + vy * pdt
  local landed = false
  if nb <= floor then
    nb = floor
    if vy < -20 and floorPart then
      if pr.CanTouch then d.events.Touched:Fire(floorPart) end
      if floorPart.__d.props.CanTouch then floorPart.__d.events.Touched:Fire(p) end
    end
    vy = 0
    landed = true
  end
  d.vy = vy
  if nb < -200 then
    Inst.Destroy(p) -- упало за край мира
  elseif nb - bottom > 0.0001 or bottom - nb > 0.0001 then
    pr.Position = setmetatable({ __x = pos.__x, __y = nb + size.__y / 2, __z = pos.__z }, V3)
    d.geo = (d.geo or 0) + 1
    __dirty = true
  elseif landed or (vy == 0 and g == 0) then
    -- лежит и не двигается: засыпает, пока опора на месте
    d.sleeping = true
    d.sleepOn = floorPart
    d.sleepGeo = floorPart and (floorPart.__d.geo or 0) or 0
    d.pt = nil
  end
end

local lastPhys = nil
local hbAcc = 0
local lastG = nil
local cursor = 1
local heavyFlip = false
local PHYS_BUDGET = 0.010 -- секунд настоящего времени на падение деталей за шаг
physics = function(now)
  local dt = lastPhys and math.min(0.1, now - lastPhys) or 0
  lastPhys = now
  if dt <= 0 then return end
  local g = D(wsRoot).props.Gravity
  local parts = wsParts()
  if g ~= lastG then
    -- поменяли гравитацию — будим всех
    lastG = g
    for i = 1, #parts do parts[i].__d.sleeping = nil end
  end
  -- кто сейчас падает (спящие детали пропускаем)
  local awake = {}
  local baseD = base.__d
  for i = 1, #parts do
    local p = parts[i]
    local d = p.__d
    if not d.props.Anchored and d ~= baseD then
      local s = d.sleeping and d.sleepOn
      if d.sleeping and (not s or ((s.__d.geo or 0) == d.sleepGeo and not s.__d.destroyed)) then
        -- спит
      else
        d.sleeping = nil
        awake[#awake + 1] = p
      end
    end
  end
  local n = #awake
  -- падает очень много деталей: двигаем их через шаг — вдвое дешевле, а падают так же быстро
  if n > 100 then heavyFlip = not heavyFlip else heavyFlip = false end
  if n > 0 and not heavyFlip then
    local t0 = rnow()
    local grid, big = buildGrid(parts)
    if cursor > n then cursor = 1 end
    local start = cursor
    for k = 0, n - 1 do
      local idx = (start - 1 + k) % n + 1
      local p = awake[idx]
      local d = p.__d
      if not d.destroyed then stepPart(parts, p, d, now, dt, g, grid, big) end
      -- не успели всех — продолжим с этого места на следующем шаге
      if k % 32 == 31 and rnow() - t0 > PHYS_BUDGET then
        cursor = idx % n + 1
        break
      end
    end
  end
  -- персонаж идёт к цели
  if avatar.joined and not avatar.dead and avatar.tx then
    local speed = math.max(0, D(hum).props.WalkSpeed)
    local dx, dz = avatar.tx - avatar.x, avatar.tz - avatar.z
    local dist = math.sqrt(dx * dx + dz * dz)
    local step = speed * dt
    if dist <= step or speed <= 0 then
      if speed > 0 then avatar.x, avatar.z = avatar.tx, avatar.tz end
      local target = avatar.target
      avatar.tx, avatar.tz, avatar.target = nil, nil, nil
      if target and isInst(target) and not D(target).destroyed then
        local tp = D(target).props
        avatar.y = tp.Position.Y + tp.Size.Y / 2 + 3
        placeAvatar()
        if tp.CanTouch then D(target).events.Touched:Fire(foot) end
      end
    else
      avatar.x = avatar.x + dx / dist * step
      avatar.z = avatar.z + dz / dist * step
    end
    placeAvatar()
    __dirty = true
  end
  if avatar.joined and not avatar.dead and D(hum).props.Health <= 0 then
    avatar.dead = true
    avatar.deadAt = now
    __dirty = true
  end
  if avatar.dead and now - avatar.deadAt > 3 then respawn() end
  -- Heartbeat ~20 раз в секунду
  hbAcc = hbAcc + dt
  if hbAcc >= 0.05 then
    D(RunService).events.Heartbeat:Fire(hbAcc)
    D(RunService).events.Stepped:Fire(now, hbAcc)
    hbAcc = 0
  end
end

-------------------------------------------------------------- связь с JS
function __touch(id)
  local o = byId[id]
  if not o or D(o).destroyed or not avatar.joined or avatar.dead then return end
  local p = D(o).props
  avatar.tx, avatar.tz, avatar.target = p.Position.X, p.Position.Z, o
end
function __click(id)
  local o = byId[id]
  if not o or D(o).destroyed then return false end
  local cd = Inst.FindFirstChildOfClass(o, "ClickDetector")
  if cd then D(cd).events.MouseClick:Fire(player) return true end
  return false
end
function __hasClick(id)
  local o = byId[id]
  return o ~= nil and Inst.FindFirstChildOfClass(o, "ClickDetector") ~= nil
end
function __chat(msg)
  D(player).events.Chatted:Fire(msg)
end

local function f(n) return string.format("%.3f", n) end
function __snapshot()
  local out = {}
  local function walk(x, depth)
    for _, c in ipairs(D(x).children) do
      local d = D(c)
      local p = d.props
      if BASEPART[p.ClassName] and not d.avatar and c ~= base then
        -- строчку детали пересобираем, только если деталь менялась (при падении — только место)
        local line = d.snapLine
        if not line or d.snapVer ~= d.ver or d.snapGeo ~= d.geo then
          if not d.snapRest or d.snapVer ~= d.ver then
            local hasClick = Inst.FindFirstChildOfClass(c, "ClickDetector") and 1 or 0
            local light = Inst.FindFirstChildOfClass(c, "PointLight") and 1 or 0
            local s, col = p.Size, p.Color
            d.snapHead = "P\t" .. d.id .. "\t" .. p.Name .. "\t"
            d.snapRest = "\t" .. s.__x .. "\t" .. s.__y .. "\t" .. s.__z .. "\t" .. col.__r .. "\t" .. col.__g .. "\t" .. col.__b .. "\t" ..
              p.Transparency .. "\t" .. p.Material.Name .. "\t" .. p.Shape.Name .. "\t" .. hasClick .. "\t" .. light .. "\t" .. (p.Anchored and 1 or 0)
            d.snapVer = d.ver
          end
          local pos = p.Position
          line = d.snapHead .. pos.__x .. "\t" .. pos.__y .. "\t" .. pos.__z .. d.snapRest
          d.snapLine = line
          d.snapGeo = d.geo
        end
        out[#out + 1] = line
      end
      walk(c, depth + 1)
    end
  end
  walk(wsRoot, 0)
  out[#out + 1] = table.concat({ "A", avatar.joined and 1 or 0, avatar.dead and 1 or 0, f(avatar.x), f(avatar.y), f(avatar.z),
    f(D(hum).props.Health), f(D(hum).props.MaxHealth), avatar.tx and 1 or 0 }, "\t")
  local ls = findChild(player, "leaderstats")
  if ls and avatar.joined then
    for _, v in ipairs(D(ls).children) do
      local vp = D(v).props
      if vp.Value ~= nil then out[#out + 1] = table.concat({ "L", vp.Name, tostring(vp.Value) }, "\t") end
    end
  end
  out[#out + 1] = table.concat({ "W", f(D(Lighting).props.ClockTime), f(D(workspace).props.Gravity) }, "\t")
  return table.concat(out, "\n")
end

-------------------------------------------------------------- запуск кода игрока
script = newInstance("Script")
D(script).props.Name = "Script"

function __start(src, inPart)
  if inPart then
    local holder = Instance.new("Part")
    holder.Name = "Деталь"
    holder.Anchored = true
    holder.Position = Vector3.new(0, 0.5, -8)
    holder.Size = Vector3.new(6, 1, 6)
    holder.Color = Color3.fromRGB(13, 105, 172)
    holder.Parent = workspace
    setParent(script, holder)
  else
    setParent(script, services.ServerScriptService)
  end
  local fn, err = load(src, "=Script", "t")
  if not fn then
    __out("error", err)
    return false
  end
  spawn(fn)
  spawn(function() wait(0.15) join() end)
  return true
end

_G.spawn = task.spawn
