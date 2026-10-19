--!strict
-- Таймлайн ролика: список планов по порядку и поиск плана по времени.

local Config = require(script.Parent:WaitForChild("Config"))
local ShotsFolder = script.Parent:WaitForChild("Shots")

local Timeline = {}

local shots: { any } = {}
for _, id in Config.ShotOrder do
	local shot: any = (require :: any)((ShotsFolder :: any):WaitForChild(id))
	shot.id = shot.id or id
	table.insert(shots, shot)
end
table.sort(shots, function(a: any, b: any)
	return a.start < b.start
end)

Timeline.shots = shots
Timeline.duration = Config.Duration

function Timeline.shotAt(t: number): (any, number)
	for i = #shots, 1, -1 do
		if t >= shots[i].start then
			return shots[i], i
		end
	end
	return shots[1], 1
end

function Timeline.byId(id: string): any
	for _, s in shots do
		if s.id == id then
			return s
		end
	end
	return nil
end

return Timeline
