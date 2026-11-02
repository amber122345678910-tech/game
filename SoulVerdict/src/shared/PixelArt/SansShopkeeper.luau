--!strict
-- PixelArt/SansShopkeeper: the Shop screen's shopkeeper scene (owner's request: sleepy Sans at his sentry-station
-- shop, "zzz... oh. hi, kid. what do you want?") as pixel art on one Width x Height cell grid (0-based cells,
-- x = column, y = row from the top). Drawn by Client/UI/Screens/ShopKeeper; the head is the owner's 40 x 37 sprite
-- (Shared/PixelArt/SansHead). Lune-safe: data + pure helpers, no services.
--
-- Drawing order (back -> front): Booth (snowy roof beam + posts), Body (blue hoodie, white fur trim of the hood,
-- shirt + drawstrings), the head, Counter (wooden top + front planks + the sign board), Arms (sleeves resting on the
-- counter, bony hands), Props (gold coin stack, ketchup bottle). Then the floating "Z z z" glyphs while he sleeps.
-- Palette keys: '#' black outline, '.' white, b/B/l hoodie blue / shade / light, f/F fur + shirt / shade,
-- w/W/d wood light / mid / dark, s/S snow / shade, g/G/y gold / rim / shine, r/R/p ketchup / shade / shine,
-- z the Z letters, ' ' transparent.
--
--   SansShopkeeper.Width, .Height = 72, 72        scene grid
--   SansShopkeeper.Colors : { [string]: Color3 }   every palette key above
--   SansShopkeeper.Order : { string }              "Booth", "Body", "Head", "Counter", "Arms", "Props"
--   SansShopkeeper.Layers : { [name]: Layer }      Layer = { X, Y (cell of Rows[1][1]), Rows: {string} }
--   SansShopkeeper.HeadX, .HeadAwakeY, .HeadAsleepY   head placement (cells): awake / slumped asleep (2 lower)
--   SansShopkeeper.AwakeHead : {string}            the owner's sprite as drawn (SansHead.Rows: left eye open, wink)
--   SansShopkeeper.SleepHead : {string}            derived from it: both eyes closed as arcs
--   SansShopkeeper.SleepingHead(rows) -> {string}  the derivation: the black left eye socket (+ its white pupil) is
--                                                  cleared to white and the right eye's closed arc is mirrored onto
--                                                  the left eye (x -> 40 - x, rows 14..19); the cheek marks stay
--   SansShopkeeper.HeadParts() -> { Base, Awake, Asleep }  40 x 37 grids: Base = cells both heads share, Awake /
--                                                  Asleep = only the cells that differ (eye overlays, toggled)
--   SansShopkeeper.Z : { Small, Medium, Big }      glyph rows ('z' / ' '), 4x4, 5x5, 6x6 (a Z needs 4 cells for its
--                                                  diagonal to read); drawn on the bottom-left of a ZSize slot
--   SansShopkeeper.ZSize = 6                       cells of that square slot
--   SansShopkeeper.ZStart, .ZEnd : { x, y }        path of a floating Z (cell of its slot's top-left corner), bottom
--                                                  -> top: up the gap between his head and the right post
--   SansShopkeeper.Sign : { X, Y, W, H }           inner area of the counter-front board (the "SHOP" label sits there)
--   SansShopkeeper.CounterFrontY = 59              first row of the counter front (a dialogue box may cover it)
--   SansShopkeeper.Runs(rows) -> {Run}             horizontal runs of one key: Run = { x, y, length, color }
--   SansShopkeeper.Rects(rows) -> {Rect}           runs stacked vertically when identical (x, length, key) in
--                                                  consecutive rows: Rect = { x, y, w, h, color }; painted in order
--                                                  they give exactly the rows, one GuiObject each
--   SansShopkeeper.Compose(head: "Awake"|"Asleep", headY: number?) -> {string}   the whole scene as one grid
--   SansShopkeeper.Validate() -> {string}          problems (empty = well-formed)

local SansHead = require(script.Parent.SansHead)

export type Layer = { X: number, Y: number, Rows: { string } }
export type Run = { x: number, y: number, length: number, color: string }
export type Rect = { x: number, y: number, w: number, h: number, color: string }

local SansShopkeeper = {}

SansShopkeeper.Width = 72
SansShopkeeper.Height = 72
SansShopkeeper.HeadX = 16
SansShopkeeper.HeadAwakeY = 8
SansShopkeeper.HeadAsleepY = 10
SansShopkeeper.CounterFrontY = 59

local rgb = Color3.fromRGB
SansShopkeeper.Colors = {
	["#"] = rgb(0, 0, 0),
	["."] = rgb(255, 255, 255),
	b = rgb(56, 110, 212),
	B = rgb(34, 70, 150),
	l = rgb(104, 160, 242),
	f = rgb(238, 242, 250),
	F = rgb(170, 182, 206),
	w = rgb(222, 160, 94),
	W = rgb(170, 106, 54),
	d = rgb(112, 64, 30),
	s = rgb(250, 252, 255),
	S = rgb(176, 204, 236),
	g = rgb(255, 208, 44),
	G = rgb(196, 134, 20),
	y = rgb(255, 244, 160),
	r = rgb(220, 40, 40),
	R = rgb(146, 20, 26),
	p = rgb(255, 140, 140),
	z = rgb(255, 255, 255),
}

SansShopkeeper.Order = { "Booth", "Body", "Head", "Counter", "Arms", "Props" }

-- (rows keep their trailing spaces: every row of a layer has the same length)
SansShopkeeper.Layers = {
	Booth = {
		X = 0,
		Y = 0,
		Rows = {
			"########################################################################",
			"#ssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssss#",
			"#ssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssss#",
			"#SSSSsssssSSSSSSSSSsssSSSSSSSssssssSSSSSSSSSssssSSSSSSSssssssSSSSsssSSS#",
			"#wwwwssssswwwwwwwdwSSSwwwwwwwssssssdwwwwwwwwSSSSwwwwwdwsssssswwwwSSSwww#",
			"#WWWW#SSS#WWWWWWWdW###WWWWWWW#SSSS#dWWWWWWWW####WWWWWdW#SSSS#WWWW###WWW#",
			"#WWWWW###WWWWWWWWdWWWWWWWWWWWW####WdWWWWWWWWWWWWWWWWWdWW####WWWWWWWWWWW#",
			"#dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd#",
			"########################################################################",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
			"#wWWd#                                                            #wWWd#",
		},
	},
	Body = {
		X = 7,
		Y = 35,
		Rows = {
			"                 #######################                  ",
			"            ######ffFffFffFffFffFffFffF######             ",
			"         ####fFffFfffffffffffffffffffffffFff####          ",
			"       ###fFffffffffffffffffffffffffffffffffFff###        ",
			"      ##FffffffffffffffffffffffffffffffffffffffFf##       ",
			"      #fffffffffffffffffffffffffffffffffffffffffff##      ",
			"    ###fffffffffffffffffffffffffffffffffffffffffff####    ",
			"  ###l##FffffffffffffffffffffffffffffffffffffffFf##ll##   ",
			" ##bbbb###fFffffffffffffffffffffffffffffffffFff###bbbb##  ",
			" #Bbbbbbb####FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF####bbbbbbB## ",
			"##Bbbbbbbbbb######FFFFFFFFFFFFFFFFFFFFF######bbbbbbbbbBB# ",
			"#BBbbbbbbbbbbbbbb#######.########.######bbbbbbbbbbbbbbBB##",
			"#BBbbbbbbbbbbbbbbbbbbbBf.ffffffff.bbbbbbbbbbbbbbbbbbbbBBB#",
			"#BBbbbbbbbbbbbbbbbbbbbBf.ffffffff.bbbbbbbbbbbbbbbbbbbbBBB#",
			"#BBbbbbbbbbbbbbbbbbbbbBf.ffffffff.bbbbbbbbbbbbbbbbbbbbBBB#",
			"#BBbbbbbbbbbbbbbbbbbbbBf.ffffffff.bbbbbbbbbbbbbbbbbbbbBBB#",
			"#BBbbbbbbbbbbbbbbbbbbbBf#ffffffff#bbbbbbbbbbbbbbbbbbbbBBB#",
			"#BBbbbbbbbbbbbbbbbbbbbBffffffffffBbbbbbbbbbbbbbbbbbbbbBBB#",
			"#BBbbbbbbbbbbbbbbbbbbbBffffffffffBbbbbbbbbbbbbbbbbbbbbBBB#",
			"#BBbbbbbbbbbbbbbbbbbbbBffffffffffBbbbbbbbbbbbbbbbbbbbbBBB#",
			"#BBbbbbbbbbbbbbbbbbbbbBffffffffffBbbbbbbbbbbbbbbbbbbbbBBB#",
			"#BBbbbbbbbbbbbbbbbbbbbBffffffffffBbbbbbbbbbbbbbbbbbbbbBBB#",
			"#BBbbbbbbbbbbbbbbbbbbbBffffffffffBbbbbbbbbbbbbbbbbbbbbBBB#",
		},
	},
	Counter = {
		X = 0,
		Y = 55,
		Rows = {
			"########################################################################",
			"#wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww#",
			"#wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww#",
			"#dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd#",
			"########################################################################",
			"#WWWdWWWWWWWWdWWWWWWWWdWWWWWWWWdWWWWWWWWdWWWWWWWWdWWWWWWWWdWWWWWWWWdWWW#",
			"#WWWdWWWWWWWWdWWWW####################################WWWWdWWWWWWWWdWWW#",
			"#WWWdWWWWWWWWdWWWW#wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww#WWWWdWWWWWWWWdWWW#",
			"#WWWdWWWWWWWWdWWWW#wdwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwdw#WWWWdWWWWWWWWdWWW#",
			"#WWWdWWWWWWWWdWWWW#wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww#WWWWdWWWWWWWWdWWW#",
			"#WWWdWWWWWWWWdWWWW#wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww#WWWWdWWWWWWWWdWWW#",
			"#WWWdWWWWWWWWdWWWW#wdwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwdw#WWWWdWWWWWWWWdWWW#",
			"#WWWdWWWWWWWWdWWWW#wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww#WWWWdWWWWWWWWdWWW#",
			"#WWWdWWWWWWWWdWWWW#WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW#WWWWdWWWWWWWWdWWW#",
			"#WWWdWWWWWWWWdWWWW####################################WWWWdWWWWWWWWdWWW#",
			"#dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd#",
			"########################################################################",
		},
	},
	Arms = {
		X = 6,
		Y = 48,
		Rows = {
			"  #######################          #######################  ",
			"###lllllllllllllllllllbb############bblllllllllllllllllll###",
			"#lllllllllllllllllllllBBBB#..##..#BBBBlllllllllllllllllllll#",
			"#bbbbbbbbbbbbbbbbbbbbbBBBB........BBBBbbbbbbbbbbbbbbbbbbbbb#",
			"#bbbbbbbbbbbbbbbbbbbbbBBB..........BBBbbbbbbbbbbbbbbbbbbbbb#",
			"#bbbbbbbbbbbbbbbbbbbbbBBB..#....#..BBBbbbbbbbbbbbbbbbbbbbbb#",
			"#BBBBBBBBBBBBBBBBBBBBBBBBB#......#BBBBBBBBBBBBBBBBBBBBBBBBB#",
			"##BBBBBBBBBBBBBBBBBBBBBBB##########BBBBBBBBBBBBBBBBBBBBBBB##",
			" #########################        ######################### ",
		},
	},
	Props = {
		X = 5,
		Y = 39,
		Rows = {
			"                                                       ###   ",
			"                                                      #fff#  ",
			"                                                      #rrr#  ",
			"                                                      #prr#  ",
			"                                                      #prr#  ",
			" ######                                              ##prr## ",
			"#yyggGG#                                            ##rrrrr##",
			"#GGGGGG#                                            #rprrrrR#",
			" ######G#                                           #rprrrrR#",
			" #GGGGGG#                                           #rpRRRRR#",
			"#y######                                            #rp....R#",
			"#GGGGGG#                                            #rp....R#",
			" ######G#                                           #rpRRRRR#",
			" #GGGGGG#######                                     #rprrrrR#",
			"#y#######yyggGG#                                    #rprrrrR#",
			"#GGGGGG##GGGGGG#                                    #rrrrrrR#",
			" ######  ######                                     #########",
		},
	},
}

SansShopkeeper.Z = {
	Small = {
		"zzzz",
		"  z ",
		" z  ",
		"zzzz",
	},
	Medium = {
		"zzzzz",
		"   z ",
		"  z  ",
		" z   ",
		"zzzzz",
	},
	Big = {
		"zzzzzz",
		"    z ",
		"   z  ",
		"  z   ",
		" z    ",
		"zzzzzz",
	},
}
SansShopkeeper.ZSize = 6 -- cells of the square slot a Z letter is drawn in (glyphs sit on its bottom-left)
SansShopkeeper.ZStart = { x = 55, y = 30 }
SansShopkeeper.ZEnd = { x = 60, y = 9 }
SansShopkeeper.Sign = { X = 19, Y = 62, W = 34, H = 7 }

------------------------------------------------------------------------------------------------ the sleeping head

local HEAD_W, HEAD_H = SansHead.Width, SansHead.Height
local LEFT_SOCKET = { x = 10, y = 14 } -- a cell of the black left eye socket (0-based)
local RIGHT_ARC = { x = 24, y = 14 } -- a cell of the closed right eye (the wink arc)
local ARC_LAST_ROW = 19 -- rows below belong to the cheek marks under the eyes (kept as drawn)

local function cell(grid: { { string } }, x: number, y: number): string
	local row = grid[y + 1]
	return if row then (row[x + 1] or " ") else " "
end

-- 4-connected cells of `key` around (x, y)
local function component(grid: { { string } }, x0: number, y0: number, key: string): { { number } }
	local out = {}
	if cell(grid, x0, y0) ~= key then
		return out
	end
	local seen = { [y0 * 1000 + x0] = true }
	local stack = { { x0, y0 } }
	while #stack > 0 do
		local p = table.remove(stack) :: { number }
		table.insert(out, p)
		for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local x, y = p[1] + d[1], p[2] + d[2]
			local id = y * 1000 + x
			if not seen[id] and cell(grid, x, y) == key then
				seen[id] = true
				table.insert(stack, { x, y })
			end
		end
	end
	return out
end

local function toGrid(rows: { string }): { { string } }
	local grid = {}
	for i, row in rows do
		local r = table.create(#row)
		for x = 1, #row do
			r[x] = string.sub(row, x, x)
		end
		grid[i] = r
	end
	return grid
end

local function fromGrid(grid: { { string } }): { string }
	local out = table.create(#grid)
	for i, r in grid do
		out[i] = table.concat(r)
	end
	return out
end

function SansShopkeeper.SleepingHead(rows: { string }): { string }
	local source = toGrid(rows)
	local grid = toGrid(rows)
	for _, p in component(source, LEFT_SOCKET.x, LEFT_SOCKET.y, "#") do
		if p[2] <= ARC_LAST_ROW then
			grid[p[2] + 1][p[1] + 1] = "."
		end
	end
	for _, p in component(source, RIGHT_ARC.x, RIGHT_ARC.y, "#") do
		local mx = HEAD_W - p[1]
		if p[2] <= ARC_LAST_ROW and mx >= 0 and mx < HEAD_W then
			grid[p[2] + 1][mx + 1] = "#"
		end
	end
	return fromGrid(grid)
end

SansShopkeeper.AwakeHead = SansHead.Rows
SansShopkeeper.SleepHead = SansShopkeeper.SleepingHead(SansHead.Rows)

function SansShopkeeper.HeadParts(): { Base: { string }, Awake: { string }, Asleep: { string } }
	local base, awake, asleep = {}, {}, {}
	for y = 1, HEAD_H do
		local a = SansShopkeeper.AwakeHead[y] or ""
		local s = SansShopkeeper.SleepHead[y] or ""
		local rb, ra, rs = table.create(HEAD_W, " "), table.create(HEAD_W, " "), table.create(HEAD_W, " ")
		for x = 1, HEAD_W do
			local ca, cs = string.sub(a, x, x), string.sub(s, x, x)
			if ca == cs then
				rb[x] = if ca == "" then " " else ca
			else
				ra[x] = if ca == "" then " " else ca
				rs[x] = if cs == "" then " " else cs
			end
		end
		base[y], awake[y], asleep[y] = table.concat(rb), table.concat(ra), table.concat(rs)
	end
	return { Base = base, Awake = awake, Asleep = asleep }
end

------------------------------------------------------------------------------------------------ runs / rects

function SansShopkeeper.Runs(rows: { string }): { Run }
	local out: { Run } = {}
	for i, row in rows do
		local x = 1
		local n = #row
		while x <= n do
			local c = string.sub(row, x, x)
			local stop = x
			while stop < n and string.sub(row, stop + 1, stop + 1) == c do
				stop += 1
			end
			if c ~= " " then
				table.insert(out, { x = x - 1, y = i - 1, length = stop - x + 1, color = c })
			end
			x = stop + 1
		end
	end
	return out
end

function SansShopkeeper.Rects(rows: { string }): { Rect }
	local out: { Rect } = {}
	local open: { [string]: Rect } = {}
	for _, run in SansShopkeeper.Runs(rows) do
		local key = run.x .. ":" .. run.length .. ":" .. run.color
		local r = open[key]
		if r and r.y + r.h == run.y then
			r.h += 1
		else
			local rect = { x = run.x, y = run.y, w = run.length, h = 1, color = run.color }
			open[key] = rect
			table.insert(out, rect)
		end
	end
	return out
end

------------------------------------------------------------------------------------------------ compose / validate

local function blit(grid: { { string } }, rows: { string }, ox: number, oy: number)
	for j, row in rows do
		local target = grid[oy + j]
		if target then
			for i = 1, #row do
				local c = string.sub(row, i, i)
				if c ~= " " and ox + i >= 1 and ox + i <= #target then
					target[ox + i] = c
				end
			end
		end
	end
end

function SansShopkeeper.Compose(head: string, headY: number?): { string }
	local grid = {}
	for y = 1, SansShopkeeper.Height do
		grid[y] = table.create(SansShopkeeper.Width, " ")
	end
	local asleep = head == "Asleep"
	local hy = headY or (if asleep then SansShopkeeper.HeadAsleepY else SansShopkeeper.HeadAwakeY)
	for _, name in SansShopkeeper.Order do
		if name == "Head" then
			blit(grid, if asleep then SansShopkeeper.SleepHead else SansShopkeeper.AwakeHead, SansShopkeeper.HeadX, hy)
		else
			local layer = SansShopkeeper.Layers[name]
			blit(grid, layer.Rows, layer.X, layer.Y)
		end
	end
	return fromGrid(grid)
end

local function checkRows(problems: { string }, label: string, rows: { string }, w: number?, h: number?)
	local width = w or (if rows[1] then #rows[1] else 0)
	if h and #rows ~= h then
		table.insert(problems, ("%s: %d rows, expected %d"):format(label, #rows, h))
	end
	for i, row in rows do
		if #row ~= width then
			table.insert(problems, ("%s row %d: %d cells, expected %d"):format(label, i, #row, width))
		end
		for x = 1, #row do
			local c = string.sub(row, x, x)
			if c ~= " " and SansShopkeeper.Colors[c] == nil then
				table.insert(problems, ("%s row %d: unknown key %q at column %d"):format(label, i, c, x))
				break
			end
		end
	end
end

function SansShopkeeper.Validate(): { string }
	local problems: { string } = {}
	local W, H = SansShopkeeper.Width, SansShopkeeper.Height
	for _, name in SansShopkeeper.Order do
		if name ~= "Head" then
			local layer = SansShopkeeper.Layers[name]
			if layer == nil then
				table.insert(problems, "missing layer " .. name)
			else
				checkRows(problems, name, layer.Rows)
				local lw = if layer.Rows[1] then #layer.Rows[1] else 0
				if layer.X < 0 or layer.Y < 0 or layer.X + lw > W or layer.Y + #layer.Rows > H then
					table.insert(problems, name .. ": outside the scene")
				end
			end
		end
	end
	checkRows(problems, "AwakeHead", SansShopkeeper.AwakeHead, HEAD_W, HEAD_H)
	checkRows(problems, "SleepHead", SansShopkeeper.SleepHead, HEAD_W, HEAD_H)
	for _, y in { SansShopkeeper.HeadAwakeY, SansShopkeeper.HeadAsleepY } do
		if SansShopkeeper.HeadX < 0 or SansShopkeeper.HeadX + HEAD_W > W or y < 0 or y + HEAD_H > H then
			table.insert(problems, "head outside the scene")
		end
	end
	for name, glyph in SansShopkeeper.Z do
		checkRows(problems, "Z." .. name, glyph, #glyph, #glyph)
		if #glyph > SansShopkeeper.ZSize then
			table.insert(problems, "Z." .. name .. ": larger than ZSize")
		end
	end
	for _, p in { SansShopkeeper.ZStart, SansShopkeeper.ZEnd } do
		if p.x < 0 or p.y < 0 or p.x + SansShopkeeper.ZSize > W or p.y + SansShopkeeper.ZSize > H then
			table.insert(problems, "Z path outside the scene")
		end
	end
	local s = SansShopkeeper.Sign
	if s.X < 0 or s.Y < 0 or s.X + s.W > W or s.Y + s.H > H then
		table.insert(problems, "sign outside the scene")
	end
	return problems
end

return SansShopkeeper
