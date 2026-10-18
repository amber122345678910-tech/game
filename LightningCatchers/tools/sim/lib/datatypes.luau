--!nocheck
-- Roblox datatypes that Lune's @lune/roblox does not provide (or provides incompletely):
-- TweenInfo, RaycastParams, RaycastResult, OverlapParams, Random, Font (all fonts), DateTime, PathWaypoint stub.
-- Each value is a locked table registered in DT.kind so the sim's typeof() reports the Roblox type name.
local roblox = require("@lune/roblox")

local Enum = roblox.Enum

local DT = {}
DT.kind = setmetatable({}, { __mode = "k" }) -- value -> "TweenInfo" | ...

local function lockedValue(kindName, fields, methods, tostr)
	local obj = {}
	local mt = {
		__index = function(_, k)
			local v = fields[k]
			if v ~= nil then
				return v
			end
			if methods and methods[k] then
				return methods[k]
			end
			error(tostring(k) .. " is not a valid member of " .. kindName, 2)
		end,
		__newindex = function(_, k)
			error(tostring(k) .. " cannot be assigned to (" .. kindName .. " is immutable)", 2)
		end,
		__tostring = tostr or function()
			return kindName
		end,
		__metatable = "The metatable is locked",
	}
	setmetatable(obj, mt)
	DT.kind[obj] = kindName
	return obj, fields
end

local function enumCheck(v, enum, argName, fn)
	if v == nil then
		return nil
	end
	if typeof(v) ~= "EnumItem" or v.EnumType ~= enum then
		error(string.format("invalid argument %s to '%s' (%s expected, got %s)", argName, fn, tostring(enum), typeof(v)), 3)
	end
	return v
end

----------------------------------------------------------------------
-- TweenInfo
----------------------------------------------------------------------
DT.TweenInfo = {
	new = function(time, style, direction, repeatCount, reverses, delayTime)
		if time ~= nil and type(time) ~= "number" then
			error("invalid argument #1 to 'new' (number expected, got " .. typeof(time) .. ")", 2)
		end
		style = enumCheck(style, Enum.EasingStyle, "#2", "TweenInfo.new") or Enum.EasingStyle.Quad
		direction = enumCheck(direction, Enum.EasingDirection, "#3", "TweenInfo.new") or Enum.EasingDirection.Out
		if repeatCount ~= nil and type(repeatCount) ~= "number" then
			error("invalid argument #4 to 'new' (number expected, got " .. typeof(repeatCount) .. ")", 2)
		end
		if reverses ~= nil and type(reverses) ~= "boolean" then
			error("invalid argument #5 to 'new' (boolean expected, got " .. typeof(reverses) .. ")", 2)
		end
		if delayTime ~= nil and type(delayTime) ~= "number" then
			error("invalid argument #6 to 'new' (number expected, got " .. typeof(delayTime) .. ")", 2)
		end
		local fields = {
			Time = time or 1,
			EasingStyle = style,
			EasingDirection = direction,
			RepeatCount = repeatCount or 0,
			Reverses = reverses or false,
			DelayTime = delayTime or 0,
		}
		return (lockedValue("TweenInfo", fields, nil, function()
			return string.format("TweenInfo(%g)", fields.Time)
		end))
	end,
}

----------------------------------------------------------------------
-- RaycastParams / OverlapParams (mutable property bags)
----------------------------------------------------------------------
local function paramsClass(kindName, defaults)
	return {
		new = function()
			local fields = table.clone(defaults)
			fields.FilterDescendantsInstances = {}
			local obj = {}
			local methods = {}
			function methods.AddToFilter(_, inst)
				if typeof(inst) == "table" then
					for _, i in inst do
						table.insert(fields.FilterDescendantsInstances, i)
					end
				else
					table.insert(fields.FilterDescendantsInstances, inst)
				end
			end
			setmetatable(obj, {
				__index = function(_, k)
					local v = fields[k]
					if v ~= nil then
						return v
					end
					if methods[k] then
						return methods[k]
					end
					error(tostring(k) .. " is not a valid member of " .. kindName, 2)
				end,
				__newindex = function(_, k, v)
					if defaults[k] == nil and k ~= "FilterDescendantsInstances" then
						error(tostring(k) .. " is not a valid member of " .. kindName, 2)
					end
					if k == "FilterDescendantsInstances" then
						if type(v) ~= "table" then
							error("FilterDescendantsInstances must be an array of Instances", 2)
						end
						v = table.clone(v)
					elseif k == "FilterType" then
						if typeof(v) ~= "EnumItem" or v.EnumType ~= Enum.RaycastFilterType then
							error("Unable to assign property FilterType. EnumItem of type RaycastFilterType expected", 2)
						end
					end
					fields[k] = v
				end,
				__tostring = function()
					return kindName .. "{}"
				end,
				__metatable = "The metatable is locked",
			})
			DT.kind[obj] = kindName
			return obj
		end,
	}
