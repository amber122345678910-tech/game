--!nocheck
-- Animation system: clip libraries (both families + kit overrides), AnimMath (sampling, easing, blending,
-- masks, mirroring, locomotion weights, IK helpers), Joints, AimService validation.
-- NOTE (Lune): Instance userdata are not identity-stable; compare instances with == only.
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local REQUIRED = {
	"Idle", "Walk", "Run", "Jump", "Fall", "Land", "Dash", "Stunned", "Downed", "Block", "Parry", "Dodge", "Hit",
	"Death", "Victory", "Emote_Wave", "Emote_Shrug", "Emote_Sit", "Emote_Laugh",
	"Cast", "CastUp", "CastForward", "Summon", "Point", "Slam", "Throw", "Spin", "Leap", "Charge",
	"Slash1", "Slash2", "Slash3", "Slash4", "Punch1", "Punch2", "Punch3", "Punch4", "Kick1", "Kick2", "Kick3",
	"Shoot", "Reload", "Heal", "Guard", "Taunt",
}
-- extras the AnimController relies on
local CONTROLLER_CLIPS = { "WalkBack", "StrafeL", "StrafeR", "BlueHeavy", "Idle_Look" }
local LOCOMOTION = { "Walk", "Run", "WalkBack", "StrafeL", "StrafeR" }
local KNOWN_EVENTS = { Hit = true, Step = true, Release = true, Summon = true, Wink = true }

local function families(Loader)
	return {
		Skeleton = Loader.requirePath("src/shared/Anim/Clips/Skeleton"),
		Human = Loader.requirePath("src/shared/Anim/Clips/Human"),
	}
end

local function kitClipFiles(Loader)
	local fs = require("@lune/fs")
	local out = {}
	local dir = "src/shared/Anim/Clips/Kits"
	if fs.isDir(dir) then
		for _, f in fs.readDir(dir) do
			if string.sub(f, -5) == ".luau" then
				local id = string.sub(f, 1, -6)
				out[id] = Loader.requirePath(dir .. "/" .. id)
			end
		end
	end
	return out
end

local function sorted(t)
	local names = {}
	for k in t do
		table.insert(names, k)
	end
	table.sort(names)
	return names
end

local function wrapDiff(a, b)
	local d = (a - b) % 360
	if d > 180 then
		d -= 360
	end
	return math.abs(d)
end

-- max channel difference between two pose buffers (rotations wrap-aware)
local function bufDiff(a, b)
	local m = 0
	for i = 1, #a do
		local c = ((i - 1) % 6) + 1
		local d = if c <= 3 then wrapDiff(a[i], b[i]) else math.abs(a[i] - b[i])
		if d > m then
			m = d
		end
	end
	return m
end

