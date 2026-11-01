--!nocheck
-- Combat client unit tests (pure helpers of the combat client): beam layer sizes over time, Gaster Blaster pose,
-- telegraph timing windows, spike / rain visual timing vs the server geometry, payload building per Aim mode,
-- soft targeting, damage-number styling, cast clips, the visual registry and client kit shapes.
-- Run: lune run tools/lune/run_tests.luau combat_client
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Instance = roblox.Instance

local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."

local function hv(Loader)
	return Loader.require(CLIENT .. "Controllers.HazardVisuals")
end

local function lib(Loader)
	return Loader.require(CLIENT .. "VFX.Lib")
end

local function defs(Loader)
	return Loader.require("ReplicatedStorage.Shared.Combat.HazardDefs")
end

local function colorEq(a, b)
	return math.abs(a.R - b.R) < 1e-3 and math.abs(a.G - b.G) < 1e-3 and math.abs(a.B - b.B) < 1e-3
end

return {
	modules_load_under_lune = function(T, Loader)
		for _, path in
			{
				"Controllers.HazardVisuals",
				"Controllers.FxController",
				"Controllers.CombatController",
				"VFX.Lib",
				"VFX.Pool",
				"VFX.ScreenFX",
				"VFX.DamageNumbers",
				"Kits.ClassicSans",
				"Kits.Determination",
			}
		do
			T.noerror(function()
				local m = Loader.require(CLIENT .. path)
				assert(type(m) == "table", path .. " did not return a table")
			end, path .. " loads")
		end
	end,

	beam_layers_are_honest_and_stacked = function(T, Loader)
		local H = hv(Loader)
		local p = { delay = 0.75, duration = 0.6, width = 5, linger = 0.35 }
		local core, mid, outer, alpha, phase = H.BeamLayers(p, 0.5)
		T.eq(outer, 0, "nothing before the beam")
		T.eq(phase, "Charge")
		for i = 0, 60 do
			local t = 0.75 + i * 0.01
			core, mid, outer, alpha, phase = H.BeamLayers(p, t)
			T.ok(outer >= 5 - 1e-6, ("outer layer >= hit width at t=%.2f (got %.3f)"):format(t, outer))
			T.near(core, outer / 2, 1e-9, "core = outer / 2")
			T.near(mid, outer / 1.25, 1e-9, "mid = outer / 1.25")
			T.eq(alpha, 1, "opaque while damaging")
			T.eq(phase, "Fire")
		end
		-- appears a hair early, ramps in 0.06 s
		local _, _, early = H.BeamLayers(p, 0.72)
		T.ok(early > 0 and early < 5, "ramp before the damage window")
		-- fade: x0.8 per 30 Hz frame, -10 % opacity per frame
		core, mid, outer, alpha, phase = H.BeamLayers(p, 0.75 + 0.6 + 0.1)
		T.eq(phase, "Fade")
		T.near(outer, 5 * 1.08 * 0.8 ^ 3, 1e-6, "shrinks 0.8 per frame")
		T.near(alpha, 0.7, 1e-6, "opacity -10 % per frame")
		local _, _, _, _, done = H.BeamLayers(p, 0.75 + 0.6 + 0.36)
		T.eq(done, "Done")
	end,

	blaster_pose_flies_in_aims_and_recoils = function(T, Loader)
		local H = hv(Loader)
		local D = defs(Loader)
		local origin = D.LookAlong(Vector3.new(0, 10, 0), Vector3.new(1, -0.2, 0))
		local p = { origin = origin, delay = 0.75, duration = 0.6, linger = 0.35, spawnFrom = Vector3.new(0, 0, 10) }
		local p0 = H.BlasterPose(p, 0)
		T.ok((p0.Pos - Vector3.new(0, 1.5, 10)).Magnitude < 1e-6, "starts at spawnFrom (+1.5 up)")
		T.near(p0.Alpha, 0, 1e-6, "fades in")
		local p1 = H.BlasterPose(p, 0.3)
		T.ok((p1.Pos - origin.Position).Magnitude < 1e-6, "sits exactly at the muzzle slot after the fly-in")
		local aimed = H.BlasterPose(p, 0.75 - 0.12)
		T.ok(aimed.Look:Dot(origin.LookVector) > 0.999, "fully aimed before the beam")
		local lastJaw = -1
		for i = 0, 75 do
			local pose = H.BlasterPose(p, i * 0.01)
			T.ok(pose.Jaw >= lastJaw - 1e-9, "jaw only opens before firing")
			lastJaw = pose.Jaw
		end
		local fire = H.BlasterPose(p, 0.9)
		T.eq(fire.Eyes, 0, "sockets go hollow while firing")
		T.ok(fire.Recoil > 0, "recoils while firing")
		T.ok(fire.Jaw > 0.4, "jaw wide open while firing")
		local gone = H.BlasterPose(p, 0.75 + 0.6 + 0.35)
		T.near(gone.Alpha, 0, 1e-6, "faded out at the end of the linger")
		T.ok(gone.Recoil > fire.Recoil, "flies away after the beam")
	end,

	telegraph_windows = function(T, Loader)
		local L = lib(Loader)
		local phase, k = L.TelegraphPhase(0.15, 0.75, 0.1)
		T.eq(phase, "Hidden")
		phase, k = L.TelegraphPhase(0.15, 0.75, 0.15)
		T.eq(phase, "Warn")
		T.near(k, 0, 1e-9)
		phase, k = L.TelegraphPhase(0.15, 0.75, 0.45)
		T.near(k, 0.5, 1e-9, "progress halfway")
		phase, k = L.TelegraphPhase(0.15, 0.75, 0.75)
		T.eq(phase, "Impact", "flash at the moment damage starts")
		phase = L.TelegraphPhase(0.15, 0.75, 0.75 + L.TELEGRAPH_IMPACT + 0.01)
		T.eq(phase, "Done")
		-- steady first, then blinking near the end
		T.ok(L.TelegraphBlink(0.5, 0.01) and L.TelegraphBlink(0.5, 0.08), "steady before 70 %")
		local on1, on2 = L.TelegraphBlink(0.9, 0.0), L.TelegraphBlink(0.9, 1 / 14 + 0.001)
		T.ok(on1 ~= on2, "blinks during the last 30 %")
		-- real hazards: the telegraph ends exactly when damage starts
		local D = defs(Loader)
		local spikes =
			D.Normalize("BoneSpikes", { center = Vector3.new(0, 0, 0), radius = 10, delay = 1.4, warn = 0.6 })
		local desc = D.Telegraph("BoneSpikes", spikes)
		T.eq(desc.Kind, "Circle")
		T.near(desc.Start, 0.8, 1e-9)
		T.near(desc.End, 1.4, 1e-9)
		local start = D.ActiveWindow("BoneSpikes", spikes)
		T.near(desc.End, start, 1e-9, "telegraph End == damage start")
		local rain = D.Normalize("Rain", { center = Vector3.new(0, 0, 0), count = 4, interval = 0.3, delay = 1 })
		local multi = D.Telegraph("Rain", rain)
		T.eq(multi.Kind, "Multi")
		T.eq(#multi.Items, 4, "one circle per drop")
	end,

	spike_visuals_lead_the_hitbox = function(T, Loader)
		local H = hv(Loader)
		local D = defs(Loader)
		local p = D.Normalize(
			"BoneSpikes",
			{ center = Vector3.new(0, 0, 0), radius = 8, height = 5, delay = 0.6, rise = 0.12, hold = 0.45 }
		)
		T.eq(H.SpikeFrac(p, 0.3), 0, "hidden before the peek")
		T.ok(H.SpikeFrac(p, 0.55) > 0 and H.SpikeFrac(p, 0.55) < 0.1, "tips peek just before")
		for i = 0, 57 do
			local t = 0.6 + i * 0.01
			local server = D.SpikeHeight(p, t)
			T.ok(H.SpikeFrac(p, t) * 5 >= server - 1e-6, ("visual >= server height at t=%.2f"):format(t))
		end
		T.eq(H.SpikeFrac(p, 0.6 + 0.12 + 0.45 + 0.2 + 0.01), 0, "retracted")
	end,

	rain_drop_timing = function(T, Loader)
		local H = hv(Loader)
		local p = { fallTime = 0.35, fallHeight = 30, impactTime = 0.12 }
		local drop = { ImpactTime = 1 }
		local s, h = H.RainFall(p, drop, 0.5)
		T.eq(s, "Wait")
		s, h = H.RainFall(p, drop, 0.8)
		T.eq(s, "Fall")
		T.ok(h > 0 and h < 30, "falling height")
		local _, h2 = H.RainFall(p, drop, 0.95)
		T.ok(h2 < h, "accelerates down")
		s = H.RainFall(p, drop, 1.05)
		T.eq(s, "Stuck", "lands exactly at the impact time")
		s = H.RainFall(p, drop, 2)
		T.eq(s, "Gone")
	end,

	payload_per_aim_mode = function(T, Loader)
		local C = Loader.require(CLIENT .. "Controllers.CombatController")
		local root = Vector3.new(0, 3, 0)
		local look = Vector3.new(0, 0, -1)
		-- Direction: clamped to Range
		local dirP = C.BuildPayload(
			{ Aim = "Direction", Range = 90 },
			{ Root = root, Look = look, Aim = Vector3.new(0, 3, -200), CastId = 7 }
		)
		T.near((dirP.aim - root).Magnitude, 90, 1e-4, "direction aim clamped to range")
		T.ok(dirP.dir:Dot(Vector3.new(0, 0, -1)) > 0.999, "direction dir")
		T.eq(dirP.castId, 7)
		T.eq(dirP.charge, nil, "no charge for non-hold abilities")
		T.eq(dirP.target, nil)
		-- Ground: horizontal clamp + ground snap
		local groundP = C.BuildPayload({ Aim = "Ground", Range = 70 }, {
			Root = root,
			Look = look,
			Aim = Vector3.new(100, 5, 0),
			Ground = function(p)
				return Vector3.new(p.X, -1, p.Z)
			end,
			CastId = 1,
		})
		T.near(groundP.aim.X, 70, 1e-4, "ground aim clamped horizontally")
		T.near(groundP.aim.Y, -1, 1e-4, "snapped to the ground")
		T.ok(groundP.dir:Dot(Vector3.new(1, 0, 0)) > 0.999, "flat dir toward the point")
		-- Target
		local m = Instance.new("Model")
		local tgtP = C.BuildPayload(
			{ Aim = "Target", Range = 45 },
			{
				Root = root,
				Look = look,
				Aim = Vector3.new(5, 3, -5),
				Target = m,
				TargetPos = Vector3.new(0, 3, -20),
				CastId = 2,
			}
		)
		T.eq(tgtP.target, m)
		T.ok((tgtP.aim - Vector3.new(0, 3, -20)).Magnitude < 1e-6, "target aim = target position")
		-- Self
		local selfP = C.BuildPayload(
			{ Aim = "Self" },
			{ Root = root, Look = Vector3.new(1, 0.5, 0), Aim = Vector3.new(9, 9, 9), CastId = 3 }
		)
		T.ok((selfP.aim - root).Magnitude < 1e-6, "self aim = own position")
		T.ok(selfP.dir:Dot(Vector3.new(1, 0, 0)) > 0.999, "self dir = flat look")
		-- Ally without a target: clamped aim, no target
		local allyP = C.BuildPayload(
			{ Aim = "Ally", Range = 30 },
			{ Root = root, Look = look, Aim = Vector3.new(0, 3, -100), CastId = 4 }
		)
		T.eq(allyP.target, nil)
		T.near((allyP.aim - root).Magnitude, 30, 1e-4)
		-- Hold: charge clamped to [0, 1]
		local holdP = C.BuildPayload(
			{ Aim = "Direction", Range = 90, Hold = { MaxTime = 1.2 } },
			{ Root = root, Look = look, Aim = Vector3.new(0, 3, -10), Charge = 1.7, CastId = 5 }
		)
		T.eq(holdP.charge, 1)
		T.near(C.ChargeOf(0.6, 1.2), 0.5, 1e-9)
		T.eq(C.ChargeOf(5, 1.2), 1)
		-- aim right under the caster: falls back to the facing
		local close = C.BuildPayload(
			{ Aim = "Direction", Range = 90 },
			{ Root = root, Look = look, Aim = Vector3.new(0, 0, 0.2), CastId = 6 }
		)
		T.ok(close.dir:Dot(look) > 0.999, "degenerate aim uses the facing")
	end,

	soft_target_selection = function(T, Loader)
		local C = Loader.require(CLIENT .. "Controllers.CombatController")
		local a, b, c, d = Instance.new("Model"), Instance.new("Model"), Instance.new("Model"), Instance.new("Model")
		local cands = {
			{ Model = a, Pos = Vector3.new(3, 0, -20) }, -- ~8.5 deg off
			{ Model = b, Pos = Vector3.new(1, 0, -30) }, -- ~1.9 deg off  <- best
			{ Model = c, Pos = Vector3.new(0, 0, -80) }, -- on the ray but out of range
			{ Model = d, Pos = Vector3.new(20, 0, -10) }, -- outside the cone
		}
		local pick = C.SelectTarget(Vector3.zero, Vector3.new(0, 0, -1), Vector3.zero, cands, 45, 22)
		T.eq(pick, b, "closest to the aim ray within range")
		T.eq(
			C.SelectTarget(Vector3.zero, Vector3.new(1, 0, 0), Vector3.zero, { cands[1] }, 45, 22),
			nil,
			"nothing in the cone"
		)
		local justice = Loader.require("ReplicatedStorage.Shared.Kits").Get("Justice")
		local ammo = C.AmmoAbility(justice)
		T.ok(ammo ~= nil and ammo.Numbers.Ammo == 6, "Justice M1 carries ammo")
		T.eq(C.AmmoAbility(Loader.require("ReplicatedStorage.Shared.Kits").Get("ClassicSans")), nil)
	end,

	damage_number_styles = function(T, Loader)
		local DN = Loader.require(CLIENT .. "VFX.DamageNumbers")
		local Strings = Loader.require("ReplicatedStorage.Shared.Strings")
		local me, enemy = Instance.new("Model"), Instance.new("Model")
		local miss = DN.Style({ target = enemy, amount = 0, kind = "Melee", dodged = true })
		T.eq(miss.Kind, "Miss")
		T.eq(miss.Text, Strings.L("fx.miss"))
		T.ok(colorEq(miss.Color, Color3.fromRGB(191, 191, 191)), "Undertale grey MISS #BFBFBF")
		T.eq(DN.Style({ target = enemy, amount = 0, kind = "Melee", negated = "Afterimage" }).Kind, "Miss")
		local heal = DN.Style({ target = me, amount = 12, kind = "Heal" })
		T.eq(heal.Kind, "Heal")
		T.eq(heal.Text, "+12")
		T.eq(DN.Style({ target = me, amount = 0.2, kind = "Heal" }), nil, "tiny heals are silent")
		T.eq(DN.Style({ target = enemy, amount = 0, kind = "Melee", parried = true }).Kind, "Parry")
		local crit = DN.Style({ target = enemy, amount = 21.6, kind = "Melee", crit = true })
		T.eq(crit.Kind, "Crit")
		T.eq(crit.Text, "22!")
		T.ok(crit.Scale > 1.2, "crits are big")
		T.eq(DN.Style({ target = enemy, amount = 4, kind = "Melee", blocked = true }).Kind, "Blocked")
		T.eq(DN.Style({ target = me, amount = 9, kind = "Beam" }, { Local = me }).Kind, "Taken", "hits on the viewer")
		local dealt = DN.Style({ target = enemy, amount = 9, kind = "Beam" }, { Local = me })
		T.eq(dealt.Kind, "Damage")
		T.ok(colorEq(dealt.Color, Color3.fromRGB(255, 46, 46)), "Undertale red damage")
		T.eq(DN.Style({ target = enemy, amount = 0, kind = "Area" }), nil, "no number for nothing")
		local abs = DN.Style({ target = enemy, amount = 0, kind = "Area", absorbed = 5 })
		T.eq(abs.Text, "(5)")
		local drain = DN.Style({ target = enemy, amount = 1, kind = "DodgeDrain" })
		T.eq(drain.Kind, "Dodge")
		T.eq(drain.Text, Strings.L("fx.dodgeDrain", "1"))
		T.ok(DN.STYLES.KR.Scale < 1, "KR ticks are small")
		T.ok(colorEq(DN.STYLES.KR.Color, Color3.fromRGB(213, 53, 217)), "KR purple")
		T.eq(DN.Format(0.5), "0.5")
		T.eq(DN.Format(7.4), "7")
		T.eq(DN.Format(12.5), "13")
	end,

	hit_colors_and_cast_clips = function(T, Loader)
		local Fx = Loader.require(CLIENT .. "Controllers.FxController")
		local L = lib(Loader)
		T.ok(colorEq(Fx.HitColor({ color = "Blue", kind = "Area" }), L.Colors.Blue), "colour rule wins")
		T.ok(colorEq(L.Colors.Blue, Color3.fromRGB(20, 169, 255)), "#14A9FF")
		T.ok(colorEq(L.Colors.Orange, Color3.fromRGB(255, 160, 64)), "#FFA040")
		local human = Instance.new("Model")
		human:SetAttribute("Team", "Humans")
		human:SetAttribute("KitId", "Determination")
		T.ok(
			colorEq(Fx.HitColor({ kind = "Melee", attacker = human }), Color3.fromRGB(255, 0, 0)),
			"human hits use the SOUL colour"
		)
		T.eq(Fx.CastClip({ Clip = "Slash1" }, 1), "Slash1")
		T.eq(Fx.CastClip({ Clip = "Slash1" }, 3), "Slash3")
		T.eq(Fx.CastClip({ Clip = "Slash1" }, 5), "Slash1", "wraps after 4")
		T.eq(Fx.CastClip({ Clip = "Kick1" }, 4), "Kick1", "kicks wrap after 3")
		T.eq(Fx.CastClip({ Clip = "Summon" }, 3), "Summon", "non-combo clips stay")
		T.eq(Fx.CastClip(nil, 1), nil)
	end,

	bones_are_at_least_as_wide_as_the_hitbox = function(T, Loader)
		local L = lib(Loader)
		local Config = Loader.require("ReplicatedStorage.Shared.Config")
		for _, t in { 0.7, 0.8, 0.9 } do
			local d = L.BoneDims(t)
			T.ok(d.Shaft >= t * Config.Combat.HazardForgiveness - 1e-9, "shaft >= effective hit thickness")
			T.ok(d.Span >= t, "knob pair wider than the hitbox")
		end
		local H = hv(Loader)
		T.near(H.BlasterScale(5, 2.5), 2.5, 1e-9, "skull ~1.25x the beam width")
	end,

	visual_registry = function(T, Loader)
		local H = hv(Loader)
		for _, name in
			{
				"Orb",
				"Bone",
				"Bullet",
				"Ribbon",
				"Page",
				"Dish",
				"StarBone",
				"Chain",
				"Star",
				"Fireball",
				"Knife",
				"VoidOrb",
			}
		do
			T.ok(H.HasVisual(name), "built-in visual " .. name)
		end
		T.ok(not H.HasVisual("NoSuchVisual"))
		H.RegisterVisual("TestVisual", function(_ctx)
			return { Destroy = function() end }
		end)
		T.ok(H.HasVisual("TestVisual"), "registered")
		T.ok(table.find(H.Visuals(), "TestVisual") ~= nil, "listed")
		T.fails(function()
			H.RegisterVisual("", function() end)
		end, "empty name rejected")
		T.fails(function()
			H.RegisterVisual("X", 5)
		end, "non-function rejected")
		T.fails(function()
			H.RegisterRenderer("Y", {})
		end, "renderer needs Update")
	end,

	client_kits_cover_every_ability = function(T, Loader)
		local Kits = Loader.require("ReplicatedStorage.Shared.Kits")
		for _, kitId in { "ClassicSans", "Determination" } do
			local client = Loader.require(CLIENT .. "Kits." .. kitId)
			T.ok(type(client.Effects) == "table", kitId .. " Effects")
			for _, ability in Kits.Get(kitId).Abilities do
				T.ok(type(client.Effects[ability.Id]) == "function", kitId .. " has Effects." .. ability.Id)
				local aimed = type(ability.Hold) == "table" or ability.Aim == "Ground" or ability.Aim == "Target"
				if aimed and kitId == "ClassicSans" then
					T.ok(type(client.Indicator[ability.Id]) == "function", kitId .. " has Indicator." .. ability.Id)
				end
			end
			T.ok(type(client.OnCharacter) == "function", kitId .. " OnCharacter")
		end
		local Sans = Loader.require(CLIENT .. "Kits.ClassicSans")
		T.eq(#Sans.BlasterSlots(1), 1)
		T.eq(#Sans.BlasterSlots(3), 3)
		T.eq(#Sans.BlasterSlots(6), 6, "generic arc for larger counts")
	end,

	strings_have_both_languages = function(T, Loader)
		local text = Loader.require("ReplicatedStorage.Shared.Strings.KitText")
		for key, entry in text do
			T.ok(type(entry.en) == "string" and entry.en ~= "", key .. " en")
			T.ok(type(entry.ru) == "string" and entry.ru ~= "", key .. " ru")
		end
		local Strings = Loader.require("ReplicatedStorage.Shared.Strings")
		T.ok(Strings.Has("fx.miss") and Strings.Has("fx.counter") and Strings.Has("fx.guardBreak"), "merged")
	end,
}
