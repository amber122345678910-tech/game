--!strict
-- Ростер пациентов: у каждого одно правило, свой телеграф и параметры ИИ.
-- Тексты (имя, правило, оповещение) — в Locale по ключам Inmate_<Id>_Name / _Rule / _Alert / _Tell.

export type InmateKind = "Chaser" | "Lamplighter" | "Knocker" | "StillOne" | "Blind" | "Sentinel" | "Twins" | "Collector" | "RedLight" | "Boss"

export type InmateLook = {
	Scale: Vector3, -- множители ширины/высоты/глубины рига
	Body: Color3,
	Head: Color3,
	Accent: Color3,
	Material: Enum.Material,
	Accessory: string, -- "Lantern" | "Blindfold" | "Shawl" | "Sack" | "Flashlight" | "Hollow" | "None" | "Mannequin"
	Glow: boolean, -- есть ли светящийся элемент (фонарь, глаза)
}

export type InmateDef = {
	Id: string,
	Number: string,
	Kind: InmateKind,
	Unlock: number, -- с какой ночи может выпасть
	Weight: number, -- вес при случайном выборе
	Bodies: number, -- сколько тел (Twins = 2)
	Lethal: boolean,
	RoamSpeed: number,
	ChaseSpeed: number,
	UnseenSpeed: number, -- StillOne: скорость, когда никто не смотрит
	HP: number,
	HearRange: number,
	SightLit: number,
	SightDark: number,
	StunImmune: boolean,
	OpensHiding: boolean, -- проверяет укрытия
	BreaksInstantly: boolean, -- доски и замки ломает мгновенно
	BoardBreakTime: number, -- секунд на одну доску
	LockBreakTime: number,
	Look: InmateLook,
	Sounds: { Voice: string, Chase: string, Tell: string },
	-- особые параметры
	KnockDelay: number,
	LookDuration: number, -- RedLight: сколько смотрит
	CycleMin: number,
	CycleMax: number,
	LullabyRange: number,
	WaitAtHiding: number,
	ShakeRange: number,
}

local function def(d: { [string]: any }): InmateDef
	return {
		Id = d.Id,
		Number = d.Number,
		Kind = d.Kind,
		Unlock = d.Unlock or 1,
		Weight = d.Weight or 10,
		Bodies = d.Bodies or 1,
		Lethal = d.Lethal ~= false,
		RoamSpeed = d.RoamSpeed or 10,
		ChaseSpeed = d.ChaseSpeed or 21,
		UnseenSpeed = d.UnseenSpeed or 0,
		HP = d.HP or 100,
		HearRange = d.HearRange or 20,
		SightLit = d.SightLit or 40,
		SightDark = d.SightDark or 14,
		StunImmune = d.StunImmune == true,
		OpensHiding = d.OpensHiding ~= false,
		BreaksInstantly = d.BreaksInstantly == true,
		BoardBreakTime = d.BoardBreakTime or 3,
		LockBreakTime = d.LockBreakTime or 4,
		Look = d.Look,
		Sounds = d.Sounds or { Voice = "", Chase = "ChaseMusic", Tell = "" },
		KnockDelay = d.KnockDelay or 6,
		LookDuration = d.LookDuration or 2.5,
		CycleMin = d.CycleMin or 5,
		CycleMax = d.CycleMax or 9,
		LullabyRange = d.LullabyRange or 45,
		WaitAtHiding = d.WaitAtHiding or 0,
		ShakeRange = d.ShakeRange or 0,
	}
end

local function look(scale: Vector3, body: Color3, head: Color3, accent: Color3, accessory: string, material: Enum.Material?, glow: boolean?): InmateLook
	return {
		Scale = scale,
		Body = body,
		Head = head,
		Accent = accent,
		Material = material or Enum.Material.Fabric,
		Accessory = accessory,
		Glow = glow == true,
	}
end

local Inmates = {}

