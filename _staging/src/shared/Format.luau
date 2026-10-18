--!strict
-- Форматирование чисел и времени для интерфейса.

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

-- 999 -> "999", 1234 -> "1.23K", 15600 -> "15.6K", 2500000 -> "2.5M"
function Format.short(n: number): string
	if n ~= n then
		return "0"
	end
	local sign = if n < 0 then "-" else ""
	n = math.abs(n)
	if n < 1000 then
		return sign .. tostring(math.floor(n))
	end
	local tier = math.min(math.floor(math.log10(n) / 3), #SUFFIXES - 1)
	local scaled = n / 10 ^ (tier * 3)
	local text: string
	if scaled >= 100 then
		text = string.format("%d", math.floor(scaled))
	elseif scaled >= 10 then
		text = string.format("%.1f", math.floor(scaled * 10) / 10)
	else
		text = string.format("%.2f", math.floor(scaled * 100) / 100)
	end
	-- убрать хвостовые нули: "2.50" -> "2.5", "3.00" -> "3"
	text = string.gsub(text, "(%.%d-)0+$", "%1")
	text = string.gsub(text, "%.$", "")
	return sign .. text .. SUFFIXES[tier + 1]
end

-- 1234567 -> "1 234 567"
function Format.full(n: number): string
	local s = tostring(math.floor(math.abs(n)))
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1 ")))
	out = string.gsub(out, "^ ", "")
	return (if n < 0 then "-" else "") .. out
end

-- 75 -> "1:15", 3725 -> "1:02:05"
function Format.time(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

-- Русское множественное число: plural(5, "звезда", "звезды", "звёзд") -> "звёзд"
function Format.plural(n: number, one: string, few: string, many: string): string
	local a = math.abs(math.floor(n)) % 100
	local b = a % 10
	if a > 10 and a < 20 then
		return many
	elseif b == 1 then
		return one
	elseif b >= 2 and b <= 4 then
		return few
	end
	return many
end

-- 1.5 -> "x1.5", 2 -> "x2"
function Format.mult(m: number): string
	local text = string.format("%.2f", m)
	text = string.gsub(text, "(%.%d-)0+$", "%1")
	text = string.gsub(text, "%.$", "")
	return "x" .. text
end

-- 0.0012 -> "0.12%", 0.25 -> "25%"
function Format.percent(p: number): string
	local v = p * 100
	if v >= 10 then
		return string.format("%d%%", math.floor(v + 0.5))
	elseif v >= 1 then
		local t = string.format("%.1f", v)
		t = string.gsub(t, "%.0$", "")
		return t .. "%"
	end
	if v >= 0.1 then
		local t = string.format("%.2f", v)
		t = string.gsub(t, "(%.%d-)0+$", "%1")
		t = string.gsub(t, "%.$", "")
		return t .. "%"
	end
	-- совсем редкое: "1/2500"
	if p <= 0 then
		return "0%"
	end
	return "1/" .. Format.short(math.floor(1 / p + 0.5))
end

return Format
