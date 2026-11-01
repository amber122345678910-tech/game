--!strict
-- ThemeService: holds the active menu theme and HUD style and announces changes. Lune-safe at require
-- time (only requires Themes and Shared/Util/Signal; a tiny local signal is used if Signal is missing).
--
--   ThemeService.Current() -> Theme
--   ThemeService.Set(id: string) -> boolean            false if the id is unknown; fires Changed(new, old)
--   ThemeService.Changed : Signal<(Theme, Theme)>
--   ThemeService.HudStyle() -> HudStyle
--   ThemeService.SetHudStyle(id: string) -> boolean    fires HudChanged(new, old)
--   ThemeService.HudChanged : Signal<(HudStyle, HudStyle)>
--   ThemeService.Ids() / ThemeService.HudIds() -> { string }
--   ThemeService.Next(step: number?) -> Theme          cycles to the next/previous theme (Style Lab, Gallery)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Themes = require(script.Parent.Themes)

type Theme = Themes.Theme
type HudStyle = Themes.HudStyle

export type SignalLike = {
	Connect: (self: any, fn: (...any) -> ()) -> any,
	Once: (self: any, fn: (...any) -> ()) -> any,
	Fire: (self: any, ...any) -> (),
	Wait: (self: any) -> ...any,
	DisconnectAll: (self: any) -> (),
}

-- Fallback signal (used only when Shared/Util/Signal is unavailable) -----------------------------
local function fallbackSignal(): SignalLike
	local handlers: { { fn: (...any) -> (), once: boolean, connected: boolean } } = {}
	local self = {}
	function self:Connect(fn: (...any) -> ())
		local entry = { fn = fn, once = false, connected = true }
		table.insert(handlers, entry)
		return {
			Connected = true,
			Disconnect = function(conn: any)
				entry.connected = false
				conn.Connected = false
			end,
		}
	end
	function self:Once(fn: (...any) -> ())
		local entry = { fn = fn, once = true, connected = true }
		table.insert(handlers, entry)
		return {
			Connected = true,
			Disconnect = function(conn: any)
				entry.connected = false
				conn.Connected = false
			end,
		}
	end
	function self:Fire(...: any)
		local snapshot = table.clone(handlers)
		for _, entry in snapshot do
			if entry.connected then
				if entry.once then
					entry.connected = false
				end
				entry.fn(...)
			end
		end
		for i = #handlers, 1, -1 do
			if not handlers[i].connected then
				table.remove(handlers, i)
			end
		end
	end
	function self:Wait(): ...any
		local thread = coroutine.running()
		self:Once(function(...: any)
			task.spawn(thread, ...)
		end)
		return coroutine.yield()
	end
	function self:DisconnectAll()
		for _, entry in handlers do
			entry.connected = false
		end
		table.clear(handlers)
	end
	return self :: any
end

local function newSignal(): SignalLike
	local ok, Signal = pcall(function()
		local shared = ReplicatedStorage:WaitForChild("Shared")
		local util = (shared :: any):FindFirstChild("Util")
		local module = util and util:FindFirstChild("Signal")
		if not module then
			error("no Util/Signal")
		end
		return require(module) :: any
	end)
	if ok and type(Signal) == "table" and type(Signal.new) == "function" then
		return Signal.new()
	end
	return fallbackSignal()
end

local ThemeService = {}

local current: Theme = Themes.Get(Themes.Default)
local currentHud: HudStyle = Themes.GetHud(Themes.DefaultHud)

ThemeService.Changed = newSignal()
ThemeService.HudChanged = newSignal()

function ThemeService.Current(): Theme
	return current
end

function ThemeService.Set(id: string): boolean
	if not Themes.Has(id) then
		return false
	end
	local old = current
	if old.Id == id then
		return true
	end
	current = Themes.Get(id)
	ThemeService.Changed:Fire(current, old)
	return true
end

function ThemeService.Next(step: number?): Theme
	local ids = Themes.Ids
	local index = table.find(ids, current.Id) or 1
	local n = #ids
	local nextIndex = ((index - 1 + (step or 1)) % n + n) % n + 1
	ThemeService.Set(ids[nextIndex])
	return current
end

function ThemeService.HudStyle(): HudStyle
	return currentHud
end

function ThemeService.SetHudStyle(id: string): boolean
	if Themes.HudStyles[id] == nil then
		return false
	end
	local old = currentHud
	if old.Id == id then
		return true
	end
	currentHud = Themes.GetHud(id)
	ThemeService.HudChanged:Fire(currentHud, old)
	return true
end

function ThemeService.Ids(): { string }
	return table.clone(Themes.Ids)
end

function ThemeService.HudIds(): { string }
	return table.clone(Themes.HudIds)
end

return ThemeService
