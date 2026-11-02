--!nocheck
-- Lobby ShopBooth shopkeeper ("sleepy Sans", Shared/Maps/Shopkeeper + Client/Controllers/ShopkeeperController):
-- the lobby builds with the NPC (named, frozen ghost parts, inside the booth, behind the counter, asleep on it),
-- the pure forward kinematics reproduce the built pose and give a sensible awake pose, the controller's pure state
-- machine (asleep -> awake -> bye -> asleep, by distance and timers), look-at clamps, typing, and the strings.
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
		local parts, bad = 0, {}
		for _, inst in model:GetDescendants() do
			if inst:IsA("BasePart") then
				parts += 1
				if not inst.Anchored or inst.CanCollide or inst.CanQuery or inst.CanTouch then
					table.insert(bad, inst.Name)
				end
			end
			T.ok(not inst:IsA("Humanoid"), "no Humanoid: not a character, invisible to targeting")
			T.ok(not inst:IsA("JointInstance") and not inst:IsA("WeldConstraint"), "no joints (frozen): " .. inst.Name)
			T.ok(not inst:IsA("Light") and not inst:IsA("LuaSourceContainer"), "no lights / scripts: " .. inst.Name)
		end
		T.ok(parts > 100, "a full rig (" .. parts .. " parts)")
		T.eq(#bad, 0, "anchored ghost parts (no collide / query / touch): " .. table.concat(bad, ", "))
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
		for _, name in { "Init", "Start", "State", "LookAngles", "Typing", "PoseRig", "Pose" } do
			T.eq(type(C[name]), "function", name)
		end
		T.eq(C.State(), nil, "no shopkeeper offline")
		T.eq(C.Tuning.WAKE_RADIUS, 12, "wakes within ~12 studs")
		T.eq(C.Tuning.LEAVE_RADIUS, 18, "bye beyond ~18 studs...")
		T.eq(C.Tuning.LEAVE_TIME, 2, "...for 2 s")
		T.ok(C.Tuning.LEAVE_RADIUS > C.Tuning.WAKE_RADIUS, "hysteresis")
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
		yaw = C.LookAngles(CFrame.new(), Vector3.new(10, 0, 10))
		T.near(yaw, -C.Tuning.MAX_YAW, 1e-6, "behind him: yaw clamped")
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
