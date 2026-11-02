--!strict
-- PixelArt/SansHead: the owner's pixel-art Sans head (40 x 37 cells, row 1 = top), drawn by the PLAY / PRACTICE
-- loading screen (Client/UI/Overlays/Loading). Lune-safe: data + pure helpers, no services.
--   '#' = black (outline, eyes, nose, grin), '.' = white (the skull), ' ' = transparent.
--
--   SansHead.Rows : {string}             the sprite exactly as drawn (every row Width characters)
--   SansHead.MirroredRows : {string}     the same sprite flipped left <-> right (the back of a coin turn)
--   SansHead.Width = 40, SansHead.Height = 37
--   SansHead.Colors : { ["#"]: Color3, ["."]: Color3 }   black / white
--   SansHead.Mirror(rows) -> {string}    any sprite flipped left <-> right
--   SansHead.Runs(rows?) -> {Run}        every row merged into horizontal runs of one colour (left to right, top to
--                                        bottom): Run = { x, y, length, color } with x, y = 0-based cell (x = column,
--                                        y = row from the top) and color = "#" | "."; the runs cover every
--                                        non-transparent cell exactly once (one GuiObject per run, no seams in a row)
--   SansHead.LayeredRuns(rows?) -> {Run} seam-proof drawing order for a sprite that gets squeezed (the coin turn):
--                                        first one "." run per row spanning its white extent (split only at
--                                        transparent cells), then every "#" run on top. Painted in order they give
--                                        exactly the sprite; a rounding gap can only show the white under-fill
--                                        inside the face or the (black) background next to the black outline.
--   SansHead.Validate(rows?) -> {string} problems (empty = well-formed: Height rows x Width cells of '#', '.', ' ')
-- rows? defaults to SansHead.Rows.

export type Run = { x: number, y: number, length: number, color: string }

local SansHead = {}

SansHead.Width = 40
SansHead.Height = 37

-- OWNER'S SPRITE (keep every row exactly 40 characters, trailing spaces included)
SansHead.Rows = {
	"             ###############            ",
	"           ####################         ",
	"         ####...............####        ",
	"       ####....................###      ",
	"      ###.......................###     ",
	"     ##...........................##    ",
	"    ##.............................##   ",
	"   ##...............................##  ",
	"  ##.................................## ",
	" ##..................................## ",
	" ##..................................## ",
	" ##...................................##",
	"##.......######.......................##",
	"##.....#########......................##",
	"##....###########.......#.............##",
	"##...############.......#..........#..##",
	"##...#####..#####.......#..........#..##",
	"##...#####..#####.......#.........##.## ",
	" ##...##########....#...##.......##..## ",
	" ##....#########...###...#########..##  ",
	"  ##...........#...###...##........##   ",
	"   ##.........#...#####...#........##   ",
	"   ##.......##....#####....##.......##  ",
	"   ##....#........#####.............##  ",
	"  ##.....#....................#......## ",
	"  ##....###...................#......## ",
	"  ##..##.#.##................####....## ",
	"  ##......##.################.#......## ",
	"  ##.......#.#..#...#...#..#.#.......## ",
	"  ##........##..#...#...#..##.......##  ",
	"   ##........#..#...#...#..#........##  ",
	"    ##........#############........##   ",
	"     ##..........................###    ",
	"      ###......................####     ",
	"       #####.................####       ",
	"         ######################         ",
	"            #################           ",
}

SansHead.Colors = {
	["#"] = Color3.fromRGB(0, 0, 0),
	["."] = Color3.fromRGB(255, 255, 255),
}

function SansHead.Mirror(rows: { string }): { string }
	local out = table.create(#rows)
	for i, row in rows do
		out[i] = string.reverse(row)
	end
	return out
end

SansHead.MirroredRows = SansHead.Mirror(SansHead.Rows)

-- runs of one character inside row[from..to] (1-based, inclusive); only chars in `keep` produce runs
local function rowRuns(row: string, y: number, from: number, to: number, keep: { [string]: boolean }, out: { Run })
	local x = from
	while x <= to do
		local c = string.sub(row, x, x)
		local stop = x
		while stop < to and string.sub(row, stop + 1, stop + 1) == c do
			stop += 1
		end
		if keep[c] then
			table.insert(out, { x = x - 1, y = y, length = stop - x + 1, color = c })
		end
		x = stop + 1
	end
end

local ALL = { ["#"] = true, ["."] = true }
local BLACK = { ["#"] = true }

function SansHead.Runs(rows: { string }?): { Run }
	local sprite = rows or SansHead.Rows
	local out: { Run } = {}
	for i, row in sprite do
		rowRuns(row, i - 1, 1, #row, ALL, out)
	end
	return out
end

function SansHead.LayeredRuns(rows: { string }?): { Run }
	local sprite = rows or SansHead.Rows
	local base: { Run } = {}
	local top: { Run } = {}
	for i, row in sprite do
		local first = string.find(row, ".", 1, true)
		if first then
			local last = first
			for x = #row, first, -1 do
				if string.sub(row, x, x) == "." then
					last = x
					break
				end
			end
			-- the white extent, split only where the sprite is transparent
			local x = first
			while x <= last do
				if string.sub(row, x, x) == " " then
					x += 1
				else
					local stop = x
					while stop < last and string.sub(row, stop + 1, stop + 1) ~= " " do
						stop += 1
					end
					table.insert(base, { x = x - 1, y = i - 1, length = stop - x + 1, color = "." })
					x = stop + 1
				end
			end
		end
		rowRuns(row, i - 1, 1, #row, BLACK, top)
	end
	for _, run in top do
		table.insert(base, run)
	end
	return base
end

function SansHead.Validate(rows: { string }?): { string }
	local sprite = rows or SansHead.Rows
	local problems = {}
	if #sprite ~= SansHead.Height then
		table.insert(problems, ("%d rows, expected %d"):format(#sprite, SansHead.Height))
	end
	for i, row in sprite do
		if #row ~= SansHead.Width then
			table.insert(problems, ("row %d has %d cells, expected %d"):format(i, #row, SansHead.Width))
		end
		local bad = string.find(row, "[^#%. ]")
		if bad then
			table.insert(problems, ("row %d: unexpected character %q at column %d"):format(i, string.sub(row, bad, bad), bad))
		end
	end
	return problems
end

return SansHead
