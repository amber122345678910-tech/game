--!strict
-- Проигрыватель KeyframeSequence без Animator: компилирует KFS в массивы по суставам
-- и выдаёт Motor6D.Transform для любого момента времени (можно перематывать, синхронизировать с музыкой).
-- Работает и в Roblox, и в Lune (превью).

local Easing = require(script.Parent:WaitForChild("Easing"))
local MathUtil = require(script.Parent:WaitForChild("MathUtil"))

local KFS = {}

export type Track = {
	times: { number },
	cfs: { CFrame },
	styles: { string },
	dirs: { string },
}

export type Clip = {
	name: string,
	length: number,
	tracks: { [string]: Track },
}

local function poseIsKeyed(pose: any): boolean
	-- Позы с Weight = 0 — только «контейнеры» иерархии (так сохраняет Animation Editor).
	return pose.Weight > 0
end

function KFS.compile(kfs: Instance): Clip
	local frames = {}
	for _, kf in kfs:GetChildren() do
		if kf:IsA("Keyframe") then
			table.insert(frames, kf)
		end
	end
	table.sort(frames, function(a: any, b: any)
		return a.Time < b.Time
	end)

	local tracks: { [string]: Track } = {}
	local length = 0
	local function visit(parent: Instance, time: number)
		for _, child in parent:GetChildren() do
			if child:IsA("Pose") then
				local pose = child :: any
				if poseIsKeyed(pose) then
					local tr = tracks[pose.Name]
					if not tr then
						tr = { times = {}, cfs = {}, styles = {}, dirs = {} }
						tracks[pose.Name] = tr
					end
					table.insert(tr.times, time)
					table.insert(tr.cfs, pose.CFrame)
					table.insert(tr.styles, pose.EasingStyle.Name)
					table.insert(tr.dirs, pose.EasingDirection.Name)
				end
				visit(pose, time)
			end
		end
	end
	for _, kf in frames do
		local time = (kf :: any).Time
		length = math.max(length, time)
		visit(kf, time)
	end
	return { name = kfs.Name, length = length, tracks = tracks }
end

-- out[имя детали Part1] = Transform для момента t (секунды от начала клипа).
function KFS.sample(clip: Clip, t: number, out: { [string]: CFrame })
	for name, tr in clip.tracks do
		local times = tr.times
		local n = #times
		if n == 1 or t <= times[1] then
			out[name] = tr.cfs[1]
		elseif t >= times[n] then
			out[name] = tr.cfs[n]
		else
			local i = MathUtil.findSegment(times, t)
			local t0, t1 = times[i], times[i + 1]
			local a = if t1 > t0 then (t - t0) / (t1 - t0) else 1
			local e = Easing.pose(tr.styles[i], tr.dirs[i], a)
			out[name] = tr.cfs[i]:Lerp(tr.cfs[i + 1], e)
		end
	end
end

return KFS
