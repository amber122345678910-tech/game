--!strict
-- Player-facing text of the Eclipse Sans kit (client kit src/client/Kits/EclipseSans.luau). Lune-safe.
-- Keys: "eclipse.*". World popups are short and uppercase (Undertale style); "*" lines are flavour subtitles.
return {
	-- Total Eclipse subtitles (shown once when the light goes out)
	["eclipse.dark.human"] = { en = "* The sun goes out.", ru = "* Солнце гаснет." },
	["eclipse.dark.self"] = { en = "* The dark walks with you.", ru = "* Тьма идёт с тобой." },
	-- Rift Trap
	["eclipse.trap.sprung"] = { en = "PULLED THROUGH", ru = "ЗАТЯНУТ" },
	["eclipse.trap.placed"] = { en = "RIFT {1}/{2}", ru = "РАЗЛОМ {1}/{2}" },
	-- Void Karma (a human near him loses ult)
	["eclipse.drain"] = { en = "ULT DRAINING", ru = "УЛЬТА УТЕКАЕТ" },
}
