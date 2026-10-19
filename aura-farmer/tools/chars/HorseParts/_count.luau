local build = require("../Horse")
local rig = build({})
local per = {}
for _, p in rig.visuals do
	local b = p.Parent.Name
	per[b] = (per[b] or 0) + 1
end
local keys = {}
for k in per do table.insert(keys, k) end
table.sort(keys, function(a, b) return per[a] > per[b] end)
local s = {}
for _, k in keys do table.insert(s, k .. "=" .. per[k]) end
print(#rig.visuals, table.concat(s, " "))
