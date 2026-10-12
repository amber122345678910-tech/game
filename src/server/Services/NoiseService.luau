--!strict
-- Шум: единая точка, через которую игроки, двери, ловушки и оружие "звучат" для ИИ.
-- Слушатели (InmateService, Director) подписываются через NoiseService.Emitted.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Signal"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Config = require(Shared:WaitForChild("Config"))

local NoiseService = {}

export type Noise = {
	Position: Vector3,
	Radius: number,
	Kind: string,
	Player: Player?,
	Time: number,
}

NoiseService.Emitted = Signal.new() :: Signal.Signal<Noise>

local recent: { Noise } = {}
local MAX_RECENT = 32

function NoiseService.emit(position: Vector3, kind: string, player: Player?, radiusOverride: number?)
	local radius = radiusOverride or Config.Noise[kind] or 10
	local noise: Noise = {
		Position = position,
		Radius = radius,
		Kind = kind,
		Player = player,
		Time = os.clock(),
	}
	table.insert(recent, noise)
	if #recent > MAX_RECENT then
		table.remove(recent, 1)
	end
	NoiseService.Emitted:Fire(noise)
	-- Для визуала/звука на клиентах (ненадёжно, это только косметика)
	if radius >= 15 then
		Remotes.Noise:FireAllClients(position, radius)
	end
end

-- Самый громкий недавний шум в радиусе слуха от точки (за последние seconds секунд)
function NoiseService.loudestNear(position: Vector3, hearRange: number, seconds: number): Noise?
	local now = os.clock()
	local best: Noise? = nil
	local bestScore = 0
	for _, n in recent do
		if now - n.Time <= seconds then
			local dist = (n.Position - position).Magnitude
			local reach = n.Radius + hearRange
			if dist <= reach then
				local score = n.Radius * (1 - dist / math.max(reach, 1)) + (seconds - (now - n.Time))
				if score > bestScore then
					best = n
					bestScore = score
				end
			end
		end
	end
	return best
end

function NoiseService.clear()
	table.clear(recent)
end

return NoiseService