return {
	required_clips_exist_for_both_families = function(T, Loader)
		for fam, lib in families(Loader) do
			for _, name in REQUIRED do
				T.ok(lib[name] ~= nil, fam .. " lacks required clip " .. name)
			end
			for _, name in CONTROLLER_CLIPS do
				T.ok(lib[name] ~= nil, fam .. " lacks controller clip " .. name)
			end
		end
	end,

	every_clip_validates = function(T, Loader)
		local A = Loader.requirePath("src/shared/Anim/AnimMath")
		local count = 0
		local libs = families(Loader)
		for id, lib in kitClipFiles(Loader) do
			libs["Kits/" .. id] = lib
		end
		for fam, lib in libs do
			for _, name in sorted(lib) do
				local ok, err = A.ValidateClip(lib[name], fam .. "." .. name)
				T.ok(ok, err)
				count += 1
			end
		end
		T.ok(count >= 100, "expected 100+ clips, got " .. count)
	end,

	keys_joints_events_are_well_formed = function(T, Loader)
		local Joints = Loader.requirePath("src/shared/Anim/Joints")
		for fam, lib in families(Loader) do
			for _, name in sorted(lib) do
				local clip = lib[name]
				local last = -1
				for k, key in clip.Keys do
					T.ok(key.t > last, ("%s.%s key %d not sorted"):format(fam, name, k))
					T.ok(key.t >= 0 and key.t <= clip.Length + 1e-6, ("%s.%s key %d outside Length"):format(fam, name, k))
					last = key.t
					for joint, v in key.Pose do
						T.ok(Joints.Valid[joint] == true, ("%s.%s unknown joint %s"):format(fam, name, tostring(joint)))
						for i, x in v do
							T.ok(x == x and math.abs(x) < 1e5, ("%s.%s %s[%d] not finite"):format(fam, name, joint, i))
						end
					end
				end
				for _, e in clip.Events or {} do
					T.ok(KNOWN_EVENTS[e.Name] == true, ("%s.%s unknown event %s"):format(fam, name, tostring(e.Name)))
					T.ok(e.t >= 0 and e.t <= clip.Length, ("%s.%s event %s outside Length"):format(fam, name, e.Name))
				end
				if clip.Loop then
					T.near(clip.Keys[1].t, 0, 1e-9, fam .. "." .. name .. " loop starts at 0")
					T.near(clip.Keys[#clip.Keys].t, clip.Length, 1e-6, fam .. "." .. name .. " loop is closed")
				end
			end
		end
	end,

	loops_are_continuous_at_the_boundary = function(T, Loader)
		local A = Loader.requirePath("src/shared/Anim/AnimMath")
		for fam, lib in families(Loader) do
			for _, name in sorted(lib) do
				local clip = lib[name]
				if clip.Loop then
					local c = A.Compile(clip, name)
					local a, b, z = A.NewBuffer(), A.NewBuffer(), A.NewBuffer()
					A.Sample(c, 0, a)
					A.Sample(c, clip.Length - 1e-4, b)
					A.Sample(c, clip.Length + 1e-4, z)
					T.ok(bufDiff(a, b) < 0.5, ("%s.%s jumps at the loop seam (%.3f)"):format(fam, name, bufDiff(a, b)))
					T.ok(bufDiff(a, z) < 0.5, ("%s.%s wraps badly (%.3f)"):format(fam, name, bufDiff(a, z)))
				end
			end
		end
	end,

	sampling_is_continuous_and_hits_keys = function(T, Loader)
		local A = Loader.requirePath("src/shared/Anim/AnimMath")
		for fam, lib in families(Loader) do
			for _, name in sorted(lib) do
				local clip = lib[name]
				local c = A.Compile(clip, name)
				local buf, before, after = A.NewBuffer(), A.NewBuffer(), A.NewBuffer()
				for k, key in clip.Keys do
					A.Sample(c, key.t, buf)
					for joint, v in key.Pose do
						local j = A.PoseToBuffer({ [joint] = v })
						local o = (({ Root = 1, Waist = 2, Neck = 3, LeftShoulder = 4, LeftElbow = 5, LeftWrist = 6, RightShoulder = 7, RightElbow = 8, RightWrist = 9, LeftHip = 10, LeftKnee = 11, LeftAnkle = 12, RightHip = 13, RightKnee = 14, RightAnkle = 15 })[joint] - 1) * 6
						for ch = 1, 3 do
							T.ok(wrapDiff(buf[o + ch], j[o + ch]) < 0.01, ("%s.%s key %d %s ch%d: %.3f vs %.3f"):format(fam, name, k, joint, ch, buf[o + ch], j[o + ch]))
						end
					end
					-- no discontinuity across a key (eased curves are continuous too)
					if k > 1 and k < #clip.Keys then
						-- eased snaps are steep (Expo/Back reach ~10^4 deg/s) but must stay continuous
						A.Sample(c, key.t - 1e-6, before)
						A.Sample(c, key.t + 1e-6, after)
						T.ok(bufDiff(before, after) < 0.25, ("%s.%s jumps across key %d (%.3f)"):format(fam, name, k, bufDiff(before, after)))
					end
				end
				-- dense sweep: always finite
				for i = 0, 40 do
					A.Sample(c, clip.Length * i / 40, buf)
					for _, x in buf do
						if x ~= x then
							T.ok(false, fam .. "." .. name .. " produced NaN")
							break
						end
					end
				end
			end
		end
	end,

	locomotion_cycles_are_phase_aligned = function(T, Loader)
		for fam, lib in families(Loader) do
			for _, name in LOCOMOTION do
				local clip = lib[name]
				T.ok(clip.Loop == true, fam .. "." .. name .. " loops")
				T.ok(type(clip.Stride) == "number" and clip.Stride > 0, fam .. "." .. name .. " has a Stride")
				local steps = {}
				for _, e in clip.Events or {} do
					if e.Name == "Step" then
						table.insert(steps, e.t / clip.Length)
					end
				end
				table.sort(steps)
				T.eq(#steps, 2, fam .. "." .. name .. " has two Step markers")
				if #steps == 2 then
					T.near(steps[1], 0, 1e-6, fam .. "." .. name .. " plants the left foot at phase 0")
					T.near(steps[2], 0.5, 0.06, fam .. "." .. name .. " plants the right foot at phase 0.5")
				end
			end
		end
	end,

	actions_have_sync_markers = function(T, Loader)
		local hitClips = { "Slash1", "Slash2", "Slash3", "Slash4", "Punch1", "Punch2", "Punch3", "Punch4", "Kick1", "Kick2", "Kick3", "Slam", "Spin", "Parry" }
		local releaseClips = { "Cast", "CastUp", "CastForward", "Summon", "Point", "Throw", "Shoot", "Heal", "Charge", "Leap", "Guard", "Taunt" }
		for fam, lib in families(Loader) do
			for _, name in hitClips do
				local has = false
				for _, e in lib[name].Events or {} do
					has = has or e.Name == "Hit"
				end
				T.ok(has, fam .. "." .. name .. " has a Hit marker")
			end
			for _, name in releaseClips do
				local has = false
				for _, e in lib[name].Events or {} do
					has = has or e.Name == "Release"
				end
				T.ok(has, fam .. "." .. name .. " has a Release marker")
			end
			-- M1 timing: the impact lands fast (anticipation -> snap)
			for _, name in { "Slash1", "Slash2", "Slash3", "Punch1", "Punch2", "Kick1" } do
				for _, e in lib[name].Events do
					if e.Name == "Hit" then
						T.ok(e.t <= 0.16, ("%s.%s Hit at %.2f is too late for an M1"):format(fam, name, e.t))
					end
				end
			end
		end
	end,

	combo_chain_end_matches_next_start = function(T, Loader)
		local A = Loader.requirePath("src/shared/Anim/AnimMath")
		for fam, lib in families(Loader) do
			for i = 1, 3 do
				local a, b = lib["Slash" .. i], lib["Slash" .. (i + 1)]
				local endPose = a.Keys[#a.Keys].Pose
				local startPose = b.Keys[1].Pose
				local ea, sb = A.PoseToBuffer(endPose), A.PoseToBuffer(startPose)
				-- the upper body of each hit starts where the previous one ended
				local m = 0
				for j = 2, 9 do
					for ch = 1, 3 do
						local o = (j - 1) * 6 + ch
						m = math.max(m, wrapDiff(ea[o], sb[o]))
					end
				end
				T.ok(m < 1, ("%s Slash%d -> Slash%d upper body does not chain (%.2f deg)"):format(fam, i, i + 1, m))
			end
		end
	end,

	kit_clip_references_resolve = function(T, Loader)
		local Kits = Loader.requirePath("src/shared/Kits")
		local libs = families(Loader)
		local kitLibs = kitClipFiles(Loader)
		local n = 0
		for _, kit in Kits.All() do
			local lib = libs[kit.Family]
			T.ok(lib ~= nil, kit.Id .. ": unknown family " .. tostring(kit.Family))
			for _, ab in kit.Abilities do
				if ab.Clip then
					n += 1
					local ok = (kitLibs[kit.Id] and kitLibs[kit.Id][ab.Clip]) or (lib and lib[ab.Clip])
					T.ok(ok ~= nil, ("%s.%s clip %s missing"):format(kit.Id, ab.Id, ab.Clip))
				end
			end
		end
		T.ok(n > 0, "no kit clips checked")
	end,

	joints_match_rig_contract = function(T, Loader)
		local Joints = Loader.requirePath("src/shared/Anim/Joints")
		local RigBuilder = Loader.requirePath("src/shared/Rigs/RigBuilder")
		local names = RigBuilder.GetJointNames()
		T.eq(#names, Joints.COUNT, "joint count")
		for i, n in names do
			T.eq(Joints.ALL[i], n, "joint order " .. i)
		end
		for i, n in Joints.ALL do
			local m = Joints.MirrorOf[n]
			T.eq(Joints.MirrorOf[m], n, "mirror is an involution for " .. n)
			T.eq(Joints.ALL[Joints.MirrorIndex[i]], m, "mirror index " .. n)
		end
		local upper = Joints.MaskArray("Upper")
		T.eq(upper[Joints.Index.Root], 0, "Upper mask excludes Root")
		T.eq(upper[Joints.Index.RightShoulder], 1, "Upper mask has arms")
		T.eq(upper[Joints.Index.LeftKnee], 0, "Upper mask excludes legs")
		local um = Joints.MaskArray("UpperMove")
		T.ok(um[Joints.Index.Waist] > 0.5 and um[Joints.Index.Waist] < 1, "UpperMove softens the waist")
		T.eq(Joints.MaskArray("Nope")[1], 1, "unknown mask -> Full")
		T.ok(not Joints.IsMask("Nope") and Joints.IsMask("Arms"), "IsMask")
	end,

	blending_math = function(T, Loader)
		local A = Loader.requirePath("src/shared/Anim/AnimMath")
		local a, b = A.NewBuffer(), A.NewBuffer()
		a[1], b[1] = 10, 30 -- Root rx
		a[2], b[2] = 170, -170 -- Root ry (wrap)
		a[4], b[4] = 0, 1 -- Root px
		local d = table.clone(a)
		A.BlendInto(d, b, 0)
		T.eq(d[1], 10, "w = 0 leaves dst")
		A.BlendInto(d, b, 1)
		T.eq(d[1], 30, "w = 1 copies src")
		T.near(d[4], 1, 1e-9, "w = 1 copies translation")
		d = table.clone(a)
		A.BlendInto(d, b, 0.5)
		T.near(d[1], 20, 1e-9, "midpoint")
		T.near(math.abs(d[2]), 180, 1e-9, "rotation blends the short way across +-180")
		T.near(d[4], 0.5, 1e-9, "translation midpoint")
		-- masks and driven
		local Joints = Loader.requirePath("src/shared/Anim/Joints")
		local c, s = A.NewBuffer(), A.NewBuffer()
		for i = 1, #s do
			s[i] = 5
		end
		A.BlendInto(c, s, 1, Joints.MaskArray("Upper"))
		T.eq(c[1], 0, "masked-out Root untouched")
		T.eq(c[(Joints.Index.Waist - 1) * 6 + 1], 5, "masked-in Waist blended")
		local drv = table.create(Joints.COUNT, false)
		drv[Joints.Index.Neck] = true
		local e = A.NewBuffer()
		A.BlendInto(e, s, 1, nil, drv)
		T.eq(e[(Joints.Index.Waist - 1) * 6 + 1], 0, "undriven joint untouched")
		T.eq(e[(Joints.Index.Neck - 1) * 6 + 1], 5, "driven joint blended")
		-- envelope
		T.near(A.Envelope(0, 0.1, 1, 0.1), 0, 1e-9, "envelope starts at 0")
		T.near(A.Envelope(0.5, 0.1, 1, 0.1), 1, 1e-9, "envelope full in the middle")
		T.near(A.Envelope(0.05, 0.1, 1, 0.1), 0.5, 1e-9, "envelope smoothstep midpoint")
		T.near(A.Envelope(1, 0.1, 0, 0.1), 0, 1e-9, "envelope ends at 0")
	end,

	channel_cframe_matches_pose_to_cframe = function(T, Loader)
		local A = Loader.requirePath("src/shared/Anim/AnimMath")
		local RigBuilder = Loader.requirePath("src/shared/Rigs/RigBuilder")
		local values = { { 30, -45, 60, 0.1, -0.2, 0.3 }, { -120, 10, -5 }, { 0, 179, 0 }, { 90, 0, 90 } }
		for _, v in values do
			local buf = A.PoseToBuffer({ Root = v })
			local mine = A.ChannelCFrame(buf, 1, 1.5)
			local ref = RigBuilder.PoseToCFrame(v, 1.5)
			local d = (mine.Position - ref.Position).Magnitude
			T.ok(d < 1e-4, "position mismatch " .. d)
			local rm = { mine:GetComponents() }
			local rr = { ref:GetComponents() }
			for i = 4, 12 do
				T.near(rm[i], rr[i], 1e-4, "rotation component " .. i)
			end
		end
	end,

	easing_and_spline_sampling = function(T, Loader)
		local A = Loader.requirePath("src/shared/Anim/AnimMath")
		local clip = A.Clip({
			Length = 1,
			Keys = {
				{ t = 0, Pose = { Neck = { 0, 0, 0 } } },
				{ t = 0.5, Ease = "Back", Dir = "Out", Pose = { Neck = { 90, 0, 0 } } },
				{ t = 1, Pose = { Neck = { 0, 0, 0 } } },
			},
		})
		local p = A.SamplePose(clip, 0.25)
		T.ok(p.Neck[1] > 45, "Back Out arrives fast (" .. p.Neck[1] .. ")")
		local overshoot = false
		for i = 1, 49 do
			local q = A.SamplePose(clip, i / 100)
			if q.Neck[1] > 90 then
				overshoot = true
			end
		end
		T.ok(overshoot, "Back Out overshoots before settling")
		-- smooth (no Ease) segments never overshoot their keys (monotone spline)
		local smooth = A.Clip({
			Length = 1,
			Keys = {
				{ t = 0, Pose = { Neck = { 0, 0, 0 } } },
				{ t = 0.3, Pose = { Neck = { 40, 0, 0 } } },
				{ t = 0.6, Pose = { Neck = { 45, 0, 0 } } },
				{ t = 1, Pose = { Neck = { 0, 0, 0 } } },
			},
		})
		for i = 0, 100 do
			local q = A.SamplePose(smooth, i / 100)
			T.ok(q.Neck[1] >= -1e-6 and q.Neck[1] <= 45 + 1e-6, "monotone spline stays within key values")
		end
		-- hold semantics: a joint missing from a later key holds its value
		local held = A.Clip({
			Length = 1,
			Keys = {
				{ t = 0, Pose = { Neck = { 10, 0, 0 }, Waist = { 5, 0, 0 } } },
				{ t = 1, Pose = { Neck = { 20, 0, 0 } } },
			},
		})
		T.eq(held.Keys[2].Pose.Waist[1], 5, "omitted joint holds")
		-- unknown joint / bad ease are rejected
		T.fails(function()
			A.Clip({ Length = 1, Keys = { { t = 0, Pose = { Elbow = { 0, 0, 0 } } } } })
		end, "unknown joint rejected")
		T.fails(function()
			A.Clip({ Length = 1, Keys = { { t = 0, Pose = {} }, { t = 0.5, Ease = "Wobbly", Pose = {} } } })
		end, "unknown ease rejected")
	end,

	spin_wraps_seamlessly = function(T, Loader)
		local A = Loader.requirePath("src/shared/Anim/AnimMath")
		local lib = families(Loader).Skeleton
		local spin = lib.Spin
		local endPose = A.SamplePose(spin, spin.Length)
		T.ok(wrapDiff(endPose.Root[2], 0) < 1e-3, "a 360 spin ends facing forward")
		local mid = A.SamplePose(spin, 0.33)
		T.ok(math.abs(mid.Root[2]) > 120, "mid-spin is turned around")
	end,

	mirror_and_phase_shift = function(T, Loader)
		local A = Loader.requirePath("src/shared/Anim/AnimMath")
		local pose = { LeftShoulder = { 10, 20, -30 }, Root = { 1, 2, 3, 0.4, 0.5, 0.6 } }
		local m = A.MirrorPose(pose)
		T.eq(m.RightShoulder[1], 10, "mirror keeps rx")
		T.eq(m.RightShoulder[2], -20, "mirror negates ry")
		T.eq(m.RightShoulder[3], 30, "mirror negates rz")
		T.eq(m.Root[4], -0.4, "mirror negates px")
		local mm = A.MirrorPose(m)
		T.eq(mm.LeftShoulder[3], -30, "mirror twice = identity")
		local lib = families(Loader).Skeleton
		local shifted = A.PhaseShift(lib.Walk, 0.5)
		for i = 0, 8 do
			local t = i / 8 * lib.Walk.Length
			local a = A.PoseToBuffer(A.SamplePose(shifted, t))
			local b = A.PoseToBuffer(A.SamplePose(lib.Walk, (t + lib.Walk.Length / 2) % lib.Walk.Length))
			T.ok(bufDiff(a, b) < 0.05, ("PhaseShift sample %d differs by %.3f"):format(i, bufDiff(a, b)))
		end
		local skR = A.SamplePose(lib.StrafeR, 0)
		local skL = A.SamplePose(lib.StrafeL, 0)
		-- both strafes plant the LEFT foot at phase 0: the left ankle is flat (no toe-off) in both
		T.ok(math.abs(skL.LeftAnkle[1]) < 25 and math.abs(skR.LeftAnkle[1]) < 25, "strafes plant the left foot at 0")
	end,

	locomotion_and_direction_weights = function(T, Loader)
		local A = Loader.requirePath("src/shared/Anim/AnimMath")
		for _, s in { 0, 0.5, 1, 2, 4, 8, 10, 12, 14, 16, 20, 40 } do
			local i, w, r = A.LocomotionWeights(s)
			T.near(i + w + r, 1, 1e-9, "locomotion weights sum to 1 at " .. s)
			T.ok(i >= 0 and w >= 0 and r >= 0, "non-negative weights")
		end
		local i0 = A.LocomotionWeights(0)
		T.eq(i0, 1, "idle at rest")
		local _, w6, r6 = A.LocomotionWeights(6)
		T.ok(w6 > 0.9 and r6 < 0.05, "walk at 6 studs/s")
		local _, _, r20 = A.LocomotionWeights(20)
		T.ok(r20 > 0.99, "run at 20 studs/s")
		for k = 0, 23 do
			local f, b, l, r = A.DirectionWeights(k * math.pi / 12)
			T.near(f + b + l + r, 1, 1e-9, "direction weights sum to 1")
		end
		local f0 = A.DirectionWeights(0)
		T.near(f0, 1, 1e-9, "forward")
		local _, _, l90 = A.DirectionWeights(math.pi / 2)
		T.near(l90, 1, 1e-9, "positive angle = left")
		local _, b180 = A.DirectionWeights(math.pi)
		T.near(b180, 1, 1e-9, "backwards")
		T.near(A.Cadence(10, 7), 10 / 7, 1e-9, "cadence = speed / stride")
		T.eq(A.Cadence(100, 7), 2.6, "cadence clamped")
	end,

	combo_and_windup = function(T, Loader)
		local A = Loader.requirePath("src/shared/Anim/AnimMath")
		local lib = families(Loader).Human
		local has = function(n)
			return lib[n] ~= nil
		end
		T.eq(A.ComboClipName("Slash1", 1, 4, has), "Slash1", "4-hit combo hit 1")
		T.eq(A.ComboClipName("Slash1", 2, 4, has), "Slash2", "4-hit combo hit 2")
		T.eq(A.ComboClipName("Slash1", 3, 4, has), "Slash3", "4-hit combo hit 3")
		T.eq(A.ComboClipName("Slash1", 4, 4, has), "Slash4", "4-hit combo finisher")
		T.eq(A.ComboClipName("Slash1", 3, 3, has), "Slash4", "3-hit combo ends on the finisher")
		T.eq(A.ComboClipName("Kick1", 3, 3, has), "Kick3", "kick finisher")
		T.eq(A.ComboClipName("Punch1", 2, 4, has), "Punch2", "punch 2")
		T.eq(A.ComboClipName("Cast", 2, 4, has), "Cast", "non-numbered clip unchanged")
		T.eq(A.ComboClipName("Slash1", 1, 1, has), "Slash1", "single hit unchanged")
		-- windup scaling lands the Release marker on the ability windup
		local summon = families(Loader).Skeleton.Summon
		local rel = A.EventTime(summon, "Release")
		local s = A.WindupSpeed(summon, 0.75)
		T.ok(s ~= nil, "Summon scales to a 0.75 s windup")
		if s then
			T.near(rel / s, 0.75, 1e-6, "Release lands on the windup")
		end
		T.eq(A.WindupSpeed(summon, 0), nil, "no windup -> nil")
		T.eq(A.WindupSpeed(families(Loader).Human.Shoot, 1.2), nil, "far-off windups play as authored")
	end,

	stance_ik_plants_feet = function(T, Loader)
		local A = Loader.requirePath("src/shared/Anim/AnimMath")
		local RigBuilder = Loader.requirePath("src/shared/Rigs/RigBuilder")
		local function find(list, name)
			for _, e in list do
				if e.Part.Name == name then
					return e.CFrame
				end
			end
		end
		for _, fam in { "Skeleton", "Human" } do
			local model = RigBuilder.BuildFromBlueprint({ Id = "T_" .. fam, Family = fam, Skeleton = fam, Palette = {}, Build = function() end }, {})
			local rest = RigBuilder.ComputeWorldCFrameList(model, {}, {})
			local pose = A.Stance(fam, { Drop = 0.25, Pitch = -10, Roll = 4, Yaw = -12, Left = { Z = -0.3 }, Right = { Z = 0.25, X = 0.1 } })
			local list = RigBuilder.ComputeWorldCFrameList(model, pose, {})
			for _, side in { "Left", "Right" } do
				local r0, r1 = find(rest, side .. "Foot"), find(list, side .. "Foot")
				local want = r0.Position + (if side == "Left" then Vector3.new(0, 0, -0.3) else Vector3.new(0.1, 0, 0.25))
				T.ok((r1.Position - want).Magnitude < 0.01, fam .. " " .. side .. " foot planted")
				local rx, _, rz = r1:ToEulerAnglesXYZ()
				T.ok(math.abs(rx) < 0.01 and math.abs(rz) < 0.01, fam .. " " .. side .. " foot flat")
			end
			-- arm reach
			local target = Vector3.new(0.4, 2.6, -0.8)
			local arm = A.Reach(fam, "Right", target)
			local list2 = RigBuilder.ComputeWorldCFrameList(model, arm, {})
			local hand = find(list2, "RightHand")
			T.ok((hand.Position - target).Magnitude < 0.01, fam .. " Reach puts the palm on the target")
			-- limb direction
			local v = A.Limb(Vector3.new(0, 0, -1))
			T.near(v[1], 90, 1e-3, "Limb forward = rx 90")
			T.near(v[3], 0, 1e-3, "Limb forward = rz 0")
		end
	end,

	aim_math_and_service_validation = function(T, Loader)
		local A = Loader.requirePath("src/shared/Anim/AnimMath")
		local cf = CFrame.new(0, 0, 0)
		local yaw, pitch = A.AimAngles(cf, Vector3.new(0, 0, 0), Vector3.new(0, 0, -10))
		T.near(yaw, 0, 1e-6, "ahead: yaw 0")
		T.near(pitch, 0, 1e-6, "ahead: pitch 0")
		yaw = A.AimAngles(cf, Vector3.new(0, 0, 0), Vector3.new(-10, 0, -10))
		T.near(yaw, 45, 1e-6, "left = positive yaw")
		local _, p2 = A.AimAngles(cf, Vector3.new(0, 0, 0), Vector3.new(0, 10, -10))
		T.near(p2, 45, 1e-6, "up = positive pitch")

		local AimService = Loader.requirePath("src/server/Services/AimService")
		local origin = Vector3.new(0, 5, 0)
		T.eq(AimService.Sanitize(origin, "x", 100), nil, "non-Vector3 rejected")
		T.eq(AimService.Sanitize(origin, Vector3.new(0 / 0, 0, 0), 100), nil, "NaN rejected")
		T.eq(AimService.Sanitize(origin, Vector3.new(1e7, 0, 0), 100), nil, "huge rejected")
		local p = AimService.Sanitize(origin, Vector3.new(0, 5, -50), 100)
		T.ok(p ~= nil and (p - Vector3.new(0, 5, -50)).Magnitude < 1e-6, "in-range point kept")
		local far = AimService.Sanitize(origin, Vector3.new(0, 5, -500), 100)
		T.ok(far ~= nil and math.abs((far - origin).Magnitude - 100) < 1e-4, "far point clamped to range")
		local state = {}
		local allowed = 0
		for _ = 1, 10 do
			if AimService.Allow(state, 0) then
				allowed += 1
			end
		end
		T.eq(allowed, AimService.BURST, "burst limit")
		T.ok(not AimService.Allow(state, 0.05), "no token after 50 ms")
		T.ok(AimService.Allow(state, 0.1), "refills at RATE per second")
		local sustained = 0
		local st2 = {}
		for i = 1, 100 do
			if AimService.Allow(st2, i * 0.02) then
				sustained += 1
			end
		end
		T.ok(sustained <= 2 * AimService.RATE + AimService.BURST + 1, "sustained rate <= 10 Hz (" .. sustained .. " in 2 s)")
		T.eq(AimService.Priority, 70, "AimService priority")
	end,

	compile_cache_and_events = function(T, Loader)
		local A = Loader.requirePath("src/shared/Anim/AnimMath")
		local lib = families(Loader).Human
		local c1 = A.Compile(lib.Walk, "Walk")
		T.ok(A.Compile(lib.Walk) == c1, "compile is cached per clip")
		local fired = {}
		A.EventsBetween(c1, -1e-6, lib.Walk.Length * 2.5, function(name, t)
			table.insert(fired, t)
		end)
		T.eq(#fired, 6, "loop markers repeat each cycle (window (a, b] over 2.5 cycles -> 6 steps)")
		local hits = 0
		local s1 = A.Compile(lib.Slash1)
		A.EventsBetween(s1, -1e-6, 0.11, function()
			hits += 1
		end)
		T.eq(hits, 0, "Hit not before its time")
		A.EventsBetween(s1, 0.11, 0.2, function()
			hits += 1
		end)
		T.eq(hits, 1, "Hit fires once in its window")
	end,
}
