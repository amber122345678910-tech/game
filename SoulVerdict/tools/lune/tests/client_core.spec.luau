--!nocheck
-- Client core (InputController, CameraController math, VFX/CameraShake, Shared/Audio, Strings/Controls):
-- pure logic only (no engine services run under Lune). Also checks that every client-core controller requires
-- cleanly offline and exposes the SPEC §20 API with the right Priority.
local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
local INPUT = CLIENT .. "Controllers.InputController"
local CAMERA = CLIENT .. "Controllers.CameraController"
local SHAKE = CLIENT .. "VFX.CameraShake"
local AUDIO = "ReplicatedStorage.Shared.Audio"
local STRINGS = "ReplicatedStorage.Shared.Strings"
local CONTROLS = "ReplicatedStorage.Shared.Strings.Controls"
local REGISTRY = "ReplicatedStorage.Shared.Maps.Registry"
local THEMES = CLIENT .. "UI.Themes"

local BUILTIN_SOUNDS = {
	["rbxasset://sounds/action_falling.ogg"] = true,
	["rbxasset://sounds/action_footsteps_plastic.mp3"] = true,
	["rbxasset://sounds/action_get_up.mp3"] = true,
	["rbxasset://sounds/action_jump.mp3"] = true,
	["rbxasset://sounds/action_jump_land.mp3"] = true,
	["rbxasset://sounds/action_swim.mp3"] = true,
	["rbxasset://sounds/impact_water.mp3"] = true,
	["rbxasset://sounds/uuhhh.mp3"] = true,
}

local MOUSE_TOKENS = { MouseButton1 = true, MouseButton2 = true, MouseButton3 = true }

local function quiet(Loader, fn)
	local before = Loader.quietWarnings
	Loader.quietWarnings = true
	local ok, err = pcall(fn)
	Loader.quietWarnings = before
	if not ok then
		error(err, 0)
	end
end

local function isKeyCode(Loader, token)
	local ok, item = pcall(function()
		return Loader.roblox.Enum.KeyCode[token]
	end)
	return ok and item ~= nil
end

