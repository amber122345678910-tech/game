--!strict
-- Надписи в мире на языке игрока (src/shared/Loc.luau, «Надписи в мире»).
-- Таблички карты, табло, подписи над головой и ProximityPrompt по умолчанию английские, а исходник лежит
-- в атрибуте "Loc_<свойство>". Здесь клиент с другим языком подменяет свойство локально: изменение на клиенте
-- не уходит на сервер. Сервер меняет надпись вместе с атрибутом — подписка на атрибут и на само свойство
-- ставит перевод заново, в каком бы порядке они ни пришли.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loc = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Loc"))

local WorldText = {}

local PROPS = { "Text", "ActionText", "ObjectText" }

local hooked: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function apply(inst: Instance, prop: string)
	local text = Loc.worldText(inst, prop, Loc.lang())
	if text == nil then
		return
	end
	local anyInst: any = inst
	if anyInst[prop] ~= text then
		anyInst[prop] = text
	end
end

local function hook(inst: Instance)
	if hooked[inst] then
		return
	end
	local any = false
	for _, prop in PROPS do
		if typeof(inst:GetAttribute(Loc.attr(prop))) == "string" then
			any = true
		end
	end
	if not any then
		-- атрибут может появиться позже (сервер ставит текст после создания объекта)
		local conn: RBXScriptConnection? = nil
		conn = inst.AttributeChanged:Connect(function(name)
			if string.sub(name, 1, 4) == "Loc_" and conn then
				conn:Disconnect()
				hook(inst)
			end
		end)
		return
	end
	hooked[inst] = true
	for _, prop in PROPS do
		local attr = Loc.attr(prop)
		if typeof(inst:GetAttribute(attr)) == "string" then
			apply(inst, prop)
			inst:GetPropertyChangedSignal(prop):Connect(function()
				apply(inst, prop)
			end)
		end
		inst:GetAttributeChangedSignal(attr):Connect(function()
			apply(inst, prop)
		end)
	end
end

local function consider(inst: Instance)
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("ProximityPrompt") then
		hook(inst)
	end
end

function WorldText.start()
	-- английский — язык, на котором надписи уже стоят: подменять нечего
	if Loc.lang() == "en" then
		return
	end
	Workspace.DescendantAdded:Connect(consider)
	local all = Workspace:GetDescendants()
	for i, inst in all do
		consider(inst)
		if i % 2000 == 0 then
			task.wait() -- большая карта: не держать кадр
		end
	end
end

return WorldText
