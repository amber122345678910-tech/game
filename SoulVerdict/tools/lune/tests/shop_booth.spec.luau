--!nocheck
-- Lobby ShopBooth shopkeeper ("sleepy Sans", Shared/Maps/Shopkeeper + Client/Controllers/ShopkeeperController):
-- the lobby builds with the NPC (named, frozen ghost parts, inside the booth, behind the counter, asleep on it),
-- the pure forward kinematics reproduce the built pose and give a sensible awake pose, the controller's pure state
-- machine (asleep -> awake -> bye -> asleep, by distance and timers), look-at clamps, typing, and the strings.
local task = require("@lune/task")

local SHOPKEEPER = "ReplicatedStorage.Shared.Maps.Shopkeeper"
local LOBBY = "ReplicatedStorage.Shared.Maps.Lobby"
local STRINGS = "ReplicatedStorage.Shared.Strings"
local CONTROLLER = "StarterPlayer.StarterPlayerScripts.Client.Controllers.ShopkeeperController"

local lobbyCache = nil
local function lobby(Loader)
	if lobbyCache == nil then
		lobbyCache = Loader.require(LOBBY).Build(1)
	end
	return lobbyCache
end

local function find(root, name, class)
	for _, inst in root:GetDescendants() do
		if inst.Name == name and (class == nil or inst:IsA(class)) then
			return inst
		end
	end
	return nil
end

local function npc(Loader)
	local info = lobby(Loader)
	return find(info.Model, Loader.require(SHOPKEEPER).NAME, "Model"), info
end

local function boothFrame(Loader)
	-- the booth's own frame, exactly as Lobby.buildShop computes it (z < 0 = towards the customers)
	local roblox = Loader.roblox
	local MapKit = Loader.require("ReplicatedStorage.Shared.Maps.MapKit")
	local L = Loader.require(LOBBY).Layout
	local a = math.rad(L.ShopAngle)
	return MapKit.Facing(roblox.Vector3.new(math.cos(a) * 52, 0, math.sin(a) * 52), roblox.Vector3.new(0, 0, 0))
end

local function limb(model, name)
	local part = model:FindFirstChild(name)
	return part
end