Inmates.List = {
	def({
		Id = "Sleepwalker", Number = "005", Kind = "Chaser", Unlock = 1, Weight = 10,
		RoamSpeed = 9, ChaseSpeed = 21, HP = 100, HearRange = 20, SightLit = 40, SightDark = 14,
		Look = look(Vector3.new(1, 1.05, 1), Color3.fromRGB(120, 130, 150), Color3.fromRGB(190, 180, 170), Color3.fromRGB(70, 75, 90), "None"),
		Sounds = { Voice = "Mumble", Chase = "ChaseMusic", Tell = "StepHeavy" },
	}),
	def({
		Id = "Lamplighter", Number = "019", Kind = "Lamplighter", Unlock = 2, Weight = 9,
		RoamSpeed = 10, ChaseSpeed = 20, HP = 150, HearRange = 15, SightLit = 45, SightDark = 8,
		Look = look(Vector3.new(0.9, 1.35, 0.9), Color3.fromRGB(28, 26, 30), Color3.fromRGB(200, 190, 170), Color3.fromRGB(255, 180, 60), "Lantern", Enum.Material.Fabric, true),
		Sounds = { Voice = "LanternCreak", Chase = "ChaseMusic", Tell = "BulbBuzz" },
	}),
	def({
		Id = "Knocker", Number = "044", Kind = "Knocker", Unlock = 2, Weight = 9,
		RoamSpeed = 11, ChaseSpeed = 23, HP = 120, HearRange = 25, SightLit = 40, SightDark = 14, KnockDelay = 6, BoardBreakTime = 3,
		Look = look(Vector3.new(1.1, 1.1, 1.1), Color3.fromRGB(90, 60, 40), Color3.fromRGB(170, 150, 130), Color3.fromRGB(50, 35, 25), "BigHands"),
		Sounds = { Voice = "Breathing", Chase = "ChaseMusic", Tell = "Knock" },
	}),
	def({
		Id = "StillOne", Number = "073", Kind = "StillOne", Unlock = 3, Weight = 8,
		RoamSpeed = 0, ChaseSpeed = 0, UnseenSpeed = 38, HP = 300, HearRange = 0, SightLit = 60, SightDark = 60, StunImmune = true, OpensHiding = false,
		Look = look(Vector3.new(1, 1.15, 1), Color3.fromRGB(225, 222, 215), Color3.fromRGB(230, 228, 222), Color3.fromRGB(200, 196, 190), "Mannequin", Enum.Material.SmoothPlastic),
		Sounds = { Voice = "", Chase = "", Tell = "Creak" },
	}),
	def({
		Id = "Whistler", Number = "088", Kind = "Blind", Unlock = 3, Weight = 9,
		RoamSpeed = 10, ChaseSpeed = 24, HP = 120, HearRange = 60, SightLit = 6, SightDark = 6,
		Look = look(Vector3.new(0.95, 1.1, 0.95), Color3.fromRGB(60, 70, 60), Color3.fromRGB(180, 170, 160), Color3.fromRGB(210, 200, 190), "Blindfold"),
		Sounds = { Voice = "Whistle", Chase = "ChaseMusic", Tell = "Whistle" },
	}),
	def({
		Id = "Vesper", Number = "102", Kind = "Sentinel", Unlock = 4, Weight = 7,
		RoamSpeed = 0, ChaseSpeed = 0, HP = 400, HearRange = 0, SightLit = 0, SightDark = 0, StunImmune = true, OpensHiding = true, LullabyRange = 45,
		Look = look(Vector3.new(1.1, 0.9, 1.1), Color3.fromRGB(80, 40, 60), Color3.fromRGB(200, 190, 180), Color3.fromRGB(160, 120, 140), "Shawl"),
		Sounds = { Voice = "MusicBox", Chase = "", Tell = "MusicBox" },
	}),
	def({
		Id = "Twins", Number = "121", Kind = "Twins", Unlock = 5, Weight = 7, Bodies = 2,
		RoamSpeed = 13, ChaseSpeed = 18, HP = 100, HearRange = 20, SightLit = 40, SightDark = 16,
		Look = look(Vector3.new(0.85, 0.95, 0.85), Color3.fromRGB(200, 200, 205), Color3.fromRGB(215, 210, 205), Color3.fromRGB(120, 120, 130), "None"),
		Sounds = { Voice = "Whisper", Chase = "ChaseMusic", Tell = "Whisper" },
	}),
	def({
		Id = "Collector", Number = "136", Kind = "Collector", Unlock = 3, Weight = 5, Lethal = false,
		RoamSpeed = 12, ChaseSpeed = 12, HP = 80, HearRange = 10, SightLit = 20, SightDark = 10, OpensHiding = false,
		Look = look(Vector3.new(1, 0.9, 1.2), Color3.fromRGB(70, 65, 50), Color3.fromRGB(160, 150, 130), Color3.fromRGB(120, 100, 60), "Sack"),
		Sounds = { Voice = "Keys", Chase = "", Tell = "Keys" },
	}),
	def({
		Id = "MrStop", Number = "150", Kind = "RedLight", Unlock = 4, Weight = 8,
		RoamSpeed = 8, ChaseSpeed = 40, HP = 200, HearRange = 10, SightLit = 45, SightDark = 45, LookDuration = 2.5, CycleMin = 5, CycleMax = 9,
		Look = look(Vector3.new(1.05, 1.2, 1.05), Color3.fromRGB(40, 40, 45), Color3.fromRGB(190, 180, 170), Color3.fromRGB(230, 40, 40), "Flashlight", Enum.Material.Fabric, true),
		Sounds = { Voice = "", Chase = "ChaseMusic", Tell = "Click" },
	}),
	def({
		Id = "HollowMan", Number = "177", Kind = "Boss", Unlock = 6, Weight = 6,
		RoamSpeed = 8, ChaseSpeed = 16, HP = 600, HearRange = 30, SightLit = 45, SightDark = 20, BreaksInstantly = true, WaitAtHiding = 8, ShakeRange = 25, StunImmune = false,
		Look = look(Vector3.new(1.6, 1.7, 1.4), Color3.fromRGB(25, 22, 22), Color3.fromRGB(30, 28, 28), Color3.fromRGB(255, 120, 40), "Hollow", Enum.Material.Slate, true),
		Sounds = { Voice = "BossRumble", Chase = "ChaseMusic", Tell = "StepHeavy" },
	}),
} :: { InmateDef }