end

DT.RaycastParams = paramsClass("RaycastParams", {
	FilterType = Enum.RaycastFilterType.Exclude,
	IgnoreWater = false,
	CollisionGroup = "Default",
	RespectCanCollide = false,
	BruteForceAllSlow = false,
})
DT.OverlapParams = paramsClass("OverlapParams", {
	FilterType = Enum.RaycastFilterType.Exclude,
	CollisionGroup = "Default",
	RespectCanCollide = false,
	MaxParts = 0,
	BruteForceAllSlow = false,
})

function DT.raycastResult(inst, pos, normal, distance, material)
	return (lockedValue("RaycastResult", {
		Instance = inst,
		Position = pos,
		Normal = normal,
		Distance = distance,
		Material = material or Enum.Material.Plastic,
	}))
end

----------------------------------------------------------------------
-- Random (deterministic xorshift-style, seeded)
----------------------------------------------------------------------
local function makeGen(seed)
	-- 53-bit LCG-free generator: splitmix-ish on doubles via integer math in two 26-bit halves
	local s = math.floor(math.abs(seed or 0)) % 2147483647
	if s == 0 then
		s = 123456789
	end
	local state = s
	return function()
		-- Park–Miller minimal standard (deterministic, good enough for gameplay rolls)
		state = (state * 48271) % 2147483647
		local a = state
		state = (state * 48271) % 2147483647
		return (a + state / 2147483647) / 2147483647 % 1
	end
end
DT.makeGen = makeGen

local randomCounter = 0
DT.Random = {
	new = function(seed)
		if seed == nil then
			randomCounter += 1
			seed = 777 + randomCounter * 7919
		end
		if type(seed) ~= "number" then
			error("invalid argument #1 to 'new' (number expected, got " .. typeof(seed) .. ")", 2)
		end
		local gen = makeGen(seed)
		local methods = {}
		function methods.NextNumber(_, a, b)
			local r = gen()
			if a == nil then
				return r
			end
			return a + (b - a) * r
		end
		function methods.NextInteger(_, a, b)
			if type(a) ~= "number" or type(b) ~= "number" then
				error("invalid argument to 'NextInteger' (number expected)", 2)
			end
			a, b = math.floor(a), math.floor(b)
			if b < a then
				a, b = b, a
			end
			return a + math.floor(gen() * (b - a + 1))
		end
		function methods.NextUnitVector()
			local z = gen() * 2 - 1
			local t = gen() * math.pi * 2
			local r = math.sqrt(1 - z * z)
			return roblox.Vector3.new(r * math.cos(t), r * math.sin(t), z)
		end
		function methods.Shuffle(_, t)
			for i = #t, 2, -1 do
				local j = 1 + math.floor(gen() * i)
				t[i], t[j] = t[j], t[i]
			end
		end
		function methods.Clone()
			return DT.Random.new(seed)
		end
		return (lockedValue("Random", {}, methods))
	end,
}

