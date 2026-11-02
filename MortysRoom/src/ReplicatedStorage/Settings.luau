-- Player settings for this session (client side).
local Config = require(script.Parent.Config)

local Settings = {}
Settings.Values = table.clone(Config.Defaults)
Settings.Values.Graphics = Config.Graphics
Settings.Values.MenuStyle = Config.MenuStyle

local changed = Instance.new("BindableEvent")
Settings.Changed = changed.Event

function Settings.Get(key: string): any
	return Settings.Values[key]
end

function Settings.Set(key: string, value: any)
	if Settings.Values[key] == value then
		return
	end
	Settings.Values[key] = value
	changed:Fire(key, value)
end

return Settings
