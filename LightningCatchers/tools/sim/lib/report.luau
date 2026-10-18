--!nocheck
-- Collects everything the run finds: runtime errors (with stack traces), infinite yields, unknown members,
-- bad property values, harness gaps, warnings and scenario checks. Identical entries are merged with counts.
local fs = require("@lune/fs")

local Report = {}

-- category -> { title, severity ("error"|"warning"|"info") }
Report.Categories = {
	runtime = { "Runtime errors (uncaught, in game threads/connections)", "error" },
	caught = { "Errors caught by game code and printed with warn()", "error" },
	member = { "Unknown members (property/method/event that does not exist on the class)", "error" },
	proptype = { "Bad property values (wrong type / read-only / invalid)", "error" },
	yield = { "Infinite yields", "error" },
	remote = { "Remote / DataStore payload problems", "error" },
	check = { "Scenario checks that failed", "error" },
	emu = { "HARNESS GAPS: engine API the game used that the sim does not emulate", "error" },
	member_probe = { "Unknown members read inside pcall (deliberate probes, informational)", "info" },
	deprecated = { "Deprecated API used", "warning" },
	nan = { "NaN/inf written into a property", "warning" },
	warn = { "Other warn() output from game code", "warning" },
	note = { "Notes", "info" },
}
Report.Order = { "runtime", "caught", "member", "proptype", "yield", "remote", "check", "emu", "nan", "deprecated", "warn", "member_probe", "note" }

local entries = {} -- key -> entry
local order = {}
Report.entries = entries
Report.log = {}
Report.ROOT = "/home/user/game/LightningCatchers/"

local SIM_DIR = "tools/sim/"

-- Build a stack trace (list of frames) starting at `level` of the current thread or of `co`
-- Frames are { src, line, name }. Harness and C frames are dropped, but we remember if any existed.
function Report.frames(co, level)
	local out = {}
	local i = level or 1
	while i < 200 do
		local s, l, n
		if co then
			s, l, n = debug.info(co, i, "sln")
		else
			s, l, n = debug.info(i + 1, "sln")
		end
		if s == nil then
			break
		end
		if s ~= "[C]" and not string.find(s, SIM_DIR, 1, true) and not string.find(s, "/tools/sim", 1, true) then
			table.insert(out, { src = s, line = l, name = n })
		end
		i += 1
	end
	return out
end

function Report.formatFrames(frames, max)
	local lines = {}
	for i, f in frames do
		if max and i > max then
			table.insert(lines, string.format("      ... %d more", #frames - max))
			break
		end
		local fn = if f.name and f.name ~= "" then " in " .. f.name else ""
		table.insert(lines, string.format("      %s:%d%s", f.src, f.line or 0, fn))
	end
	return table.concat(lines, "\n")
end

local function topKey(frames, n)
	local parts = {}
	for i = 1, math.min(n, #frames) do
		table.insert(parts, frames[i].src .. ":" .. tostring(frames[i].line))
	end
	return table.concat(parts, "|")
end

-- Strip mlua decorations from error messages
function Report.cleanMessage(msg)
	local s = tostring(msg)
	s = string.gsub(s, "^runtime error: ", "")
	local cut = string.find(s, "\nstack traceback:", 1, true)
	if cut then
		s = string.sub(s, 1, cut - 1)
	end
	cut = string.find(s, "\n%[Stack Begin%]")
	if cut then
		s = string.sub(s, 1, cut - 1)
	end
	return s
end

Report.now = function()
	return 0
end

-- Add an entry. realm: string label. frames: list (may be empty). extra: optional detail string
function Report.add(category, realm, message, frames, extra)
	message = Report.cleanMessage(message)
	frames = frames or {}
	local key = category .. "\0" .. message .. "\0" .. topKey(frames, 3)
	local e = entries[key]
	if not e then
		e = {
			category = category,
			message = message,
			frames = frames,
			count = 0,
			realms = {},
			realmOrder = {},
			first = Report.now(),
			extra = extra,
		}
		entries[key] = e
		table.insert(order, e)
	end
	e.count += 1
	if realm and not e.realms[realm] then
		e.realms[realm] = true
		table.insert(e.realmOrder, realm)
	end
	return e
end

-- After entries were removed from Report.entries, drop them from the render order too
function Report.rebuildOrder()
	local live = {}
	for _, e in entries do
		live[e] = true
	end
	local keep = {}
	for _, e in order do
		if live[e] then
			table.insert(keep, e)
		end
	end
	table.clear(order)
	for _, e in keep do
		table.insert(order, e)
	end
end

function Report.count(category)
	local n = 0
	for _, e in order do
		if e.category == category then
			n += 1
		end
	end
	return n
end

function Report.errorCount()
	local n = 0
	for _, e in order do
		local cat = Report.Categories[e.category]
		if cat and cat[2] == "error" then
			n += 1
		end
	end
	return n
end

function Report.logLine(s)
	table.insert(Report.log, s)
end

local function fmtTime(t)
	return string.format("%02d:%05.2f", math.floor(t / 60), t % 60)
end
Report.fmtTime = fmtTime

function Report.render(metricsText)
	local out = {}
	local function w(s)
		table.insert(out, s)
	end
	w("")
	w("==================================================================================")
	w(" LIGHTNING CATCHERS — HEADLESS RUNTIME SIM REPORT")
	w("==================================================================================")
	for _, cat in Report.Order do
		local list = {}
		for _, e in order do
			if e.category == cat then
				table.insert(list, e)
			end
		end
		if #list > 0 then
			local info = Report.Categories[cat]
			w("")
			w(string.format("--- %s [%s] — %d unique ---", info[1], info[2], #list))
			for i, e in list do
				local realms = table.concat(e.realmOrder, ", ")
				w(string.format("[%s%d] x%d  (%s; first at %s)", string.upper(string.sub(cat, 1, 1)), i, e.count, realms, fmtTime(e.first)))
				for line in string.gmatch(e.message, "[^\n]+") do
					w("    " .. line)
				end
				if e.extra then
					for line in string.gmatch(e.extra, "[^\n]+") do
						w("    | " .. line)
					end
				end
				if #e.frames > 0 then
					w(Report.formatFrames(e.frames, 12))
				end
			end
		end
	end
	if metricsText then
		w("")
		w(metricsText)
	end
	w("")
	local errs = Report.errorCount()
	w(string.format("RESULT: %d unique error(s)%s", errs, if errs > 0 then "  -> exit code 1" else ""))
	return table.concat(out, "\n")
end

function Report.writeLog(path)
	pcall(fs.writeFile, path, table.concat(Report.log, "\n"))
end

return Report