return {
	------------------------------------------------------------------------------------------------- input
	input_bindings_complete = function(T, Loader)
		local Input = Loader.require(INPUT)
		local kb = Input.Bindings.KeyboardMouse
		for _, action in Input.Actions do
			T.ok(kb[action] ~= nil and #kb[action] > 0, "keyboard binding for " .. action)
		end
		local slots = {
			Monster = { "M1", "Q", "E", "R", "T", "F", "G", "Shift" },
			Human = { "M1", "Q", "E", "R", "F", "Shift" },
		}
		for layout, needed in slots do
			local pad = Input.Bindings.Gamepad[layout]
			T.ok(pad ~= nil, "gamepad layout " .. layout)
			for _, action in needed do
				T.ok(pad[action] ~= nil and #pad[action] > 0, ("gamepad %s binding for %s"):format(layout, action))
			end
			for _, action in { "Jump", "Menu", "Emote", "CameraLock", "Back", "Confirm", "Prev", "Next" } do
				T.ok(pad[action] ~= nil and #pad[action] > 0, ("gamepad %s binding for %s"):format(layout, action))
			end
		end
		-- the ult chord sits on the role's ult slot
		T.eq(Input.Bindings.Gamepad.Monster.G[1], Input.CHORD, "monster ult = chord")
		T.eq(Input.Bindings.Gamepad.Human.R[1], Input.CHORD, "human ult = chord")
		T.eq(Input.UltAction("Monster"), "G", "monster ult action")
		T.eq(Input.UltAction("Humans"), "R", "human ult action")
		T.eq(Input.UltAction(nil), "R", "default ult action")
		T.eq(Input.LayoutForTeam("Monster"), "Monster")
		T.eq(Input.LayoutForTeam("Lobby"), "Human")
	end,

	input_tokens_are_real_keys = function(T, Loader)
		local Input = Loader.require(INPUT)
		local function check(map, label)
			for action, tokens in map do
				for _, token in tokens do
					local valid = token == Input.CHORD or MOUSE_TOKENS[token] or isKeyCode(Loader, token)
					T.ok(valid, ("%s %s: %s is a KeyCode/mouse token"):format(label, action, tostring(token)))
				end
			end
		end
		check(Input.Bindings.KeyboardMouse, "keyboard")
		check(Input.Bindings.Gamepad.Monster, "pad/monster")
		check(Input.Bindings.Gamepad.Human, "pad/human")
		for token in Input.Passthrough do
			T.ok(isKeyCode(Loader, token), "passthrough key " .. token)
		end
	end,

	input_no_combat_conflicts = function(T, Loader)
		local Input = Loader.require(INPUT)
		local function check(map, label)
			local owner = {}
			for action, tokens in map do
				if Input.CombatActions[action] and not Input.HintOnly[action] then
					for _, token in tokens do
						local other = owner[token]
						T.ok(other == nil, ("%s: %s bound to both %s and %s"):format(label, token, tostring(other), action))
						owner[token] = action
					end
				end
			end
		end
		check(Input.Bindings.KeyboardMouse, "keyboard")
		check(Input.Bindings.Gamepad.Monster, "pad/monster")
		check(Input.Bindings.Gamepad.Human, "pad/human")
		-- revive prompt keys (CharacterService: G / DPadRight) must not trigger human combat on the pad
		local human = Input.ActionsForKey("Gamepad", "Human", "DPadRight")
		for _, action in human do
			T.ok(not Input.CombatActions[action], "DPadRight stays free for the revive prompt: " .. action)
		end
	end,

	input_reverse_lookup = function(T, Loader)
		local Input = Loader.require(INPUT)
		local function has(list, action)
			return table.find(list, action) ~= nil
		end
		T.ok(has(Input.ActionsForKey("KeyboardMouse", nil, "MouseButton1"), "M1"), "LMB -> M1")
		T.ok(has(Input.ActionsForKey("KeyboardMouse", nil, "Q"), "Q"), "Q -> Q")
		T.ok(has(Input.ActionsForKey("KeyboardMouse", nil, "Q"), "Prev"), "Q -> Prev (spectate)")
		T.ok(has(Input.ActionsForKey("KeyboardMouse", nil, "LeftShift"), "Shift"), "LeftShift -> Shift")
		T.ok(has(Input.ActionsForKey("KeyboardMouse", nil, "Space"), "Jump"), "Space -> Jump")
		-- Tab is intentionally NOT bound (it also toggles the Roblox player list); M opens the menu
		T.ok(not has(Input.ActionsForKey("KeyboardMouse", nil, "Tab"), "Menu"), "Tab must not open Menu")
		T.ok(has(Input.ActionsForKey("KeyboardMouse", nil, "M"), "Menu"), "M -> Menu")
		T.ok(has(Input.ActionsForKey("KeyboardMouse", nil, "LeftControl"), "CameraLock"), "Ctrl -> CameraLock")
		T.ok(not has(Input.ActionsForKey("KeyboardMouse", nil, "G"), "Interact"), "Interact is hint-only")
		T.ok(has(Input.ActionsForKey("Gamepad", "Monster", "ButtonB"), "R"), "monster B -> R")
		T.ok(has(Input.ActionsForKey("Gamepad", "Human", "ButtonB"), "Shift"), "human B -> dash")
		T.ok(has(Input.ActionsForKey("Gamepad", "Human", "ButtonB"), "Back"), "B -> Back")
		T.ok(has(Input.ActionsForKey("Gamepad", "Monster", "ButtonL1"), "F"), "LB -> F")
		T.ok(has(Input.ActionsForKey("Gamepad", "Human", "ButtonR3"), "CameraLock"), "RS -> CameraLock")
		T.eq(#Input.ActionsForKey("Touch", nil, "Q"), 0, "touch has no key bindings")
		T.eq(#Input.ActionsForKey("KeyboardMouse", nil, "F13"), 0, "unbound key")
		-- rebinding rebuilds the reverse map
		Input.SetBinding("KeyboardMouse", nil, "Emote", { "V" })
		T.ok(has(Input.ActionsForKey("KeyboardMouse", nil, "V"), "Emote"), "rebound V -> Emote")
		T.ok(not has(Input.ActionsForKey("KeyboardMouse", nil, "B"), "Emote"), "old key unbound")
		Input.SetBinding("KeyboardMouse", nil, "Emote", { "B" })
	end,

	input_contexts_suppress_combat = function(T, Loader)
		local Input = Loader.require(INPUT)
		T.ok(Input.IsSuppressedBy("Q", { Menu = 1 }), "Menu suppresses Q")
		T.ok(Input.IsSuppressedBy("M1", { Box = 1 }), "Box suppresses M1")
		T.ok(Input.IsSuppressedBy("Shift", { Dead = 2 }), "Dead suppresses Shift")
		T.ok(not Input.IsSuppressedBy("Menu", { Menu = 1 }), "Menu action never suppressed")
		T.ok(not Input.IsSuppressedBy("Next", { Dead = 1 }), "spectate cycling works while dead")
		T.ok(not Input.IsSuppressedBy("Q", { Hud = 1 }), "non-suppressing context")
		T.ok(not Input.IsSuppressedBy("Q", {}), "no context")
		-- runtime stack (no engine needed)
		T.ok(Input.CombatEnabled(), "combat enabled by default")
		Input.PushContext("Menu")
		Input.PushContext("Menu")
		T.ok(not Input.CombatEnabled(), "Menu pushed")
		Input.PopContext("Menu")
		T.ok(not Input.CombatEnabled(), "still one Menu push")
		Input.PopContext("Menu")
		T.ok(Input.CombatEnabled(), "popped")
		Input.PopContext("Menu") -- extra pop is harmless
		T.ok(Input.CombatEnabled(), "extra pop ignored")
	end,

	input_simulated_actions = function(T, Loader)
		local Input = Loader.require(INPUT)
		local log = {}
		Input.Action:Connect(function(action, state)
			table.insert(log, action .. ":" .. state)
		end)
		Input.Simulate("Q", "Begin")
		Input.Simulate("Q", "Begin") -- same source: no second Begin
		T.ok(Input.IsDown("Q"), "Q held")
		Input.Simulate("Q", "End")
		T.ok(not Input.IsDown("Q"), "Q released")
		Input.PushContext("Box")
		Input.Simulate("E", "Begin")
		T.ok(not Input.IsDown("E"), "suppressed while boxed")
		Input.Simulate("Next", "Begin")
		T.ok(Input.IsDown("Next"), "non-combat action passes")
		Input.Simulate("Next", "End")
		Input.PopContext("Box")
		-- holding a combat action, then a suppressing context releases it
		Input.Simulate("F", "Begin")
		Input.PushContext("Dead")
		T.ok(not Input.IsDown("F"), "context push released F")
		Input.PopContext("Dead")
		local joined = table.concat(log, ",")
		T.ok(string.find(joined, "Q:Begin,Q:End", 1, true) ~= nil, "Q begin/end once: " .. joined)
		T.ok(string.find(joined, "F:Begin,F:End", 1, true) ~= nil, "F released by context: " .. joined)
		T.ok(string.find(joined, "E:", 1, true) == nil, "E never fired: " .. joined)
	end,

	------------------------------------------------------------------------------------------------ camera
	camera_pitch_and_rotation = function(T, Loader)
		local Camera = Loader.require(CAMERA)
		local M = Camera.Math
		local lo, hi = math.rad(-70), math.rad(65)
		T.eq(M.ClampPitch(math.rad(80), lo, hi), hi, "clamped up")
		T.eq(M.ClampPitch(math.rad(-90), lo, hi), lo, "clamped down")
		T.near(M.ClampPitch(0.3, lo, hi), 0.3, 1e-9, "inside")
		T.eq(M.ClampPitch(0 / 0, lo, hi), 0, "NaN -> 0")
		T.near(Camera.Tuning.PitchMin, lo, 1e-9, "tuning reads Config.Camera.PitchMin")
		for _, case in { { 0, 0 }, { 0.7, 0.2 }, { -2.5, -0.9 }, { 3.0, 1.0 } } do
			local yaw, pitch = case[1], case[2]
			local look = M.Rotation(yaw, pitch).LookVector
			local y2, p2 = M.YawPitch(look)
			T.near(y2, yaw, 1e-4, "yaw round trip")
			T.near(p2, pitch, 1e-4, "pitch round trip")
		end
		local look0 = M.Rotation(0, 0).LookVector
		T.near(look0.Z, -1, 1e-6, "yaw 0 looks along -Z")
		local up = M.Rotation(0, 0.5).LookVector
		T.ok(up.Y > 0, "positive pitch looks up")
		local left = M.Rotation(math.pi / 2, 0).LookVector
		T.near(left.X, -1, 1e-6, "positive yaw turns left (-X)")
		-- Lune-safe look-at
		local from = Loader.roblox.Vector3.new(3, 4, 5)
		local to = Loader.roblox.Vector3.new(-7, 1, 12)
		local cf = M.LookAt(from, to)
		local dir = (to - from).Unit
		T.near(cf.LookVector:Dot(dir), 1, 1e-4, "LookAt faces the target")
		T.near((cf.Position - from).Magnitude, 0, 1e-6, "LookAt keeps the position")
		T.near(cf.RightVector.Y, 0, 1e-6, "no roll")
	end,

	camera_collision_math = function(T, Loader)
		local M = Loader.require(CAMERA).Math
		T.eq(M.CollisionTarget(11, nil, 0.12, 0.5), 11, "free -> desired")
		T.near(M.CollisionTarget(11, 6, 0.12, 0.5), 5.88, 1e-9, "hit minus padding")
		T.eq(M.CollisionTarget(11, 0.2, 0.12, 0.5), 0.5, "never closer than the minimum")
		T.eq(M.CollisionTarget(11, 30, 0.12, 0.5), 11, "hit beyond desired is ignored")
		T.eq(M.CollisionTarget(0.3, 0.1, 0.12, 0.5), 0.3, "min clamps to desired when desired is tiny")
		-- pull-in: smooth but never more than maxLag behind the obstruction
		local tuning = Loader.require(CAMERA).Tuning
		local pullRate, easeRate, lag = tuning.PullInRate, tuning.EaseOutRate, tuning.MaxPullLag
		local d = M.SmoothCollision(11, 4, 1 / 60, pullRate, easeRate, lag)
		T.ok(d <= 4 + lag + 1e-9 and d >= 4, "pull-in bounded by the lag: " .. d)
		local small = M.SmoothCollision(5, 4.9, 1 / 60, pullRate, easeRate, lag)
		T.ok(small < 5 and small > 4.9, "small pull-in is smooth: " .. small)
		-- ease-out: slow, monotonic, converges
		local cur, prev = 4, 4
		for _ = 1, 30 do
			cur = M.SmoothCollision(cur, 11, 1 / 60, pullRate, easeRate, lag)
			T.ok(cur >= prev and cur <= 11, "monotonic ease-out")
			prev = cur
		end
		T.ok(cur < 9, "ease-out is slow (0.5 s -> still short of the target): " .. cur)
		for _ = 1, 600 do
			cur = M.SmoothCollision(cur, 11, 1 / 60, pullRate, easeRate, lag)
		end
		T.near(cur, 11, 1e-3, "ease-out converges")
		-- the pull-in is much faster than the ease-out
		local pulled = M.SmoothCollision(8, 4, 0.1, pullRate, easeRate, 10)
		local released = M.SmoothCollision(4, 8, 0.1, pullRate, easeRate, 10)
		T.ok((8 - pulled) > 3 * (released - 4), "pull-in faster than ease-out")
		-- character fade
		T.eq(M.FadeAlpha(5, 2.6, 1.1), 0, "far -> visible")
		T.eq(M.FadeAlpha(0.5, 2.6, 1.1), 1, "inside -> hidden")
		T.near(M.FadeAlpha(1.85, 2.6, 1.1), 0.5, 1e-9, "half way")
	end,

	camera_stick_curve = function(T, Loader)
		local M = Loader.require(CAMERA).Math
		local x, y = M.StickCurve(0.1, 0.05, 0.14, 1.7)
		T.ok(x == 0 and y == 0, "inside the dead zone")
		x, y = M.StickCurve(1, 0, 0.14, 1.7)
		T.near(x, 1, 1e-9, "full deflection -> 1")
		T.near(y, 0, 1e-9)
		x, y = M.StickCurve(0, -1, 0.14, 1.7)
		T.near(y, -1, 1e-9, "sign kept")
		local half = M.StickCurve(0.57, 0, 0.14, 1.7)
		T.ok(half > 0 and half < 0.5, "curve is softer than linear near the centre: " .. half)
		local a = M.StickCurve(0.4, 0, 0.14, 1.7)
		local b = M.StickCurve(0.6, 0, 0.14, 1.7)
		local c = M.StickCurve(0.8, 0, 0.14, 1.7)
		T.ok(a < b and b < c, "monotonic")
	end,

	camera_spline = function(T, Loader)
		local M = Loader.require(CAMERA).Math
		local V3 = Loader.roblox.Vector3
		local CF = Loader.roblox.CFrame
		local p0, p1, p2, p3 = V3.new(0, 0, 0), V3.new(10, 0, 0), V3.new(20, 5, 0), V3.new(30, 5, 10)
		T.near((M.CatmullRom(p0, p1, p2, p3, 0) - p1).Magnitude, 0, 1e-6, "u=0 -> p1")
		T.near((M.CatmullRom(p0, p1, p2, p3, 1) - p2).Magnitude, 0, 1e-6, "u=1 -> p2")
		-- collinear evenly spaced points stay on the line
		local mid = M.CatmullRom(V3.new(0, 0, 0), V3.new(1, 0, 0), V3.new(2, 0, 0), V3.new(3, 0, 0), 0.5)
		T.near(mid.X, 1.5, 1e-6, "collinear midpoint")
		-- duplicate control points do not produce NaN (centripetal knot guard)
		local dup = M.CatmullRom(p1, p1, p2, p2, 0.5)
		T.ok(dup.X == dup.X and dup.Y == dup.Y, "no NaN with duplicate points")

		local path = {
			CF.new(0, 30, 80),
			CF.new(60, 25, 40),
			CF.new(40, 20, -40),
			CF.new(-30, 12, -20),
			CF.new(0, 8, 20),
		}
		T.eq(M.BuildPath({ path[1] }), nil, "one point is not a path")
		local cache = M.BuildPath(path, 16)
		T.ok(cache ~= nil and cache.Total > 0, "path built")
		local first = M.SamplePath(cache, 0)
		local last = M.SamplePath(cache, 1)
		T.near((first.Position - path[1].Position).Magnitude, 0, 1e-4, "starts at the first key")
		T.near((last.Position - path[#path].Position).Magnitude, 0, 1e-4, "ends at the last key")
		-- passes through every key
		for i = 2, #path - 1 do
			local best = math.huge
			for k = 0, 400 do
				local p = M.SamplePath(cache, k / 400).Position
				best = math.min(best, (p - path[i].Position).Magnitude)
			end
			T.ok(best < 0.8, ("passes near key %d (%.3f)"):format(i, best))
		end
		-- cumulative lengths are monotonic and the sampler is ~constant speed
		for i = 2, #cache.Lengths do
			T.ok(cache.Lengths[i] >= cache.Lengths[i - 1], "monotonic arc length")
		end
		local steps = 50
		local minStep, maxStep = math.huge, 0
		local prev = M.SamplePath(cache, 0).Position
		for k = 1, steps do
			local p = M.SamplePath(cache, k / steps).Position
			local d = (p - prev).Magnitude
			minStep = math.min(minStep, d)
			maxStep = math.max(maxStep, d)
			prev = p
		end
		T.ok(maxStep / minStep < 1.15, ("constant speed (step ratio %.3f)"):format(maxStep / minStep))
		-- the camera looks along the keys' look direction at the keys
		local look = M.SamplePath(cache, 0).LookVector
		T.near(look:Dot(path[1].LookVector), 1, 1e-3, "start orientation from the first key")
	end,

	camera_orbit = function(T, Loader)
		local M = Loader.require(CAMERA).Math
		local V3 = Loader.roblox.Vector3
		local center = V3.new(10, 0, -5)
		for _, yaw in { 0, 1, 2.5, -2 } do
			local cf = M.Orbit(center, yaw, 20, 6, 2)
			local flat = V3.new(cf.Position.X - center.X, 0, cf.Position.Z - center.Z)
			T.near(flat.Magnitude, 20, 1e-4, "orbit radius")
			T.near(cf.Position.Y - center.Y, 6, 1e-4, "orbit height")
			local toTarget = ((center + V3.new(0, 2, 0)) - cf.Position).Unit
			T.near(cf.LookVector:Dot(toTarget), 1, 1e-4, "orbit looks at the centre")
			local y2 = M.YawPitch(cf.LookVector)
			T.near(math.cos(y2 - yaw), 1, 1e-3, "orbit yaw matches the view yaw")
		end
	end,

	--------------------------------------------------------------------------------------------- shake
	shake_trauma_decay = function(T, Loader)
		local CameraShake = Loader.require(SHAKE)
		local s = CameraShake.new({ DecayRate = 1.2, Exponent = 2 })
		s:AddTrauma(0.8)
		s:Update(0.1)
		T.near(s:Trauma(), 0.68, 1e-9, "linear decay")
		T.near(s:Magnitude(), 0.68 * 0.68, 1e-9, "magnitude = trauma^2")
		s:Update(0.25)
		T.near(s:Trauma(), 0.38, 1e-9, "decays further")
		for _ = 1, 10 do
			s:Update(0.25)
		end
		T.eq(s:Trauma(), 0, "clamped at zero")
		local pos, rot = s:Update(0.1)
		T.eq(pos.Magnitude, 0, "no offset at rest")
		T.eq(rot.Magnitude, 0, "no rotation at rest")
		s:AddTrauma(5)
		s:Update(0)
		T.near(s:Trauma(), s.MaxTrauma, 1e-9, "capped at MaxTrauma")
		s:AddTrauma(0 / 0)
		s:Update(0)
		T.ok(s:Trauma() == s:Trauma(), "NaN ignored")
		s:Reset()
		T.eq(s:Trauma(), 0, "reset")
	end,

	shake_sources_envelope = function(T, Loader)
		local CameraShake = Loader.require(SHAKE)
		local s = CameraShake.new()
		s:Shake(0.5, 1.0)
		s:Update(0)
		T.near(s:Trauma(), 0.5, 1e-9, "full intensity at the start")
		s:Update(0.25)
		s:Update(0.25)
		T.near(s:Trauma(), 0.5 * 0.25, 1e-9, "(1 - t/d)^2 envelope")
		s:Update(0.25)
		s:Update(0.25)
		s:Update(0.1)
		T.eq(s:Trauma(), 0, "source ended")
		T.eq(s:ActiveSources(), 0, "source removed")
		-- several sources: max + 25 % of the rest
		s:Shake(0.4, 10)
		s:Shake(0.2, 10)
		s:Update(0)
		T.near(s:Trauma(), 0.4 + 0.25 * 0.2, 1e-9, "combined sources")
		-- saturation keeps the strongest
		local t = CameraShake.new({ MaxSources = 2 })
		t:Shake(0.1, 5)
		t:Shake(0.2, 5)
		t:Shake(0.9, 5)
		t:Update(0)
		T.ok(t:Trauma() >= 0.9, "strongest source kept when full")
		T.eq(t:ActiveSources(), 2, "bounded source count")
	end,

	shake_offsets = function(T, Loader)
		local CameraShake = Loader.require(SHAKE)
		local a = CameraShake.new({ Seed = 3.3 })
		local b = CameraShake.new({ Seed = 3.3 })
		a:AddTrauma(1)
		b:AddTrauma(1)
		local maxRot = 0
		for _ = 1, 30 do
			local pa, ra = a:Update(1 / 60)
			local pb, rb = b:Update(1 / 60)
			T.ok((pa - pb).Magnitude < 1e-9 and (ra - rb).Magnitude < 1e-9, "deterministic")
			maxRot = math.max(maxRot, math.abs(ra.X), math.abs(ra.Y), math.abs(ra.Z))
		end
		T.ok(maxRot > 0, "shakes")
		T.ok(maxRot <= math.rad(3.2) * 1.0001, "bounded by MaxAngles")
		local off = CameraShake.new()
		off:SetScale(0)
		off:AddTrauma(1)
		local p, r = off:Update(1 / 60)
		T.eq(p.Magnitude + r.Magnitude, 0, "scale 0 (setting off / reduced motion) -> still")
		-- module-level shortcuts drive the default instance
		CameraShake.Default:Reset()
		CameraShake.Shake(0.3, 0.5)
		CameraShake.Default:Update(0)
		T.near(CameraShake.Default:Trauma(), 0.3, 1e-9, "CameraShake.Shake -> Default")
		CameraShake.AddTrauma(0.2)
		CameraShake.Default:Update(0)
		T.near(CameraShake.Default:Trauma(), 0.5, 1e-9, "CameraShake.AddTrauma -> Default")
		CameraShake.Default:Reset()
		for name, preset in CameraShake.Presets do
			T.ok(type(preset[1]) == "number" and type(preset[2]) == "number", "preset " .. name)
		end
	end,

	--------------------------------------------------------------------------------------------- audio
	audio_registry_well_formed = function(T, Loader)
		local Audio = Loader.require(AUDIO)
		local problems = Audio.Validate()
		T.eq(#problems, 0, "Audio.Validate: " .. table.concat(problems, "; "))
		for name, def in Audio.Sounds do
			if def.Id ~= "" then
				local builtin = string.sub(def.Id, 1, 11) == "rbxasset://"
				T.ok(not builtin or BUILTIN_SOUNDS[def.Id], name .. " uses a confirmed built-in file: " .. def.Id)
			end
		end
		-- everything the task / other modules ask for exists
		local required = {
			"Lobby", "Map_HallOfVerdicts", "Map_SnowdinCrossroads", "Map_WaterfallGrotto", "Map_VoidRift",
			"Map_CoreReactor", "FinalPhase", "VerdictBox", "Victory", "Defeat",
			"BlasterCharge", "BlasterFire", "BoneRise", "BoneHit", "Slash", "Punch", "Shot", "Parry", "Dodge", "Hit",
			"SoulBreak", "Heal", "SaveLit", "UiHover", "UiClick", "UiConfirm", "UiBack", "TextBlip", "SansTextBlip",
			"Teleport", "Ding", "Dash", "DoubleJump", "SlamLand", "FinalPhaseStinger",
		}
		for _, name in required do
			T.ok(Audio.Get(name) ~= nil, "registry has " .. name)
		end
		for _, name in Audio.Names("Music") do
			T.eq(Audio.Get(name).Group, "Music", name)
		end
	end,

	audio_resolution = function(T, Loader)
		local Audio = Loader.require(AUDIO)
		T.eq(Audio.NormalizeId("123"), "rbxassetid://123", "bare id")
		T.eq(Audio.NormalizeId(""), "", "empty stays empty")
		T.eq(Audio.NormalizeId("rbxassetid://9"), "rbxassetid://9", "full id untouched")
		local def, name = Audio.Resolve("Land")
		T.ok(def ~= nil and name == "Land", "built-in resolves to itself")
		T.eq(Audio.Resolve("NoSuchSound"), nil, "unknown -> silent")
		-- an empty entry with an empty fallback chain is silent; with a built-in at the end it resolves
		local revive, reviveName = Audio.Resolve("Revive")
		T.ok(revive ~= nil and reviveName == "GetUp", "Revive falls back to the built-in GetUp")
		if #Audio.Candidates("Hit") == 0 and #Audio.Candidates("HitHeavy") == 0 then -- (Id and Ids both count)
			T.eq(Audio.Resolve("HitHeavy"), nil, "fallback to an empty entry is silent")
		end
		T.eq(Audio.MapMusic("Map_VoidRift"), "Map_VoidRift")
		T.eq(Audio.MapMusic("Map_VoidRift", true), "Map_VoidRift_Final")
		T.eq(Audio.MapMusic("Lobby", true), "FinalPhase", "no per-map final -> FinalPhase")
		T.eq(Audio.MapMusic("VoidRift"), "Map_VoidRift", "alias")
		T.eq(Audio.MapMusic(nil), "Lobby", "default")
		T.eq(Audio.Get("Map_VoidRift_Final").Fallback, "FinalPhase")
	end,

	audio_covers_maps_and_themes = function(T, Loader)
		local Audio = Loader.require(AUDIO)
		local okReg, Registry = pcall(Loader.require, REGISTRY)
		T.ok(okReg, "Maps/Registry loads")
		if okReg then
			for _, meta in Registry.List() do
				T.ok(Audio.Get(meta.Music) ~= nil, ("map %s music key %s is registered"):format(meta.Id, meta.Music))
			end
		end
		local okThemes, Themes = false, nil
		quiet(Loader, function()
			okThemes, Themes = pcall(Loader.require, THEMES)
		end)
		if okThemes and type(Themes) == "table" and type(Themes.List) == "function" then
			for _, theme in Themes.List() do
				for kind, key in theme.Sounds or {} do
					T.ok(Audio.Get(key) ~= nil, ("theme %s sound %s = %s is registered"):format(theme.Id, kind, key))
				end
			end
		end
	end,

	-- literal sound names played by client code should exist in Shared/Audio (or be Register()-ed at runtime).
	-- Unknown names play nothing (no runtime harm), so drift is REPORTED (printed) instead of failing the gate:
	-- other agents cannot edit Shared/Audio.luau. The client-core controllers themselves must stay covered.
	audio_covers_client_sound_calls = function(T, Loader)
		local fs = require("@lune/fs")
		local Audio = Loader.require(AUDIO)
		local files = {}
		local function collect(dir)
			for _, name in fs.readDir(dir) do
				local path = dir .. "/" .. name
				if fs.isDir(path) then
					collect(path)
				elseif string.find(name, "%.luau$") then
					table.insert(files, path)
				end
			end
		end
		collect("src/client")
		local registered, used = {}, {}
		local patterns = {
			'[Ss]ound%("([%w_%.]+)"',
			'playSound%("([%w_%.]+)"',
			'SoundController%.Play%("([%w_%.]+)"',
			'"SoundController", "Play", "([%w_%.]+)"',
		}
		for _, path in files do
			local source = fs.readFile(path)
			for name in string.gmatch(source, '%.Register%("([%w_%.]+)"') do
				registered[name] = true
			end
			for _, pattern in patterns do
				for name in string.gmatch(source, pattern) do
					used[name] = used[name] or path
				end
			end
		end
		local CORE = {
			InputController = true,
			StateController = true,
			CameraController = true,
			SoundController = true,
			MovementController = true,
			SpectateController = true,
			RigStyleController = true,
		}
		local count, missing = 0, {}
		for name, path in used do
			count += 1
			if Audio.Get(name) == nil and not registered[name] then
				local file = string.match(path, "([%w_]+)%.luau$") or path
				if CORE[file] then
					T.ok(false, ("sound %q (used in %s) is in Shared/Audio"):format(name, path))
				else
					table.insert(missing, ("%s (%s)"):format(name, path))
				end
			end
		end
		T.ok(count > 0, "found sound calls to check")
		if #missing > 0 then
			table.sort(missing)
			print("[warn] client_core: sounds not in Shared/Audio (silent until registered): " .. table.concat(missing, ", "))
		end
	end,

	-------------------------------------------------------------------------------------------- strings
	controls_strings = function(T, Loader)
		local Controls = Loader.require(CONTROLS)
		for key, entry in Controls do
			T.ok(type(entry.en) == "string" and entry.en ~= "", key .. " has en")
			T.ok(type(entry.ru) == "string" and entry.ru ~= "", key .. " has ru")
		end
		local Input = Loader.require(INPUT)
		for _, action in Input.Actions do
			T.ok(Controls["controls.action." .. action] ~= nil, "action name for " .. action)
		end
		for _, device in { "KeyboardMouse", "Gamepad", "Touch" } do
			T.ok(Controls["controls.device." .. device] ~= nil, "device name " .. device)
		end
		-- every gamepad token has a label; keyboard tokens either have a label or are a single character
		for _, layout in { "Monster", "Human" } do
			for _, tokens in Input.Bindings.Gamepad[layout] do
				for _, token in tokens do
					if token ~= Input.CHORD then
						T.ok(Controls["controls.pad." .. token] ~= nil, "pad label for " .. token)
					end
				end
			end
		end
		for _, tokens in Input.Bindings.KeyboardMouse do
			for _, token in tokens do
				T.ok(#token == 1 or Controls["controls.key." .. token] ~= nil, "key label for " .. token)
			end
		end
		local Strings = Loader.require(STRINGS)
		T.ok(Strings.Has("controls.lock.on"), "Controls merged into Strings")
		T.eq(Strings.L("controls.chord", "LT", "RT"), "LT+RT", "chord template")
	end,

	--------------------------------------------------------------------------------------- module shapes
	controllers_require_offline = function(T, Loader)
		local expected = {
			InputController = { 5, { "Init", "Start", "IsDown", "Device", "PushContext", "PopContext", "CombatEnabled", "KeyLabel", "BindTouchButton" } },
			StateController = { 8, { "Init", "Start", "Round", "Phase", "TimeLeft", "Now", "Profile", "OnRoundEvent", "LocalCharacter", "Role", "Request", "Leaderboards", "KitOf", "IsEnemy", "Setting", "SetSetting" } },
			SoundController = { 10, { "Init", "Start", "Play", "PlayMusic", "StopMusic", "SetVolumes", "Register", "Stop", "SetMusicOverride", "Duck" } },
			CameraController = { 15, { "Init", "Start", "SetMode", "PlayIntro", "Spectate", "KillCam", "Shake", "Kick", "AimRay", "AimPoint", "SetLock", "LockEnabled", "Focus", "FacingYaw", "ShouldFaceCamera", "Cut" } },
			MovementController = { 22, { "Init", "Start", "Facing", "ApplyForceMove", "IsDashing", "PredictDash", "FaceFor" } },
			SpectateController = { 45, { "Init", "Start", "IsSpectating", "Target", "Targets", "Next", "Prev", "SetEnabled" } },
			RigStyleController = { 50, { "Init", "Start", "Style", "SetOverride", "ApplyTo", "Refresh" } },
		}
		local signals = {
			InputController = { "Action", "DeviceChanged", "ContextChanged" },
			StateController = { "RoundChanged", "ProfileChanged", "RoundEvent", "Notify", "CharacterChanged", "SettingChanged" },
			CameraController = { "ModeChanged", "LockChanged" },
			MovementController = { "Dashed", "DoubleJumped", "Landed" },
			SpectateController = { "Changed", "TargetChanged" },
			RigStyleController = { "StyleChanged" },
		}
		for name, spec in expected do
			local ok, module
			quiet(Loader, function()
				ok, module = pcall(Loader.require, CLIENT .. "Controllers." .. name)
			end)
			T.ok(ok, name .. " requires under Lune: " .. tostring(module))
			if ok then
				T.eq(module.Priority, spec[1], name .. ".Priority")
				for _, fn in spec[2] do
					T.ok(type(module[fn]) == "function", ("%s.%s is a function"):format(name, fn))
				end
				for _, signalName in signals[name] or {} do
					local s = module[signalName]
					T.ok(type(s) == "table" and type(s.Connect) == "function", ("%s.%s is a signal"):format(name, signalName))
				end
			end
		end
	end,
}
