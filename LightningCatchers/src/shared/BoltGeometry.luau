--!strict
-- Форма молнии: зигзаг методом "смещения середины" плюс 1–3 ответвления.
-- Чистая функция от seed — один и тот же удар выглядит одинаково везде (и в превью-рендере).

local Prng = require(script.Parent.Prng)
local Geom = require(script.Parent.Geom)

export type Segment = {
	A: Vector3,
	B: Vector3,
	Width: number,
	Branch: boolean,
}

local BoltGeometry = {}

local function displace(points: { Vector3 }, rng: Prng.Prng, amount: number, depth: number): { Vector3 }
	local pts = points
	local amt = amount
	for _ = 1, depth do
		local out = { pts[1] }
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local mid = (a + b) / 2
			local dir = (b - a)
			-- смещение перпендикулярно направлению
			local perp = dir:Cross(Vector3.new(rng:range(-1, 1), rng:range(-0.2, 0.2), rng:range(-1, 1)))
			if perp.Magnitude > 1e-3 then
				mid += perp.Unit * rng:range(-amt, amt)
			end
			table.insert(out, mid)
			table.insert(out, b)
		end
		pts = out
		amt *= 0.55
	end
	return pts
end

-- from — точка в туче, to — точка удара на земле. detail 3..5 (больше — больше сегментов)
function BoltGeometry.build(seed: number, from: Vector3, to: Vector3, detail: number?): { Segment }
	local rng = Prng.new(seed)
	local len = (to - from).Magnitude
	local d = math.clamp(detail or 4, 2, 6)
	local main = displace({ from, to }, rng, len * 0.12, d)
	local segs: { Segment } = {}
	local n = #main
	for i = 1, n - 1 do
		-- к земле молния толще и ярче
		local t = i / n
		table.insert(segs, { A = main[i], B = main[i + 1], Width = 0.35 + 0.45 * t, Branch = false })
	end
	-- ответвления
	local branches = rng:int(1, 3)
	for _ = 1, branches do
		local startIdx = rng:int(math.max(2, math.floor(n * 0.15)), math.max(2, math.floor(n * 0.7)))
		local start = main[startIdx]
		local remaining = (to - start)
		local dir = (remaining.Unit + Vector3.new(rng:range(-0.9, 0.9), rng:range(-0.1, 0.3), rng:range(-0.9, 0.9))).Unit
		local blen = remaining.Magnitude * rng:range(0.25, 0.45)
		local bpts = displace({ start, start + dir * blen }, rng, blen * 0.15, math.max(2, d - 1))
		for i = 1, #bpts - 1 do
			table.insert(segs, { A = bpts[i], B = bpts[i + 1], Width = 0.22, Branch = true })
		end
	end
	return segs
end

-- CFrame и длина цилиндра-сегмента (ось цилиндра Roblox — X)
function BoltGeometry.segmentCFrame(s: Segment): (CFrame, number)
	return Geom.axisCFrame(s.A, s.B)
end

return BoltGeometry
