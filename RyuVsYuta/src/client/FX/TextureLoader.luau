--!strict
-- Предзагрузка качественных текстур из Магазина Roblox. Пока (или если) они не загрузились —
-- везде используются встроенные текстуры клиента, сцена от этого не ломается.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Textures = require(ReplicatedStorage:WaitForChild("Cutscene"):WaitForChild("Textures"))

local TextureLoader = {}

local loaded: { [string]: boolean } = {}
local done = false
local waiters: { () -> () } = {}

function TextureLoader.start()
	task.spawn(function()
		local ids: { string } = {}
		local keyOf: { [string]: string } = {}
		for key, tex in Textures.hq do
			table.insert(ids, tex.id)
			keyOf[tex.id] = key
		end
		local ok, err = pcall(function()
			ContentProvider:PreloadAsync(ids, function(contentId: string, status: Enum.AssetFetchStatus)
				local key = keyOf[contentId]
				if key and status == Enum.AssetFetchStatus.Success then
					loaded[key] = true
				end
			end)
		end)
		if not ok then
			warn("[Cutscene] texture preload failed: " .. tostring(err))
		end
		local missing = {}
		for key in Textures.hq do
			if not loaded[key] then
				table.insert(missing, key)
			end
		end
		if #missing > 0 then
			warn("[Cutscene] textures not loaded, using built-in: " .. table.concat(missing, ", "))
		end
		done = true
		for _, fn in waiters do
			task.spawn(fn)
		end
		table.clear(waiters)
	end)
end

-- Текстура по ключу Textures.hq: качественная, если загрузилась, иначе встроенная
function TextureLoader.get(key: string): string
	local tex = Textures.hq[key]
	if not tex then
		return Textures.smoke
	end
	return if loaded[key] then tex.id else tex.fallback
end

function TextureLoader.isHQ(key: string): boolean
	return loaded[key] == true
end

function TextureLoader.onReady(fn: () -> ())
	if done then
		task.spawn(fn)
	else
		table.insert(waiters, fn)
	end
end

return TextureLoader
