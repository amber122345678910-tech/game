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
	Language = "RU", -- "RU" or "EN" (dialogues and hints)
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

	-- Story: kitchen / explosions
	Explosion = { Id = "rbxassetid://9114554766", Volume = 0.8, Group = "SFX" }, -- Gas Fire Explosion 4 (PSE)
	ExplosionBig = { Id = "rbxassetid://9114224800", Volume = 0.9, Group = "SFX" }, -- Earthquake Explosion 2 (PSE)
	ExplosionSmall = { Id = "rbxassetid://9117895914", Volume = 0.9, Group = "SFX" }, -- Pressure Blast 2 (PSE)
	Electric = { Id = "rbxassetid://9116273112", Volume = 0.5, Group = "SFX" }, -- Electrical Bursts 19 (PSE)
	Tinnitus = { Id = "rbxassetid://9069161602", Volume = 0.5, Group = "Music" }, -- Ear Ringing (Fade)
	OverheatBeep = { Id = "rbxassetid://9125387654", Volume = 0.35, Looped = true, Group = "SFX", RollOff = 20 }, -- High Pitch Fast Beeps (PSE)
	Sizzle = { Id = "rbxassetid://9117065841", Volume = 0.35, Looped = true, Group = "SFX", RollOff = 20 }, -- Neon Transformer 6 (PSE)
	Clink = { Id = "rbxassetid://9116673068", Volume = 0.12, Group = "SFX" }, -- Metal Impact Clanky (PSE)
	Burp = { Id = "rbxassetid://9114171726", Volume = 0.5, Group = "SFX" }, -- Drink Burp 2 (PSE)

	-- Story: glitches
	Glitch1 = { Id = "rbxassetid://9114478791", Volume = 0.4, Group = "SFX" }, -- Flashing Triangle Tone (PSE)
	Glitch2 = { Id = "rbxassetid://9119588836", Volume = 0.4, Group = "SFX" }, -- Static Rough 3 (PSE)
	Glitch3 = { Id = "rbxassetid://9126077092", Volume = 0.35, Group = "SFX" }, -- Synth Static Feedback (PSE)
	StaticLoop = { Id = "rbxassetid://9126159606", Volume = 0.35, Looped = true, Group = "SFX" }, -- Video Static Distortion (PSE)

	-- Story: garage + flight
	LabHum = { Id = "rbxassetid://9112889082", Volume = 0.25, Looped = true, Group = "Ambience" }, -- Transformer Hum 1 (PSE)
	Bubbles = { Id = "rbxassetid://9114492495", Volume = 0.3, Looped = true, Group = "Ambience", RollOff = 30 }, -- Bubbling Water (PSE)
	GarageDoor = { Id = "rbxassetid://9113910422", Volume = 0.5, Group = "SFX", RollOff = 60 }, -- Conveyor Belt 2 (PSE)
	UfoHum = { Id = "rbxassetid://9125515917", Volume = 0.5, Looped = true, Group = "SFX", RollOff = 80 }, -- Resonant Humming (PSE)
	Takeoff = { Id = "rbxassetid://9113081793", Volume = 0.6, Group = "SFX" }, -- Airy Whoosh Blast 4 (PSE)
	Warp = { Id = "rbxassetid://9120054806", Volume = 0.7, Group = "SFX" }, -- Time Travel Fly By 3 (PSE)
	Reentry = { Id = "rbxassetid://9118747525", Volume = 0.6, Looped = true, Group = "SFX" }, -- Interior Wind Turbo (PSE)
	MetalCrash = { Id = "rbxassetid://9116546593", Volume = 0.9, Group = "SFX", RollOff = 300 }, -- Metal Crash 4 (PSE)
	Wind = { Id = "rbxassetid://9114057128", Volume = 0.35, Looped = true, Group = "Ambience" }, -- Desert Wind Gusts 2 (PSE)

	-- Story: radar, titan, entity
	RadarPing = { Id = "rbxassetid://9125397532", Volume = 0.4, Group = "SFX" }, -- Blip Tone (PSE)
	Thruster = { Id = "rbxassetid://9112780561", Volume = 0.9, Looped = true, Group = "SFX", RollOff = 500 }, -- Fire Whoosh 1 (PSE)
	RobotStomp = { Id = "rbxassetid://9116478399", Volume = 1, Group = "SFX", RollOff = 600 }, -- Massive Footstep Impact (PSE)
	Servo = { Id = "rbxassetid://9119019622", Volume = 0.6, Group = "SFX", RollOff = 400 }, -- Servo Whir (PSE)
	RobotVoice = { Id = "rbxassetid://9118560128", Volume = 0.8, Group = "SFX", RollOff = 600 }, -- Robot Voice Low Growls (PSE)
	Charge = { Id = "rbxassetid://9125975059", Volume = 0.7, Group = "SFX", RollOff = 600 }, -- Energy Charge Up (PSE)
	ChargeLong = { Id = "rbxassetid://9126062181", Volume = 0.8, Group = "SFX", RollOff = 600 }, -- Building Burst (PSE)
	Laser = { Id = "rbxassetid://9118787127", Volume = 1, Group = "SFX", RollOff = 800 }, -- Sci-Fi Weapon 6 (PSE)
	SonicBoom = { Id = "rbxassetid://9120769331", Volume = 0.9, Group = "SFX", RollOff = 800 }, -- Sonic Boom Low Impact (PSE)
	Boom = { Id = "rbxassetid://9125484359", Volume = 1, Group = "SFX" }, -- Deep Reverberant Booms (PSE)
	Roar = { Id = "rbxassetid://9113985604", Volume = 1, Group = "SFX", RollOff = 1000 }, -- Creature Roar Mix (PSE)
	RoarDeep = { Id = "rbxassetid://9114628818", Volume = 1, Group = "SFX", RollOff = 1000 }, -- Goliath Deep Growl (PSE)
	Drone = { Id = "rbxassetid://9112775175", Volume = 0.4, Looped = true, Group = "Ambience" }, -- Eerie Ambience 1 (PSE)
	Rumble = { Id = "rbxassetid://9125351660", Volume = 0.45, Looped = true, Group = "Ambience" }, -- Weird Rumbling (PSE)
	Thud = { Id = "rbxassetid://9113476681", Volume = 0.8, Group = "SFX" }, -- Body Fall Master 40 (PSE)
	BodyWhoosh = { Id = "rbxassetid://9113077334", Volume = 0.8, Group = "SFX" }, -- Air Whoosh Heavy (PSE)
	MuffledBoom = { Id = "rbxassetid://9125392715", Volume = 0.8, Group = "SFX" }, -- Rocks Drop Interior Muffled (PSE)
	DustFall = { Id = "rbxassetid://9113221127", Volume = 0.3, Group = "SFX" }, -- Avalanche Rolling 6 (PSE)

	-- The sound you asked for when Titan Speakerman shows up
	TitanTheme = { Id = "rbxassetid://111681527595415", Volume = 0.8, Group = "Music" },

	-- Story music (APM, Roblox licensed library)
	MusicBreakfast = { Id = "rbxassetid://9045800615", Volume = 0.35, Looped = true, Group = "Music" }, -- Quirky Turkey (a)
	MusicFlight = { Id = "rbxassetid://1839633919", Volume = 0.45, Looped = true, Group = "Music" }, -- Into The Future
	MusicEerie = { Id = "rbxassetid://1836590380", Volume = 0.45, Looped = true, Group = "Music" }, -- Desert Plains (Ambient)
	MusicDread = { Id = "rbxassetid://1847064374", Volume = 0.45, Looped = true, Group = "Music" }, -- Scary Atmosphere (Drones)
	MusicAction = { Id = "rbxassetid://9042643029", Volume = 0.5, Looped = true, Group = "Music" }, -- Digital Underworld
	MusicBunker = { Id = "rbxassetid://9042153803", Volume = 0.45, Looped = true, Group = "Music" }, -- Piano Reflections

	-- Menu UI (official Roblox UI sounds)
	UIHover = { Id = "rbxassetid://10066931761", Volume = 0.35, Group = "SFX" },
	UIClick = { Id = "rbxassetid://15675032796", Volume = 0.6, Group = "SFX" },
	UIBack = { Id = "rbxassetid://10066914500", Volume = 0.5, Group = "SFX" },
	UISwoosh = { Id = "rbxassetid://15675024286", Volume = 0.4, Group = "SFX" },
	UITick = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 0.5, Group = "SFX" }, -- ships with Roblox
}

return Config