Inmates.ById = {} :: { [string]: InmateDef }
for _, d in Inmates.List do
	Inmates.ById[d.Id] = d
end

function Inmates.get(id: string): InmateDef?
	return Inmates.ById[id]
end

-- Выбор пациентов на ночь. lastIds — кто был прошлой ночью (не повторяем подряд).
-- count — сколько "слотов" (Twins занимают 1 слот, но дают 2 тела). forceBoss — последняя ночь Hard/Nightmare.
function Inmates.pickForNight(night: number, count: number, lastIds: { string }, forceBoss: boolean, rng: Random): { string }
	local picked: { string } = {}
	local function isLast(id: string): boolean
		return table.find(lastIds, id) ~= nil
	end
	if night == 1 then
		table.insert(picked, "Sleepwalker")
	elseif night == 2 then
		table.insert(picked, if rng:NextNumber() < 0.5 then "Knocker" else "Lamplighter")
	end
	if forceBoss and not table.find(picked, "HollowMan") then
		table.insert(picked, "HollowMan")
	end
	local guard = 0
	while #picked < count and guard < 50 do
		guard += 1
		local pool: { InmateDef } = {}
		local total = 0
		for _, d in Inmates.List do
			if d.Unlock <= night and not table.find(picked, d.Id) and not isLast(d.Id) then
				-- два "сидячих"/безвредных в одну ночь не нужны
				if not (d.Kind == "Sentinel" or d.Kind == "Collector") or #picked == 0 then
					table.insert(pool, d)
					total += d.Weight
				end
			end
		end
		if #pool == 0 then
			-- всё исключено (например, ночь 1-2 с count 2): берём любого разблокированного
			for _, d in Inmates.List do
				if d.Unlock <= night and not table.find(picked, d.Id) then
					table.insert(pool, d)
					total += d.Weight
				end
			end
			if #pool == 0 then
				break
			end
		end
		local roll = rng:NextNumber() * total
		for _, d in pool do
			roll -= d.Weight
			if roll <= 0 then
				table.insert(picked, d.Id)
				break
			end
		end
	end
	return picked
end

return Inmates