----------------------------------------------------------------------
-- Font (Lune's Font.fromEnum does not know newer fonts like BuilderSans*)
----------------------------------------------------------------------
local FAMILY_OF = {
	BuilderSans = "BuilderSans",
	BuilderSansMedium = "BuilderSans",
	BuilderSansBold = "BuilderSans",
	BuilderSansExtraBold = "BuilderSans",
	FredokaOne = "FredokaOne",
	GothamBlack = "GothamSSm",
	GothamBold = "GothamSSm",
	GothamMedium = "GothamSSm",
	Gotham = "GothamSSm",
	SourceSans = "SourceSansPro",
	SourceSansBold = "SourceSansPro",
	SourceSansSemibold = "SourceSansPro",
	Arial = "Arial",
	ArialBold = "Arial",
	Legacy = "LegacyArial",
	Cartoon = "ComicNeueAngular",
	Arcade = "PressStart2P",
	Highway = "HighwayGothic",
	SciFi = "Zekton",
	Fantasy = "Balthazar",
	Antique = "Kalam",
	Code = "Inconsolata",
	Ubuntu = "Ubuntu",
	Montserrat = "Montserrat",
	MontserratBold = "Montserrat",
	MontserratBlack = "Montserrat",
	LuckiestGuy = "LuckiestGuy",
	Bangers = "Bangers",
	Creepster = "Creepster",
	Oswald = "Oswald",
	Nunito = "Nunito",
	Roboto = "Roboto",
	RobotoMono = "RobotoMono",
	Sarpanch = "Sarpanch",
	PermanentMarker = "PermanentMarker",
	Merriweather = "Merriweather",
	DenkOne = "DenkOne",
	JosefinSans = "JosefinSans",
	TitilliumWeb = "TitilliumWeb",
	AmaticSC = "AmaticSC",
	Bodoni = "AccanthisADFStd",
	Garamond = "Guru",
	IndieFlower = "IndieFlower",
	SpecialElite = "SpecialElite",
	Kalam = "Kalam",
	GrenzeGotisch = "GrenzeGotisch",
}
local WEIGHT_OF = {
	BuilderSansMedium = "Medium",
	BuilderSansBold = "Bold",
	BuilderSansExtraBold = "ExtraBold",
	GothamBlack = "Heavy",
	GothamBold = "Bold",
	GothamMedium = "Medium",
	SourceSansBold = "Bold",
	SourceSansSemibold = "SemiBold",
	ArialBold = "Bold",
	MontserratBold = "Bold",
	MontserratBlack = "Heavy",
}

local function newFont(family, weight, style)
	if type(family) ~= "string" then
		error("invalid argument #1 to 'new' (string expected, got " .. typeof(family) .. ")", 3)
	end
	weight = weight or Enum.FontWeight.Regular
	style = style or Enum.FontStyle.Normal
	if typeof(weight) ~= "EnumItem" or weight.EnumType ~= Enum.FontWeight then
		error("invalid argument #2 to 'new' (Enum.FontWeight expected, got " .. typeof(weight) .. ")", 3)
	end
	if typeof(style) ~= "EnumItem" or style.EnumType ~= Enum.FontStyle then
		error("invalid argument #3 to 'new' (Enum.FontStyle expected, got " .. typeof(style) .. ")", 3)
	end
	local fields = { Family = family, Weight = weight, Style = style, Bold = weight.Value >= 600 }
	return (lockedValue("Font", fields, nil, function()
		return string.format("Font { Family = %s, Weight = %s, Style = %s }", family, weight.Name, style.Name)
	end))
end

DT.Font = {
	new = function(family, weight, style)
		return newFont(family, weight, style)
	end,
	fromEnum = function(e)
		if typeof(e) ~= "EnumItem" or e.EnumType ~= Enum.Font then
			error("invalid argument #1 to 'fromEnum' (Enum.Font expected, got " .. typeof(e) .. ")", 2)
		end
		local fam = FAMILY_OF[e.Name] or e.Name
		local w = WEIGHT_OF[e.Name]
		return newFont("rbxasset://fonts/families/" .. fam .. ".json", if w then Enum.FontWeight[w] else nil, nil)
	end,
	fromName = function(name, weight, style)
		return newFont("rbxasset://fonts/families/" .. tostring(name) .. ".json", weight, style)
	end,
	fromId = function(id, weight, style)
		return newFont("rbxassetid://" .. tostring(id), weight, style)
	end,
}

-- Convert a Lune Font (from the deserialized place) to ours
function DT.fromLuneFont(f)
	local ok, fam = pcall(function()
		return f.Family
	end)
	if not ok then
		return DT.Font.new("rbxasset://fonts/families/SourceSansPro.json")
	end
	local w = f.Weight
	local s = f.Style
	return newFont(fam, w, s)
end

----------------------------------------------------------------------
-- DateTime (minimal)
----------------------------------------------------------------------
local function newDateTime(ms)
	local fields = { UnixTimestampMillis = ms, UnixTimestamp = math.floor(ms / 1000) }
	local methods = {}
	function methods.ToUniversalTime()
		local t = os.date("!*t", math.floor(ms / 1000))
		return { Year = t.year, Month = t.month, Day = t.day, Hour = t.hour, Minute = t.min, Second = t.sec, Millisecond = ms % 1000 }
	end
	function methods.ToLocalTime()
		return methods.ToUniversalTime()
	end
	function methods.ToIsoDate()
		return os.date("!%Y-%m-%dT%H:%M:%SZ", math.floor(ms / 1000))
	end
	function methods.FormatUniversalTime(_, fmt)
		return os.date("!%Y-%m-%d %H:%M:%S", math.floor(ms / 1000))
	end
	methods.FormatLocalTime = methods.FormatUniversalTime
	return (lockedValue("DateTime", fields, methods))
end

function DT.makeDateTime(nowFn)
	return {
		now = function()
			return newDateTime(math.floor(nowFn() * 1000))
		end,
		fromUnixTimestamp = function(t)
			return newDateTime(math.floor(t * 1000))
		end,
		fromUnixTimestampMillis = function(ms)
			return newDateTime(ms)
		end,
		fromUniversalTime = function(y, mo, d, h, mi, s, ms)
			local t = os.time({ year = y or 1970, month = mo or 1, day = d or 1, hour = h or 0, min = mi or 0, sec = s or 0 })
			return newDateTime(t * 1000 + (ms or 0))
		end,
	}
end

return DT