-- A camera CFrame at `from` looking at `at` (Lune's CFrame.lookAt is mirrored: build it from basis vectors).
local function looking(roblox, from, at)
	local look = (at - from).Unit
	local right = look:Cross(roblox.Vector3.new(0, 1, 0)).Unit
	return roblox.CFrame.fromMatrix(from, right, right:Cross(look), -look)
end

-- The controller's frame step on a fresh NPC (built at the origin, facing -Z) with stand-ins for the engine: a fake
-- workspace (a phone-sized camera with a real field of view + BulkMoveTo counting moves), a fake local character,
-- SoundController (counting "SansTextBlip") and UIController (the Shop screen open or not). body(C, h) runs the
-- test; everything is put back afterwards.
local function withRuntime(T, Loader, body)
	local C = Loader.require(CONTROLLER)
	local Shopkeeper = Loader.require(SHOPKEEPER)
	local Strings = Loader.require(STRINGS)
	local roblox = Loader.roblox
	local Vector3 = roblox.Vector3
	local G = getfenv(C.Step)
	local Players = G.game:GetService("Players")
	local oldWorkspace, oldPlayer, oldLang = rawget(G, "workspace"), rawget(Players, "LocalPlayer"), Strings.Language()
	local h = { moves = 0, blips = 0, shop = false }
	h.camera = { CFrame = roblox.CFrame.new(0, 8, -20), FieldOfView = 72, ViewportSize = roblox.Vector2.new(844, 390) }
	G.workspace = {
		CurrentCamera = h.camera,
		BulkMoveTo = function(_, parts, cframes)
			h.moves += 1
			for i, part in parts do
				part.CFrame = cframes[i]
			end
		end,
	}
	local function fakePart()
		return {
			Position = Vector3.zero,
			IsA = function(_, class)
				return class == "BasePart"
			end,
		}
	end
	local bodyPart, headPart = fakePart(), fakePart()
	function h.standAt(x, z)
		bodyPart.Position = Vector3.new(x, 3, z)
		headPart.Position = Vector3.new(x, 4.6, z)
	end
	function h.look(from, at)
		h.camera.CFrame = looking(roblox, from, at)
	end
	function h.run(seconds, dt, each)
		dt = dt or 1 / 60
		for _ = 1, math.floor(seconds / dt + 0.5) do
			if each then
				each()
			end
			C.Step(dt)
		end
	end
	local character = {
		FindFirstChild = function(_, name)
			return if name == "HumanoidRootPart" then bodyPart elseif name == "Head" then headPart else nil
		end,
	}
	rawset(Players, "LocalPlayer", { Name = "Kid", Character = character })
	Strings.SetLanguage("en")
	C._Harness({
		Sound = {
			Play = function(name)
				if name == "SansTextBlip" then
					h.blips += 1
				end
			end,
		},
		UI = {
			IsOpen = function(name)
				return name == "Shop" and h.shop
			end,
		},
	})
	local ok, err = pcall(function()
		local folder = roblox.Instance.new("Folder")
		h.model = Shopkeeper.Build(roblox.CFrame.new(0, 3.39, 0))
		h.model.Parent = folder
		local root = h.model.PrimaryPart
		T.ok(C.Attach(h.model), "attaches to the frozen NPC")
		h.gui = root:FindFirstChild("ShopkeeperBubbleAnchor"):FindFirstChild("ShopkeeperBubble")
		h.line = h.gui:FindFirstChild("Line", true)
		h.skull = h.model.Head:FindFirstChild("Cranium")
		h.rest = h.skull.CFrame
		body(C, h, Strings)
	end)
	C.Detach()
	C._Harness({})
	G.workspace = oldWorkspace
	rawset(Players, "LocalPlayer", oldPlayer)
	Strings.SetLanguage(oldLang)
	if not ok then
		error(err, 0)
	end
end

local function run(M, m, seconds, distance, dt)
	dt = dt or 0.05
	local events = {}
	local steps = math.floor(seconds / dt + 0.5)
	for _ = 1, steps do
		for _, e in M.Step(m, dt, distance) do
			table.insert(events, e)
		end
	end
	return events
end

return {
	shop_booth_npc_built_frozen = function(T, Loader)
		local model, info = npc(Loader)
		T.ok(model ~= nil, "Decor/ShopBooth has the ShopkeeperSans model")
		if model == nil then
			return
		end
		T.eq(model:GetAttribute("Shopkeeper"), true, "Shopkeeper attribute")
		T.eq(model:GetAttribute("BlueprintId"), "ClassicSans", "a Classic Sans rig")
		T.ok(
			model.Parent
				and model.Parent.Name == "ShopBooth"
				and model.Parent.Parent
				and model.Parent.Parent.Name == "Decor",
			"lives in Decor/ShopBooth"
		)
		T.eq(info.Model:GetAttribute("ShopkeeperError"), nil, "no build error recorded on the lobby")
		local parts, bad, shadows = 0, {}, 0
		for _, inst in model:GetDescendants() do
			if inst:IsA("BasePart") then
				parts += 1
				if not inst.Anchored or inst.CanCollide or inst.CanQuery or inst.CanTouch then
					table.insert(bad, inst.Name)
				end
				if inst.CastShadow then
					shadows += 1
				end
			end
			T.ok(not inst:IsA("Humanoid"), "no Humanoid: not a character, invisible to targeting")
			T.ok(not inst:IsA("JointInstance") and not inst:IsA("WeldConstraint"), "no joints (frozen): " .. inst.Name)
			T.ok(not inst:IsA("Light") and not inst:IsA("LuaSourceContainer"), "no lights / scripts: " .. inst.Name)
		end
		T.ok(parts > 100, "a full rig (" .. parts .. " parts)")
		T.eq(#bad, 0, "anchored ghost parts (no collide / query / touch): " .. table.concat(bad, ", "))
		-- the client moves ~130 of them several times a second: moving shadow casters would keep invalidating the
		-- lighting around the booth on phones
		T.eq(shadows, 0, "no part casts a shadow")
		T.eq(model:GetAttribute("PartCount"), parts, "PartCount attribute matches")
		T.ok(
			model.PrimaryPart ~= nil and model.PrimaryPart.Name == "HumanoidRootPart",
			"PrimaryPart = HumanoidRootPart"
		)
		-- not a round character: no Bots folder, no Humanoid anywhere in the map's decor
		T.ok(find(info.Model, "Bots") == nil, "the lobby has no Bots folder for him to join")
		-- the booth prompt still opens the Shop screen
		local marker = find(info.Model, "ShopBooth", "BasePart")
		T.ok(marker ~= nil and marker:GetAttribute("Action") == "Shop", "ShopBooth marker keeps Action = Shop")
		local prompt = marker and marker:FindFirstChildOfClass("ProximityPrompt")
		T.ok(prompt ~= nil and prompt:GetAttribute("Action") == "Shop", "the prompt is unchanged")
	end,

	shop_booth_npc_inside_booth_asleep_on_counter = function(T, Loader)
		local model, info = npc(Loader)
		if model == nil then
			T.ok(false, "no shopkeeper")
			return
		end
		local frame = boothFrame(Loader)
		local inv = frame:Inverse()
		local counterTop = find(info.Model, "CounterTop", "BasePart")
		T.ok(counterTop ~= nil, "booth counter top exists")
		local topY = (inv * counterTop.CFrame).Position.Y + counterTop.Size.Y / 2
		-- every visible part inside the booth footprint (floor 12 x 9 centred at z = 1.5), above the floor, under the awning
		local worst = nil
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part.Transparency < 1 then
				local p = inv * part.CFrame.Position
				local inside = math.abs(p.X) < 5.4 and p.Z > -2.75 and p.Z < 4.3 and p.Y > 0.5 and p.Y < 9
				if not inside then
					worst = part.Name .. " at " .. tostring(p)
				end
			end
		end
		T.eq(worst, nil, "all parts inside the booth, nothing poking out of the counter front")
		-- sits on the stool behind the counter body
		local root = inv * model.PrimaryPart.CFrame.Position
		T.ok(root.Z > -0.5, "seated behind the counter (root z " .. root.Z .. ")")
		local stool = find(info.Model, "StoolSeat", "BasePart")
		T.ok(stool ~= nil and math.abs((inv * stool.CFrame.Position - root).X) < 0.05, "on the stool")
		-- slumped: the torso leans well forward over the counter
		local torso = limb(model, "UpperTorso")
		local lean = math.deg(math.acos(math.clamp(torso.CFrame.UpVector.Y, -1, 1)))
		T.ok(lean > 45 and lean < 80, "torso slumped forward (" .. math.floor(lean) .. " deg)")
		T.ok(frame:VectorToObjectSpace(torso.CFrame.UpVector).Z < -0.6, "...towards the customers")
		-- crossed forearms lying flat on the counter top
		for _, side in { "Left", "Right" } do
			local fore = limb(model, side .. "LowerArm")
			local p = inv * fore.CFrame.Position
			local lift = p.Y - topY -- the forearm's centre: about half its thickness above the counter top
			T.ok(lift > 0.2 and lift < 0.55, side .. " forearm rests on the counter (" .. lift .. ")")
			T.ok(math.abs(fore.CFrame.UpVector.Y) < 0.25, side .. " forearm lies flat")
			T.ok(p.Z < -0.3 and p.Z > -3, side .. " forearm is over the counter top")
		end
		local l, r = inv * limb(model, "LeftHand").CFrame.Position, inv * limb(model, "RightHand").CFrame.Position
		T.ok(l.X > -0.4 and r.X < 0.4, "the hands reach across the middle: arms folded")
		-- skull low, resting on the arms, tipped sideways, eyes shut
		local head = limb(model, "Head")
		local h = inv * head.CFrame.Position
		T.ok(
			h.Y - topY < 2.2 and h.Y - topY > 1.2,
			"skull rests low on the arms (" .. (h.Y - topY) .. " above the counter)"
		)
		T.ok(h.Z < -0.3 and h.Z > -3, "skull above the counter top")
		local roll = math.deg(math.acos(math.clamp(head.CFrame.UpVector.Y, -1, 1)))
		T.ok(roll > 15 and roll < 60, "skull tipped onto the arms (" .. math.floor(roll) .. " deg)")
		local facing = frame:VectorToObjectSpace(head.CFrame.LookVector)
		T.ok(facing.Z < -0.5, "his (shut) eyes and grin face the customers")
		local Shopkeeper = Loader.require(SHOPKEEPER)
		for _, part in head:GetDescendants() do
			if part:IsA("BasePart") and table.find(Shopkeeper.EYES, part.Name) then
				T.eq(part.Transparency, 1, "pupils hidden while asleep")
			elseif part:IsA("BasePart") and table.find(Shopkeeper.LIDS, part.Name) then
				T.eq(part.Transparency, 0, "lids shown while asleep")
			end
		end
	end,

	shop_booth_fk_reproduces_and_awake_pose = function(T, Loader)
		local Shopkeeper = Loader.require(SHOPKEEPER)
		local model = npc(Loader)
		if model == nil then
			T.ok(false, "no shopkeeper")
			return
		end
		local joints = Shopkeeper.Joints(model)
		T.eq(#joints, 15, "15 joints stored on the limbs")
		T.eq(joints[1].Parent, "HumanoidRootPart", "parents first")
		local seen = { HumanoidRootPart = true }
		for _, j in joints do
			T.ok(seen[j.Parent], j.Limb .. " after its parent " .. j.Parent)
			seen[j.Limb] = true
		end
		local root = model.PrimaryPart.CFrame
		local scale = model:GetAttribute("RigScale")
		local sleep = Shopkeeper.Solve(root, joints, Shopkeeper.Transforms(Shopkeeper.SleepPose, scale))
		local worst = 0
		for _, j in joints do
			local part = model:FindFirstChild(j.Limb)
			worst = math.max(worst, (sleep[j.Limb].Position - part.CFrame.Position).Magnitude)
			worst = math.max(worst, (sleep[j.Limb].LookVector - part.CFrame.LookVector).Magnitude)
		end
		T.ok(worst < 1e-3, "Solve(SleepPose) reproduces the built limbs (err " .. worst .. ")")
		local awake = Shopkeeper.Solve(root, joints, Shopkeeper.Transforms(Shopkeeper.AwakePose, scale))
		T.ok(awake.Head.Position.Y > sleep.Head.Position.Y + 0.15, "awake: the skull lifts")
		T.ok(awake.Head.UpVector.Y > 0.95, "awake: the skull is upright")
		for _, side in { "Left", "Right" } do
			local dy = awake[side .. "LowerArm"].Position.Y - sleep[side .. "LowerArm"].Position.Y
			T.ok(math.abs(dy) < 0.12, side .. " forearm stays on the counter while he props up (" .. dy .. ")")
		end
		T.ok(awake.LeftUpperLeg.Position == sleep.LeftUpperLeg.Position, "legs do not move")
		-- gui anchors (root space) above the skull
		local zzz, bubble = model:GetAttribute("ZzzOffset"), model:GetAttribute("BubbleOffset")
		T.ok(typeof(zzz) == "Vector3" and typeof(bubble) == "Vector3", "ZzzOffset / BubbleOffset attributes")
		local headLocal = root:Inverse() * awake.Head.Position
		T.ok(bubble.Y > headLocal.Y + 1, "the speech bubble sits above the awake skull")
		T.ok(zzz.Y > (root:Inverse() * sleep.Head.Position).Y + 0.9, "the Zzz start above the sleeping skull")
		-- build options used by previews
		local roblox = Loader.roblox
		local awakeModel = Shopkeeper.Build(roblox.CFrame.new(0, 3, 0), { Pose = Shopkeeper.AwakePose, Awake = true })
		local pupils = 0
		for _, part in awakeModel:GetDescendants() do
			if part:IsA("BasePart") and table.find(Shopkeeper.EYES, part.Name) and part.Transparency == 0 then
				pupils += 1
			end
		end
		T.eq(pupils, 2, "Awake = true opens the eyes")
	end,

	shop_booth_controller_api = function(T, Loader)
		local C = Loader.require(CONTROLLER)
		T.eq(C.Priority, 62, "Priority")
		for _, name in { "Init", "Start", "State", "LookAngles", "Typing", "PoseRig", "Pose", "InView", "Search" } do
			T.eq(type(C[name]), "function", name)
		end
		T.eq(C.State(), nil, "no shopkeeper offline")
		T.eq(C.Tuning.LEAVE_TIME, 2, "bye after 2 s away")
		T.ok(C.Tuning.LEAVE_RADIUS >= C.Tuning.WAKE_RADIUS + 4, "hysteresis")
		-- he is awake before the booth's Shop prompt shows: the prompt appears MaxActivationDistance from its marker
		-- (in front of the counter), which can be farther from him than a 12-stud wake radius
		local model, info = npc(Loader)
		local marker = find(info.Model, "ShopBooth", "BasePart")
		local prompt = marker and marker:FindFirstChildOfClass("ProximityPrompt")
		T.ok(model ~= nil and prompt ~= nil, "shopkeeper and booth prompt")
		if model == nil or prompt == nil then
			return
		end
		local root = model.PrimaryPart.CFrame
		local m = root:Inverse() * marker.CFrame.Position
		local reach = 0
		for deg = -90, 90, 5 do -- player roots at the marker's height, in front of him, at the prompt's edge
			local a = math.rad(deg)
			local p = m + Loader.roblox.Vector3.new(math.sin(a), 0, -math.cos(a)) * prompt.MaxActivationDistance
			reach = math.max(reach, p.Magnitude)
		end
		T.ok(
			C.Tuning.WAKE_RADIUS >= reach,
			("wakes before the Shop prompt shows (wake %.1f, prompt reach %.1f studs)"):format(
				C.Tuning.WAKE_RADIUS,
				reach
			)
		)
		T.ok(C.Tuning.WAKE_RADIUS <= reach + 3, "...but only just (he is not woken from across the plaza)")
	end,

	shop_booth_controller_pose = function(T, Loader)
		-- the controller's runtime pose maths on the real lobby NPC (what it feeds to workspace:BulkMoveTo)
		local C = Loader.require(CONTROLLER)
		local model = npc(Loader)
		if model == nil then
			T.ok(false, "no shopkeeper")
			return
		end
		local pr = C.PoseRig(model)
		T.ok(pr ~= nil, "PoseRig reads the frozen model")
		if pr == nil then
			return
		end
		table.sort(pr.UpperBody)
		T.eq(
			table.concat(pr.UpperBody, ","),
			"Head,LeftHand,LeftLowerArm,LeftUpperArm,RightHand,RightLowerArm,RightUpperArm,UpperTorso",
			"only the upper body moves"
		)
		local asleep = C.Pose(pr, 0)
		local worst = 0
		for name, cf in asleep do
			local part = model:FindFirstChild(name)
			worst = math.max(
				worst,
				(cf.Position - part.CFrame.Position).Magnitude,
				(cf.LookVector - part.CFrame.LookVector).Magnitude
			)
		end
		T.ok(worst < 1e-3, "alpha 0 = the built sleep pose (err " .. worst .. ")")
		local function neckGap(limbs)
			local torsoNeck = (limbs.UpperTorso * pr.Neck.C0).Position
			local headNeck = (limbs.Head * pr.Neck.C1).Position
			return (torsoNeck - headNeck).Magnitude
		end
		for _, a in { 0, 0.3, 0.7, 1 } do
			for _, look in { { 0, 0 }, { 0.8, 0.3 }, { -1.1, -0.35 } } do
				T.ok(
					neckGap(C.Pose(pr, a, 0.02, look[1], look[2])) < 1e-3,
					"the skull stays on its neck (alpha " .. a .. ")"
				)
			end
		end
		local up = C.Pose(pr, 1)
		T.ok(up.Head.UpVector.Y > 0.95, "awake: upright skull")
		T.ok((up.Head.LookVector - pr.LookFrame.LookVector).Magnitude < 1e-4, "awake without look-at = the awake pose")
		local half = C.Pose(pr, 0.5)
		T.ok(
			half.Head.Position.Y > asleep.Head.Position.Y and half.Head.Position.Y < up.Head.Position.Y + 0.05,
			"halfway lift"
		)
		local turned = C.Pose(pr, 1, 0, math.rad(40), 0)
		local a1 = math.atan2(-pr.LookFrame.LookVector.X, -pr.LookFrame.LookVector.Z)
		local a2 = math.atan2(-turned.Head.LookVector.X, -turned.Head.LookVector.Z)
		T.near(math.deg(a2 - a1), 40, 1.5, "yaw turns the skull to his left")
		local breathing = C.Pose(pr, 0, math.rad(2))
		T.ok(
			(breathing.Head.LookVector - asleep.Head.LookVector).Magnitude < 1e-4,
			"asleep: the skull keeps resting while he breathes"
		)
		T.ok(
			(breathing.UpperTorso.UpVector - asleep.UpperTorso.UpVector).Magnitude > 0.02,
			"...and the torso rises and falls"
		)
		T.ok(
			breathing.LeftFoot.Position == asleep.LeftFoot.Position
				and up.RightFoot.Position == asleep.RightFoot.Position,
			"legs never move"
		)
	end,

	shop_booth_state_machine = function(T, Loader)
		local C = Loader.require(CONTROLLER)
		local M, tune = C.Machine, C.Tuning
		local m = M.new()
		T.eq(m.State, "Asleep", "starts asleep")
		T.eq(#run(M, m, 5, 30), 0, "a far player does not wake him")
		T.eq(#run(M, m, 5, nil), 0, "no character = far")
		T.eq(#run(M, m, 5, tune.WAKE_RADIUS + 0.5), 0, "just outside the wake radius: still asleep")
		T.eq(M.Alpha(m), 0, "sleep pose")
		local ev = run(M, m, 0.05, tune.WAKE_RADIUS - 1)
		T.eq(ev[1], "Wake", "comes near -> Wake")
		T.eq(m.State, "Waking", "Waking")
		ev = run(M, m, tune.WAKE_TIME + 0.05, 8)
		T.eq(ev[1], "Awake", "-> Awake after the lift")
		T.eq(M.Alpha(m), 1, "awake pose")
		T.eq(#run(M, m, 10, (tune.WAKE_RADIUS + tune.LEAVE_RADIUS) / 2), 0, "between the radii: stays awake")
		T.eq(#run(M, m, tune.LEAVE_TIME - 0.15, tune.LEAVE_RADIUS + 5), 0, "far, but not long enough")
		T.eq(#run(M, m, 0.5, tune.LEAVE_RADIUS - 2), 0, "steps back in: the far timer resets")
		T.eq(#run(M, m, tune.LEAVE_TIME - 0.15, tune.LEAVE_RADIUS + 5), 0, "far again (timer restarted)")
		ev = run(M, m, 0.3, tune.LEAVE_RADIUS + 5)
		T.eq(ev[1], "Bye", "far for LEAVE_TIME -> Bye")
		T.eq(m.State, "Bye", "Bye")
		ev = run(M, m, 0.05, 6)
		T.eq(ev[1], "Return", "comes back during the bye -> Return (no second greeting)")
		T.eq(m.State, "Awake", "awake again")
		ev = run(M, m, tune.LEAVE_TIME + 0.1, 40)
		T.eq(ev[1], "Bye", "leaves again -> Bye")
		ev = run(M, m, tune.BYE_TIME + 0.05, 40)
		T.eq(ev[1], "Doze", "-> dozes off after the bye line")
		T.ok(M.Alpha(m) < 1 and M.Alpha(m) > 0.5, "the skull starts sinking")
		local before = M.Alpha(m)
		run(M, m, 0.4, 40)
		T.ok(M.Alpha(m) < before, "...keeps sinking")
		ev = run(M, m, tune.DOZE_TIME, 40)
		T.eq(ev[1], "Asleep", "-> asleep again")
		T.eq(M.Alpha(m), 0, "back in the sleep pose")
		-- coming back while he dozes off wakes him with the greeting, without a pose jump
		local d = M.new()
		run(M, d, 0.05, 5)
		run(M, d, tune.WAKE_TIME + 0.1, 5)
		run(M, d, tune.LEAVE_TIME + 0.1, 40)
		run(M, d, tune.BYE_TIME + 0.05, 40)
		run(M, d, tune.DOZE_TIME * 0.5, 40)
		T.eq(d.State, "Dozing", "dozing")
		local mid = M.Alpha(d)
		ev = run(M, d, 0.05, 5)
		T.eq(ev[1], "Wake", "near while dozing -> Wake (greets again)")
		T.near(M.Alpha(d, true), mid, 0.05, "the pose continues from where it was")
	end,

	shop_booth_rush_past_and_overshoot = function(T, Loader)
		local C = Loader.require(CONTROLLER)
		local M, tune = C.Machine, C.Tuning
		-- a player who runs straight past: woken, then gone during the lift -> bye LEAVE_TIME after leaving
		local m = M.new()
		run(M, m, 0.05, 10)
		local events = run(M, m, tune.LEAVE_TIME + 0.15, 50)
		T.ok(table.find(events, "Awake") ~= nil, "finishes waking up")
		T.ok(table.find(events, "Bye") ~= nil, "says bye on time even though the player left mid-lift")
		-- the lift overshoots a little (anticipation/overshoot), never with Reduced Motion
		local w = M.new()
		run(M, w, 0.05, 5)
		local peak, peakReduced = 0, 0
		for _ = 1, 40 do
			M.Step(w, tune.WAKE_TIME / 40, 5)
			if w.State ~= "Waking" then
				break
			end
			peak = math.max(peak, M.Alpha(w))
			peakReduced = math.max(peakReduced, M.Alpha(w, true))
		end
		T.ok(peak > 1.01 and peak < 1.2, "small overshoot (" .. peak .. ")")
		T.ok(peakReduced <= 1, "no overshoot with Reduced Motion")
		-- unknown state recovers to Asleep
		local broken = { State = "???", Time = 0, Far = 0, From = 0 }
		M.Step(broken, 0.1, 50)
		T.eq(broken.State, "Asleep", "unknown state -> Asleep")
		-- NaN distance counts as far
		local n = M.new()
		T.eq(#M.Step(n, 0.1, 0 / 0), 0, "NaN distance does not wake him")
	end,

	shop_booth_look_and_typing = function(T, Loader)
		local C = Loader.require(CONTROLLER)
		local roblox = Loader.roblox
		local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
		local yaw, pitch = C.LookAngles(CFrame.new(), Vector3.new(0, 0, -10))
		T.near(yaw, 0, 1e-6, "straight ahead: no yaw")
		T.near(pitch, 0, 1e-6, "straight ahead: no pitch")
		yaw = C.LookAngles(CFrame.new(), Vector3.new(-10, 0, -10))
		T.near(yaw, math.rad(45), 1e-4, "+yaw = his left (-X)")
		yaw = C.LookAngles(CFrame.new(), Vector3.new(10, 0, -2))
		T.near(yaw, -C.Tuning.MAX_YAW, 1e-6, "far round to his right: yaw clamped")
		-- behind him he looks ahead: no skull whipping from one shoulder limit to the other as a player crosses
		-- behind his back (atan2 jumps from +180 to -180 deg there)
		local p
		yaw, p = C.LookAngles(CFrame.new(), Vector3.new(10, 0, 10))
		T.ok(yaw == 0 and p == 0, "behind him: looks ahead")
		local left = C.LookAngles(CFrame.new(), Vector3.new(-0.3, 0, 10))
		local right = C.LookAngles(CFrame.new(), Vector3.new(0.3, 0, 10))
		T.ok(left == 0 and right == 0, "crossing right behind him: no jump")
		local _, straightUp = C.LookAngles(CFrame.new(), Vector3.new(0, 10, 0))
		T.near(straightUp, C.Tuning.MAX_PITCH_UP, 1e-6, "straight above: looks up (not 'behind')")
		local _, up = C.LookAngles(CFrame.new(), Vector3.new(0, 50, -1))
		T.near(up, C.Tuning.MAX_PITCH_UP, 1e-6, "pitch up clamped")
		local _, down = C.LookAngles(CFrame.new(), Vector3.new(0, -50, -1))
		T.near(down, -C.Tuning.MAX_PITCH_DOWN, 1e-6, "pitch down clamped")
		local turned = CFrame.new(5, 2, 1) * CFrame.Angles(0, math.rad(90), 0)
		yaw = C.LookAngles(turned, turned * Vector3.new(0, 0, -4))
		T.near(yaw, 0, 1e-4, "measured in the neck frame")
		-- typing: monotonic, punctuation pauses, ends at the full line (en + ru graphemes)
		local line = "* zzz... oh. hi, kid."
		local last = 0
		for i = 0, 40 do
			local shown = C.Typing(line, i * 0.05)
			T.ok(shown >= last, "monotonic")
			last = shown
		end
		T.eq(C.Typing(line, 100), utf8.len(line), "fully typed")
		T.ok(C.Typing("abcdef", 0.1) > C.Typing("a.....", 0.1), "punctuation types slower")
		T.eq(C.Typing("привет", 100), 6, "Cyrillic counted per letter")
	end,

	shop_booth_guis = function(T, Loader)
		local C = Loader.require(CONTROLLER)
		local roblox = Loader.roblox
		local anchor = roblox.Instance.new("Attachment")
		local bubble = C.BuildBubble(anchor, "* zzz... oh. hi, kid. what do you want?")
		T.ok(bubble:IsA("BillboardGui") and bubble.Adornee == anchor, "bubble: a BillboardGui on the anchor")
		T.eq(bubble.LightInfluence, 0, "unlit")
		T.ok(bubble.AlwaysOnTop, "never hidden behind the booth posts")
		T.ok(bubble.MaxDistance > C.Tuning.LEAVE_RADIUS + 10, "still readable while the player walks off (bye)")
		T.near(bubble.SizeOffset.Y, 0.5, 1e-6, "sits above its anchor")
		local box = bubble:FindFirstChild("Box", true)
		T.ok(
			box ~= nil and box.BackgroundColor3 == roblox.Color3.new(0, 0, 0) and box.BackgroundTransparency == 0,
			"black box"
		)
		local stroke = box and box:FindFirstChildOfClass("UIStroke")
		T.ok(
			stroke ~= nil and stroke.Color == roblox.Color3.new(1, 1, 1) and stroke.Thickness >= 2,
			"white pixel border"
		)
		local line = box and box:FindFirstChild("Line")
		T.ok(line ~= nil and string.find(line.FontFace.Family, "PressStart2P", 1, true) ~= nil, "the pixel menu font")
		T.eq(line and line.Text, "* zzz... oh. hi, kid. what do you want?", "the line")
		T.eq(line and line.MaxVisibleGraphemes, -1, "shown in full")
		T.ok(line and line.TextWrapped, "wraps")
		local tail = 0
		for _, child in bubble:GetDescendants() do
			if string.sub(child.Name, 1, 4) == "Tail" then
				tail += 1
			end
		end
		T.ok(tail >= 6, "pixel tail")
		local hidden = C.BuildBubble(roblox.Instance.new("Attachment"))
		T.eq(hidden.Enabled, false, "an empty bubble starts hidden")
		local zzz = C.BuildZzz(anchor, 1.35)
		local letters = 0
		for _, child in zzz:GetChildren() do
			if child:IsA("TextLabel") and child.Text == "Z" then
				letters += 1
				T.ok(child.TextTransparency < 1, "letter visible mid-cycle")
				T.ok(string.find(child.FontFace.Family, "PressStart2P", 1, true) ~= nil, "pixel Z")
			end
		end
		T.eq(letters, 3, "three Zs")
		T.ok(zzz.AlwaysOnTop, "the Zzz show over the booth's low awning")
		T.ok(zzz.MaxDistance <= 120, "...but only near the booth")
	end,

	shop_booth_controller_runtime = function(T, Loader)
		-- the real frame step on a fresh NPC, with a fake workspace (camera + BulkMoveTo) and a fake local character
		local C = Loader.require(CONTROLLER)
		local Shopkeeper = Loader.require(SHOPKEEPER)
		local Strings = Loader.require(STRINGS)
		local roblox = Loader.roblox
		local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
		local G = getfenv(C.Step) -- the controller module's own environment (its `workspace` global)
		local Players = G.game:GetService("Players")
		local oldWorkspace, oldPlayer, oldLang =
			rawget(G, "workspace"), rawget(Players, "LocalPlayer"), Strings.Language()
		local camera = { CFrame = CFrame.new(0, 8, -20) }
		local moves = 0
		G.workspace = {
			CurrentCamera = camera,
			BulkMoveTo = function(_, parts, cframes)
				moves += 1
				for i, part in parts do
					part.CFrame = cframes[i]
				end
			end,
		}
		local function fakePart()
			return {
				Position = Vector3.zero,
				IsA = function(_, class)
					return class == "BasePart"
				end,
			}
		end
		local body, head = fakePart(), fakePart()
		local function standAt(x, z)
			body.Position = Vector3.new(x, 3, z)
			head.Position = Vector3.new(x, 4.6, z)
		end
		local character = {
			FindFirstChild = function(_, name)
				return if name == "HumanoidRootPart" then body elseif name == "Head" then head else nil
			end,
		}
		rawset(Players, "LocalPlayer", { Name = "Kid", Character = character })
		Strings.SetLanguage("en")
		local ok, err = pcall(function()
			local folder = roblox.Instance.new("Folder")
			local model = Shopkeeper.Build(CFrame.new(0, 3.39, 0))
			model.Parent = folder
			local root = model.PrimaryPart
			local skull = model.Head:FindFirstChild("Cranium")
			local pupil = model.Head:FindFirstChild("LeftPupil")
			local rest = skull.CFrame
			T.ok(C.Attach(model), "attaches to the frozen NPC")
			T.eq(C.State(), "Asleep", "asleep")
			local zzzGui = root:FindFirstChild("ShopkeeperZzzAnchor"):FindFirstChild("ShopkeeperZzz")
			local bubbleGui = root:FindFirstChild("ShopkeeperBubbleAnchor"):FindFirstChild("ShopkeeperBubble")
			local line = bubbleGui:FindFirstChild("Line", true)
			local function run(seconds, dt)
				for _ = 1, math.floor(seconds / dt + 0.5) do
					C.Step(dt)
				end
			end
			-- far player, camera nearby: asleep, breathing, Zzz
			standAt(0, -40)
			run(2, 0.1)
			T.eq(C.State(), "Asleep", "a far player does not wake him")
			T.ok(moves > 0 and moves <= 31, "breathes at ~15 Hz (" .. moves .. " moves in 2 s)")
			T.ok(zzzGui.Enabled, "Zzz shown")
			T.ok(not bubbleGui.Enabled, "no bubble")
			T.eq(pupil.Transparency, 1, "eyes shut")
			-- comes near: wakes, eyes open, greets letter by letter
			standAt(0, -8)
			run(0.05, 0.05)
			T.eq(C.State(), "Waking", "wakes up")
			run(0.25, 0.05)
			T.eq(pupil.Transparency, 0, "eyes open")
			T.eq(line.Text, "* " .. Strings.L("shop.keeper.greet"), "greets with shop.keeper.greet")
			T.ok(line.MaxVisibleGraphemes > 0 and line.MaxVisibleGraphemes < utf8.len(line.Text), "typing")
			T.ok(bubbleGui.Enabled, "bubble up")
			run(1, 0.05)
			T.eq(C.State(), "Awake", "awake")
			T.ok(skull.CFrame.Position.Y > rest.Position.Y + 0.15, "the skull lifted off his arms")
			local function facing()
				local to = (head.Position - skull.CFrame.Position).Unit
				return skull.CFrame.LookVector:Dot(to)
			end
			T.ok(facing() > 0.85, "looks at the player (" .. facing() .. ")")
			run(3, 0.05)
			T.eq(line.MaxVisibleGraphemes, -1, "the whole greeting is shown")
			standAt(-9, -6)
			run(1.5, 0.05)
			T.ok(facing() > 0.85, "turns to follow the player (" .. facing() .. ")")
			-- walks away: bye, then back to sleep
			standAt(0, -30)
			run(2.2, 0.05)
			T.eq(C.State(), "Bye", "bye after 2 s away")
			T.eq(line.Text, "* " .. Strings.L("shop.keeper.bye"), "says shop.keeper.bye")
			run(5, 0.05)
			T.eq(C.State(), "Asleep", "dozed off again")
			T.eq(pupil.Transparency, 1, "eyes shut again")
			T.ok((skull.CFrame.Position - rest.Position).Magnitude < 0.1, "the skull back on his arms")
			-- everyone far away: snaps to the exact built pose, guis off, no more moves
			standAt(0, -300)
			camera.CFrame = CFrame.new(0, 8, -300)
			C.Step(0.1)
			T.ok((skull.CFrame.Position - rest.Position).Magnitude < 1e-4, "idle: exactly the built pose")
			T.ok(not zzzGui.Enabled and not bubbleGui.Enabled, "idle: guis off")
			local idleMoves = moves
			run(1, 0.1)
			T.eq(moves, idleMoves, "idle: nothing moves")
			C.Detach()
			T.eq(C.State(), nil, "detached")
			T.eq(root:FindFirstChild("ShopkeeperZzzAnchor"), nil, "its guis are gone")
		end)
		C.Detach()
		G.workspace = oldWorkspace
		rawset(Players, "LocalPlayer", oldPlayer)
		Strings.SetLanguage(oldLang)
		if not ok then
			error(err, 0)
		end
	end,

	shop_booth_in_view = function(T, Loader)
		local C = Loader.require(CONTROLLER)
		local roblox = Loader.roblox
		local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
		local cam = CFrame.new()
		local wide = 16 / 9
		T.ok(C.InView(cam, 70, wide, Vector3.new(0, 0, -10), 0), "straight ahead")
		T.ok(not C.InView(cam, 70, wide, Vector3.new(0, 0, 10), 1), "behind the camera")
		T.ok(C.InView(cam, 70, wide, Vector3.new(0, 0, 0.5), 1), "a sphere around the camera")
		-- 16:9 at 70 deg vertical sees ~51 deg to each side
		local side = Vector3.new(math.tan(math.rad(60)) * 10, 0, -10)
		T.ok(not C.InView(cam, 70, wide, side, 0), "60 deg to the side: out of view")
		T.ok(C.InView(cam, 70, wide, side, 5), "...but a big enough sphere pokes in")
		local phoneSide = Vector3.new(-math.tan(math.rad(55)) * 10, 0, -10)
		T.ok(not C.InView(cam, 70, wide, phoneSide, 0), "55 deg to the side: out of a 16:9 view")
		T.ok(C.InView(cam, 70, 844 / 390, phoneSide, 0), "...inside a wide phone's")
		T.ok(not C.InView(cam, 70, wide, Vector3.new(0, math.tan(math.rad(40)) * 10, -10), 0), "40 deg up: above it")
		local turned = looking(roblox, Vector3.new(5, 2, 5), Vector3.new(5, 2, 30))
		T.ok(C.InView(turned, 70, wide, Vector3.new(5, 2, 20), 0), "in the camera's own frame")
		T.ok(not C.InView(turned, 70, wide, Vector3.new(5, 2, -10), 0), "...behind it")
	end,

	shop_booth_runtime_offscreen = function(T, Loader)
		-- he is only posed while the camera can see him: not from the title screen's camera (37 studs away, 78 deg
		-- past him), not behind the walking player's camera, not behind the opaque Shop screen
		withRuntime(T, Loader, function(C, h)
			local V = Loader.roblox.Vector3.new
			local npcPos = h.model.PrimaryPart.CFrame.Position
			h.standAt(0, -60)
			local from = V(0, 12, -37)
			h.look(from, from + V(math.sin(math.rad(78)), -0.1, math.cos(math.rad(78))))
			h.run(2)
			T.eq(C.State(), "Asleep", "asleep")
			T.eq(h.moves, 0, "title-screen camera looking past him: no part moves")
			h.look(from, npcPos)
			h.run(1 / 60)
			T.eq(h.moves, 1, "the camera turns to him: his current pose is applied at once")
			h.run(1)
			T.ok(h.moves >= 11 and h.moves <= 17, "...then he breathes at ~15 Hz (" .. h.moves .. " moves)")
			h.look(V(0, 8, -20), V(0, 8, -40))
			local before = h.moves
			h.run(1)
			T.eq(h.moves, before, "behind the camera: no moves")
			-- the Shop screen is open (full screen) while he wakes up: nothing moves, nothing is said
			h.look(V(0, 8, -20), npcPos)
			h.shop = true
			h.standAt(0, -8)
			before = h.moves
			h.run(2)
			T.eq(C.State(), "Awake", "awake behind the Shop screen")
			T.eq(h.moves, before, "...but not posed while the Shop screen hides him")
			T.eq(h.blips, 0, "...and no greeting blips behind it")
			T.ok(not h.gui.Enabled, "...nor a bubble")
			h.shop = false
			h.run(1 / 60)
			T.eq(h.moves, before + 1, "the Shop closes: posed at once")
			T.ok(h.skull.CFrame.Position.Y > h.rest.Position.Y + 0.15, "...awake, the skull lifted")
			-- awake, the player standing still: ~30 Hz once the skull has settled on him
			h.run(1)
			before = h.moves
			h.run(1)
			local hz = h.moves - before
			T.ok(hz >= 25 and hz <= 32, "settled on the player: ~30 Hz (" .. hz .. ")")
		end)
	end,

	shop_booth_runtime_bubble = function(T, Loader)
		-- his 2D text blips (and the bye line) only come with a bubble the player can see; a Shop screen opened
		-- over the greeting takes it away for good
		withRuntime(T, Loader, function(C, h, Strings)
			local V = Loader.roblox.Vector3.new
			local npcPos = h.model.PrimaryPart.CFrame.Position
			local greet = "* " .. Strings.L("shop.keeper.greet")
			local bye = "* " .. Strings.L("shop.keeper.bye")
			local z = -22
			h.standAt(0, z)
			h.look(V(0, 8, z - 11), npcPos)
			h.run(0.2)
			h.run(1.2, nil, function() -- walks up to the counter, the camera behind him on the booth
				z = math.min(-6, z + 17 / 60)
				h.standAt(0, z)
				h.look(V(0, 8, z - 11), npcPos)
			end)
			h.run(3)
			T.eq(h.line.Text, greet, "greeted")
			T.ok(h.blips >= 8, "with blips: the bubble is on screen (" .. h.blips .. ")")
			-- the Shop opens while the greeting is still up, then closes again
			h.shop = true
			h.run(1)
			h.shop = false
			h.run(0.5)
			T.ok(not h.gui.Enabled, "the greeting does not come back after the Shop closes")
			-- turns round and walks back to the plaza: the booth is behind the camera
			local blips, sawBye = h.blips, false
			h.run(5, nil, function()
				z -= 17 / 60
				h.standAt(0, z)
				local camZ = math.min(z + 11, -3)
				h.look(V(0, 8, camZ), V(0, 6, camZ - 20))
				sawBye = sawBye or C.State() == "Bye"
			end)
			T.ok(sawBye, "he still goes through bye")
			T.eq(h.blips, blips, "no blips from a bubble behind the camera")
			T.ok(h.line.Text ~= bye, "no bye line typed where nobody can see it")
			T.ok(not h.gui.Enabled, "no bubble left up")
			h.run(4)
			T.eq(C.State(), "Asleep", "dozed off quietly")
			-- coming back, then backing away with the camera on him: the bye line is said, with blips
			z = -8
			h.standAt(0, z)
			h.look(V(0, 8, z - 11), npcPos)
			h.run(4)
			blips = h.blips
			h.run(5, nil, function()
				z -= 8 / 60
				h.standAt(0, z)
				h.look(V(0, 8, z - 11), npcPos)
			end)
			T.eq(h.line.Text, bye, "backing away in view: says bye")
			T.ok(h.blips > blips, "...with blips (" .. (h.blips - blips) .. ")")
			h.run(6)
			T.eq(C.State(), "Asleep", "asleep again")
			-- backs up to the counter looking at the plaza: the greeting types silently until he turns round
			z = -8
			h.standAt(0, z)
			h.look(V(0, 8, z + 4), V(0, 6, z - 20))
			blips = h.blips
			h.run(0.8)
			T.eq(h.line.Text, greet, "greets a player who backed up to the counter")
			T.eq(h.blips, blips, "no blips while the bubble is behind the camera")
			h.look(V(0, 8, z - 11), npcPos)
			h.run(2)
			T.ok(h.blips > blips, "the rest of the line blips once it is on screen")
		end)
	end,

	shop_booth_runtime_customers_only = function(T, Loader)
		-- a player behind the booth (behind its back shelf) or beside / behind him does not wake him up
		withRuntime(T, Loader, function(C, h)
			local V = Loader.roblox.Vector3.new
			h.look(V(0, 10, 20), h.model.PrimaryPart.CFrame.Position)
			h.standAt(0, 8)
			h.run(2)
			T.eq(C.State(), "Asleep", "a player behind the booth does not wake him")
			h.standAt(-6, 2)
			h.run(1)
			T.eq(C.State(), "Asleep", "...nor one beside and behind him")
			h.standAt(0, -8)
			h.run(0.1)
			T.eq(C.State(), "Waking", "a customer in front of him does")
		end)
	end,

	shop_booth_search_gives_up = function(T, Loader)
		-- no usable shopkeeper in the lobby (TestArena fallback, a rig it cannot read): the lobby is searched once,
		-- not rescanned for the whole session; a lobby whose shopkeeper failed to build is not searched at all
		local C = Loader.require(CONTROLLER)
		C.Tuning.SEARCH_TRIES, C.Tuning.SEARCH_INTERVAL = 3, 0
		local function fakeLobby(err)
			local lobby = { Parent = {}, Scans = 0 }
			function lobby.GetAttribute(_, name)
				return if name == "ShopkeeperError" then err else nil
			end
			function lobby.GetDescendants(self)
				self.Scans += 1
				return {}
			end
			return lobby
		end
		local empty = fakeLobby(nil)
		C.Search(empty)
		task.wait(0.1)
		T.eq(empty.Scans, 3, "searched SEARCH_TRIES times")
		C.Search(empty)
		task.wait(0.1)
		T.eq(empty.Scans, 3, "searched in vain: not searched again")
		C.Search(empty, true)
		task.wait(0.1)
		T.eq(empty.Scans, 6, "...unless fresh (a new LobbyController.Ready)")
		local broken = fakeLobby("Build failed")
		C.Search(broken)
		task.wait(0.1)
		T.eq(broken.Scans, 0, "ShopkeeperError on the lobby: nothing to search for")
		-- a lobby with a shopkeeper: found and attached
		local roblox = Loader.roblox
		local lobby = roblox.Instance.new("Model")
		lobby.Parent = roblox.Instance.new("Folder")
		Loader.require(SHOPKEEPER).Build(roblox.CFrame.new(0, 3.39, 0)).Parent = lobby
		C.Search(lobby)
		task.wait(0.05)
		T.eq(C.State(), "Asleep", "attached to the lobby's shopkeeper")
		C.Detach()
	end,

	shop_booth_strings = function(T, Loader)
		local Strings = Loader.require(STRINGS)
		local before = Strings.Language()
		for _, lang in { "en", "ru" } do
			Strings.SetLanguage(lang)
			for _, key in { "shop.keeper.greet", "shop.keeper.bye" } do
				T.ok(Strings.Has(key), key .. " registered")
				local text = Strings.L(key)
				T.ok(type(text) == "string" and #text > 3 and text ~= key, key .. " (" .. lang .. ")")
			end
		end
		Strings.SetLanguage("en")
		T.ok(string.find(Strings.L("shop.keeper.greet"), "zzz", 1, true) ~= nil, "the greeting starts sleepy")
		Strings.SetLanguage(before)
	end,
}
