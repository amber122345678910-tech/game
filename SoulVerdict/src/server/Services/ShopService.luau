--!strict
-- ShopService (P72): purchases with earned G only (no Robux anywhere) + the daily shop clock.
-- Rules live in Shared/Progression/Shop (catalog, deterministic daily rotation, featured -20 %, CheckBuy).
-- Today's shop reaches clients inside the profile view (Profile.ShopToday, built by DataService); at UTC
-- midnight every profile is re-replicated and players get Notify "prog.notify.shopRestock".
--
-- API: Buy(player, data) -> (ok, errKey?, errArgs?)   RequestService "Buy" handler:
--          data = {kind = "Kit"|"Skin", kitId, skinId?}; kits need G + LV (Unlock.Level), skins need the kit,
--          Mastery skins are never sold; price = today's price (featured discount) or the full price.
--          Success: Notify "prog.notify.bought" / "prog.notify.boughtKit" {name} (style "Success") + early save.
--      Today() -> DailyShop

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net")) :: any
local Kits = require(Shared:WaitForChild("Kits")) :: any
local Shop = require(Shared:WaitForChild("Progression"):WaitForChild("Shop")) :: any

local ShopService = {}
ShopService.Priority = 72

local CHECK_INTERVAL = 20

local DataService: any = nil
local RequestService: any = nil

local function tryService(name: string): any
	local module = (script.Parent :: Instance):FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			return result
		end
	end
	return nil
end

local function textFor(player: Player, localized: any): string
	if RequestService and type(RequestService.TextFor) == "function" then
		local ok, s = pcall(RequestService.TextFor, player, localized)
		if ok and type(s) == "string" then
			return s
		end
	end
	return if type(localized) == "table" then (localized.en or "") else tostring(localized)
end

local function notify(player: Player, key: string, args: { any }?, style: string?)
	if player.Parent then
		pcall(Net.Server.Fire, "Notify", player, key, args, style)
	end
end

function ShopService.Today(): any
	return Shop.Daily(Shop.Day(os.time()))
end

function ShopService.Buy(player: Player, data: any): (boolean, string?, { any }?)
	local item = Shop.ParseItem(data)
	if item == nil then
		return false, "prog.err.badRequest"
	end
	if DataService == nil then
		return false, "prog.err.notReady"
	end
	local profile = DataService.Get(player)
	if profile == nil then
		return false, "prog.err.notReady"
	end
	local day = Shop.Day(os.time())
	local ok, errKey, price = Shop.CheckBuy(profile, item, day)
	if not ok then
		local args: { any }? = nil
		if errKey == "prog.err.gold" then
			args = { price or 0 }
		elseif errKey == "prog.err.level" then
			local kit = Kits.Get(item.KitId)
			args = { if kit and kit.Unlock.Level then kit.Unlock.Level else 1 }
		end
		return false, errKey, args
	end
	local applied = false
	DataService.Update(player, function(p: any)
		-- re-check inside the update (nothing can interleave, but stay defensive)
		local stillOk, _, finalPrice = Shop.CheckBuy(p, item, day)
		if stillOk and finalPrice then
			Shop.Apply(p, item, finalPrice)
			applied = true
		end
	end)
	if not applied then
		return false, "prog.err.notReady"
	end
	if type(DataService.RequestSave) == "function" then
		DataService.RequestSave(player)
	end
	local kit = Kits.Get(item.KitId)
	if item.Kind == "Kit" then
		notify(player, "prog.notify.boughtKit", { textFor(player, kit.Name) }, "Success")
	else
		local skin = Kits.Skin(item.KitId, item.SkinId)
		notify(player, "prog.notify.bought", { textFor(player, skin.Name) }, "Success")
	end
	return true
end

function ShopService.Init()
	DataService = tryService("DataService")
	RequestService = tryService("RequestService")
end

function ShopService.Start()
	task.spawn(function()
		local day = Shop.Day(os.time())
		while true do
			task.wait(CHECK_INTERVAL)
			local today = Shop.Day(os.time())
			if today ~= day then
				day = today
				Shop.Daily(today) -- warm the cache once
				for _, player in Players:GetPlayers() do
					if DataService and DataService.Get(player) then
						DataService.Replicate(player)
						notify(player, "prog.notify.shopRestock", nil, "Info")
					end
				end
			end
		end
	end)
end

return ShopService
