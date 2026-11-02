-- Server: spawns Morty (the StarterCharacter) only when the player presses Play.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

Players.CharacterAutoLoads = false

local Remotes = ReplicatedStorage:WaitForChild("Game"):WaitForChild("Remotes")
local house = workspace:WaitForChild("MortysHouse")
local spawns = house:WaitForChild("Spawns")
local wakePoint = spawns:WaitForChild("WakeUpPoint") :: BasePart
local holdPoint = spawns:WaitForChild("HoldPoint") :: BasePart

local function rootOf(char: Model?): BasePart?
	return if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

-- Spawn the character but keep it frozen out of sight while the wake-up cutscene plays.
Remotes.RequestSpawn.OnServerInvoke = function(player: Player)
	if not (player.Character and player.Character.Parent) then
		player:LoadCharacter()
	end
	local char = player.Character
	local hrp = char and char:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if char and hrp then
		hrp.Anchored = true
		char:PivotTo(holdPoint.CFrame)
	end
	return true
end

-- Cutscene finished: put Morty next to his bed and let him move.
Remotes.ReleaseCharacter.OnServerEvent:Connect(function(player: Player)
	local char = player.Character
	local hrp = rootOf(char)
	if char and hrp then
		char:PivotTo(wakePoint.CFrame)
		hrp.Anchored = false
	end
end)

-- Back to the main menu: remove the character, the menu shows sleeping Morty again.
Remotes.ReturnToMenu.OnServerEvent:Connect(function(player: Player)
	local char = player.Character
	if char then
		player.Character = nil
		char:Destroy()
	end
end)

-- Safety net: if Morty dies (e.g. glitches out of the world), respawn him by the bed.
Players.PlayerAdded:Connect(function(player: Player)
	player.CharacterAdded:Connect(function(char: Model)
		local hum = char:WaitForChild("Humanoid") :: Humanoid
		hum.Died:Connect(function()
			task.wait(2)
			if player.Parent and player.Character == char then
				player:LoadCharacter()
				local c = player.Character
				if c then
					c:PivotTo(wakePoint.CFrame)
				end
			end
		end)
	end)
end)
