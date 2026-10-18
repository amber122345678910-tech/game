--!nocheck
-- Подсчёт деталей карты по группам (для бюджета телефонов).
-- lune run tools/preview/count_parts.luau src/map/Map.rbxmx [глубина]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local file = process.args[1] or "src/map/Map.rbxmx"
local depth = tonumber(process.args[2]) or 3
local root = roblox.deserializeModel(fs.readFile(file))[1]
local byName = {}
local function count(inst)
	local n = 0
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end
local function walk(inst, path, level)
	for _, c in inst:GetChildren() do
		local p = path .. "/" .. c.Name
		if level < depth and (c:IsA("Model") or c:IsA("Folder")) then
			walk(c, p, level + 1)
		elseif c:IsA("Model") or c:IsA("Folder") then
			local key = path .. "/" .. c.Name
			byName[key] = (byName[key] or 0) + count(c)
		else
			byName[path .. "/<parts>"] = (byName[path .. "/<parts>"] or 0) + (if c:IsA("BasePart") then 1 else 0)
		end
	end
end
walk(root, "Map", 1)
local keys = {}
for k in byName do
	table.insert(keys, k)
end
table.sort(keys)
local agg = {}
for _, k in keys do
	local short = string.gsub(k, "_%d+$", "_N")
	agg[short] = (agg[short] or 0) + byName[k]
end
local list = {}
for k, v in agg do
	table.insert(list, { k, v })
end
table.sort(list, function(a, b)
	return a[2] > b[2]
end)
for i = 1, math.min(#list, 60) do
	print(string.format("%6d  %s", list[i][2], list[i][1]))
end
print("total", count(root))
