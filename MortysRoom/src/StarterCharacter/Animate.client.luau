-- Minimal R6 animation script for the Morty StarterCharacter (uses Roblox's default R6 animations).
local character = script.Parent
local humanoid = character:WaitForChild("Humanoid") :: Humanoid
local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)

local IDS = {
	idle = "rbxassetid://180435571",
	walk = "rbxassetid://180426354",
	jump = "rbxassetid://125750702",
	fall = "rbxassetid://180436148",
	climb = "rbxassetid://180436334",
	sit = "rbxassetid://178130996",
}

local tracks: { [string]: AnimationTrack } = {}
for name, id in IDS do
	local anim = Instance.new("Animation")
	anim.Name = name
	anim.AnimationId = id
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(anim)
	end)
	if ok and track then
		tracks[name] = track
		track.Priority = if name == "idle" then Enum.AnimationPriority.Idle else Enum.AnimationPriority.Movement
	end
end

local current: AnimationTrack? = nil
local function play(name: string, fade: number?, speed: number?)
	local track = tracks[name]
	if not track then
		return
	end
	if current ~= track then
		if current then
			current:Stop(fade or 0.2)
		end
		current = track
		track:Play(fade or 0.2)
	end
	if speed then
		track:AdjustSpeed(speed)
	end
end

humanoid.Running:Connect(function(speed: number)
	if speed > 0.5 then
		play("walk", 0.2, speed / 14.5)
	else
		play("idle", 0.3, 1)
	end
end)
humanoid.Jumping:Connect(function(active: boolean)
	if active then
		play("jump", 0.1)
	end
end)
humanoid.FreeFalling:Connect(function(active: boolean)
	if active then
		play("fall", 0.2)
	end
end)
humanoid.Climbing:Connect(function(speed: number)
	play("climb", 0.1, speed / 5)
end)
humanoid.Seated:Connect(function(active: boolean)
	if active then
		play("sit", 0.4)
	end
end)

play("idle", 0)
