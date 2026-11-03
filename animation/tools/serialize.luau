--!nocheck
-- Converts Roblox datatypes inside scene data into JSON-friendly values.
local S = {}

local function r4(x)
	return math.floor(x * 10000 + 0.5) / 10000
end

function S.color(c)
	return { r4(c.R), r4(c.G), r4(c.B) }
end

function S.v3(v)
	return { r4(v.X), r4(v.Y), r4(v.Z) }
end

function S.cf(cf)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return { r4(x), r4(y), r4(z), r4(r00), r4(r01), r4(r02), r4(r10), r4(r11), r4(r12), r4(r20), r4(r21), r4(r22) }
end

function S.colorSeq(seq)
	local out = {}
	for _, k in seq.Keypoints do
		table.insert(out, { r4(k.Time), S.color(k.Value) })
	end
	return out
end

function S.numSeq(seq)
	local out = {}
	for _, k in seq.Keypoints do
		table.insert(out, { r4(k.Time), r4(k.Value) })
	end
	return out
end

function S.elem(e)
	local o = {
		x = r4(e.x),
		y = r4(e.y),
		w = r4(e.w),
		h = r4(e.h),
		rot = r4(e.rot),
		c = S.color(e.color),
		a = r4(e.alpha),
		r = r4(e.radius),
	}
	if e.grad then
		o.g = {
			c = e.grad.color and S.colorSeq(e.grad.color) or nil,
			t = e.grad.transparency and S.numSeq(e.grad.transparency) or nil,
			rot = e.grad.rotation or 0,
		}
	end
	if e.group then
		o.grp = e.group
	end
	return o
end

function S.elems(list)
	local out = table.create(#list)
	for i, e in list do
		out[i] = S.elem(e)
	end
	return out
end

return S
