-- Lune: компилирует каждый .luau из src (ловит синтаксические ошибки до запуска в Studio).
-- Запуск: lune run tests/compile_all.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local failures = 0
local checked = 0

local function walk(dir: string)
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			walk(path)
		elseif string.sub(name, -5) == ".luau" then
			checked += 1
			local ok, err = pcall(luau.compile, fs.readFile(path))
			if not ok then
				failures += 1
				print("FAIL " .. path .. "\n  " .. tostring(err))
			end
		end
	end
end

walk("src")
print(string.format("compiled %d files, %d failures", checked, failures))
process.exit(if failures == 0 then 0 else 1)
