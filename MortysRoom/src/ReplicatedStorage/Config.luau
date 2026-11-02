--[[
	GAME CONFIG  —  change things here.

	MenuStyle  : which main menu you see.   "Cinematic" | "Cartoon" | "Monitor" | "VHS" | "Notebook"
	Graphics   : starting graphics preset.  "Moonlight" | "Sunrise" | "Cartoon" | "Portal" | "Noir"
	ShowStylePicker : the little bar at the bottom of the menu that lets you flip
	                  through the variants. Set to false when you have picked your favourite.
]]
local Config = {}

Config.Title = "RICK AND MORTY"
Config.Subtitle = "WAKE UP, MORTY"
Config.Version = "v0.1"

Config.MenuStyle = "Cinematic"
Config.Graphics = "Moonlight"
Config.ShowStylePicker = true

Config.MenuStyles = { "Cinematic", "Cartoon", "Monitor", "VHS", "Notebook" }
Config.GraphicsPresets = { "Moonlight", "Sunrise", "Cartoon", "Portal", "Noir" }

-- Default values of the Settings page
Config.Defaults = {
	Music = 0.6,
	Sound = 0.8,
	Sensitivity = 1.0,
	FOV = 72,
	Brightness = 0,
	HeadBob = true,
	ShowBody = true,
}

--[[
	SOUNDS
	All of these are public Roblox audio (licensed APM music, Pro Sound Effects
	library, official Roblox UI sounds, or files that ship with the Roblox client),
	so they play in any game. To use a different sound, paste another
	"rbxassetid://NUMBER" into Id. Volume is 0..1 (before the Settings sliders).
]]
Config.Sounds = {
	-- Menu music (each menu style picks one)
	MusicDreamy = { Id = "rbxassetid://9046435309", Volume = 0.45, Looped = true, Group = "Music" }, -- The Still, Sad Music Of Humanity (APM)
	MusicLofi = { Id = "rbxassetid://9043887091", Volume = 0.5, Looped = true, Group = "Music" }, -- Lo-fi Chill A (APM)
	MusicNight = { Id = "rbxassetid://9047105702", Volume = 0.5, Looped = true, Group = "Music" }, -- Light Dreamer (APM)
	MusicSynth = { Id = "rbxassetid://1837087135", Volume = 0.45, Looped = true, Group = "Music" }, -- Ambient Light (APM)

	-- Room
	Snore = { Id = "rbxassetid://9113862735", Volume = 0.55, Looped = true, Group = "SFX", RollOff = 26 }, -- Comic Snoring Male (PSE)
	Alarm = { Id = "rbxassetid://9113083860", Volume = 0.6, Looped = true, Group = "SFX", RollOff = 40 }, -- Alarm Beeps 1 (PSE)
	ClockTick = { Id = "rbxassetid://9116463812", Volume = 0.18, Looped = true, Group = "Ambience", RollOff = 18 }, -- Mantle Clock 1 (PSE)
	Crickets = { Id = "rbxassetid://9112764891", Volume = 0.3, Looped = true, Group = "Ambience" }, -- Crickets Night 3 (PSE)
	Birds = { Id = "rbxassetid://9119383684", Volume = 0.3, Looped = true, Group = "Ambience" }, -- Sonoma Morning Birds (PSE)
	PortalHum = { Id = "rbxassetid://9114340342", Volume = 0.25, Looped = true, Group = "Ambience" }, -- Energy Pass By Sci Fi (PSE)

	-- Waking up
	Gasp = { Id = "rbxassetid://9114555214", Volume = 0.5, Group = "SFX" }, -- Gasp Deep Inhale And Exhale (PSE)
	Cloth = { Id = "rbxassetid://9113824106", Volume = 0.6, Group = "SFX" }, -- Cloth Movement 21 (PSE)
	GetUp = { Id = "rbxasset://sounds/action_get_up.mp3", Volume = 0.5, Group = "SFX" }, -- ships with Roblox
	Switch = { Id = "rbxassetid://9116286721", Volume = 0.6, Group = "SFX" }, -- Light Switch Flip (PSE)
	Click = { Id = "rbxassetid://9119717523", Volume = 0.5, Group = "SFX" }, -- Switch Click (PSE)
	Whoosh = { Id = "rbxassetid://9126229255", Volume = 0.45, Group = "SFX" }, -- Whoosh By Fast Airy (PSE)
	Portal = { Id = "rbxassetid://9114340342", Volume = 0.5, Group = "SFX" }, -- Energy Pass By Sci Fi (PSE)

	-- Menu UI (official Roblox UI sounds)
	UIHover = { Id = "rbxassetid://10066931761", Volume = 0.35, Group = "SFX" },
	UIClick = { Id = "rbxassetid://15675032796", Volume = 0.6, Group = "SFX" },
	UIBack = { Id = "rbxassetid://10066914500", Volume = 0.5, Group = "SFX" },
	UISwoosh = { Id = "rbxassetid://15675024286", Volume = 0.4, Group = "SFX" },
	UITick = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 0.5, Group = "SFX" }, -- ships with Roblox
}

return Config
