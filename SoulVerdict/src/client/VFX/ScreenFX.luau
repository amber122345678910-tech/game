--!strict
-- VFX/ScreenFX: local screen-space feedback — full-screen flashes, edge vignettes and colour-correction
-- pulses (a ColorCorrectionEffect under Workspace.CurrentCamera, so it stacks with the graphics preset).
--
-- API
--   ScreenFX.Flash(color, alpha, duration)        full-screen colour flash (alpha = peak opacity 0..1)
--   ScreenFX.Vignette(color, intensity, duration) edge pulse (intensity 0..1)
--   ScreenFX.Tint(color, strength, duration)      ColorCorrection tint pulse (strength 0..1)
--   ScreenFX.Desaturate(amount, duration, hold?)  saturation dip (death, heavy hits)
--   ScreenFX.Pulse(kind, intensity?)              presets: "Hit", "Heavy", "Heal", "KR", "Parry", "GuardBreak",
--                                                 "Death", "Blue", "Ult"
--   ScreenFX.SetKR(level01)                       continuous purple edge pulse (KR / KR.Max), 0 = off
--   ScreenFX.SetLowHealth(fraction)               red heartbeat edges below 30 % HP (1 = healthy)
--   ScreenFX.SetBlue(on)                          subtle blue edges while the SOUL is blue (heavy gravity)
--   ScreenFX.Clear()
-- Reduced Motion (GraphicsController / GuiService) caps flash opacity at 0.35 (photosensitivity).
-- All animation runs in one PreRender loop that disconnects when nothing is active.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ScreenFX = {}

type Pulse = { Layer: string, Color: Color3, Peak: number, T0: number, Duration: number, Attack: number }

local LAYERS = { "Hit", "Status", "KR" }

local gui: ScreenGui? = nil
local flashFrame: Frame? = nil
local edges: { [string]: { Frame } } = {}
local cc: ColorCorrectionEffect? = nil

local pulses: { Pulse } = {}
local flashes: { Pulse } = {}
type CCPulse = { Kind: string, Color: Color3, Amount: number, T0: number, Duration: number, Hold: number }
local ccPulses: { CCPulse } = {}

local layerI: { [string]: number } = { Hit = 0, Status = 0, KR = 0 }
local layerC: { [string]: Color3 } = {}
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)

local krLevel = 0
local lowHealth = 1
local blueOn = false
local conn: any = nil

local function reducedMotion(): boolean
	local ok, on = pcall(function()
		return game:GetService("GuiService").ReducedMotionEnabled
	end)
	return ok and on == true
end

local function playerGui(): PlayerGui?
	local lp = Players.LocalPlayer
	if lp == nil then
		return nil
	end
	return lp:FindFirstChildOfClass("PlayerGui")
end

local function edgeFrame(parent: Instance, name: string, size: UDim2, pos: UDim2, anchor: Vector2, rotation: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.new(1, 0, 0)
	f.BackgroundTransparency = 1
	f.Size = size
	f.Position = pos
	f.AnchorPoint = anchor
	local g = Instance.new("UIGradient")
	g.Rotation = rotation
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.45, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = f
	f.Parent = parent
	return f
end

local function ensureGui(): boolean
	local g = gui
	if g and g.Parent then
		return true
	end
	local pg = playerGui()
	if pg == nil then
		return false
	end
	local sg = Instance.new("ScreenGui")
	sg.Name = "SV_ScreenFX"
	sg.IgnoreGuiInset = true
	sg.ResetOnSpawn = false
	sg.DisplayOrder = 1
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.BorderSizePixel = 0
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.Size = UDim2.fromScale(1, 1)
	flash.ZIndex = 10
	flash.Parent = sg
	for _, layer in LAYERS do
		local holder = Instance.new("Frame")
		holder.Name = "Edges_" .. layer
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.fromScale(1, 1)
		holder.Parent = sg
		edges[layer] = {
			edgeFrame(holder, "Top", UDim2.fromScale(1, 0.3), UDim2.fromScale(0, 0), Vector2.zero, 90),
			edgeFrame(holder, "Bottom", UDim2.fromScale(1, 0.3), UDim2.fromScale(0, 1), Vector2.new(0, 1), 270),
			edgeFrame(holder, "Left", UDim2.fromScale(0.22, 1), UDim2.fromScale(0, 0), Vector2.zero, 0),
			edgeFrame(holder, "Right", UDim2.fromScale(0.22, 1), UDim2.fromScale(1, 0), Vector2.new(1, 0), 180),
		}
	end
	sg.Parent = pg
	gui = sg
	flashFrame = flash
	return true
end

local function ensureCC(): ColorCorrectionEffect?
	local c = cc
	local cam = game:GetService("Workspace").CurrentCamera
	if cam == nil then
		return nil
	end
	if c and c.Parent == cam then
		return c
	end
	if c then
		c:Destroy()
	end
	local e = Instance.new("ColorCorrectionEffect")
	e.Name = "SV_ScreenCC"
	e.Brightness = 0
	e.Contrast = 0
	e.Saturation = 0
	e.TintColor = Color3.new(1, 1, 1)
	e.Enabled = true
	e.Parent = cam
	cc = e
	return e
end

local function envelope(p: Pulse, now: number): number
	local age = now - p.T0
	if age < 0 then
		return 0
	end
	if age < p.Attack then
		return p.Peak * (age / p.Attack)
	end
	local k = (age - p.Attack) / math.max(1e-3, p.Duration - p.Attack)
	if k >= 1 then
		return -1
	end
	return p.Peak * (1 - k) * (1 - k)
end

local function setLayer(layer: string, color: Color3, intensity: number)
	local list = edges[layer]
	if list == nil then
		return
	end
	local t = 1 - math.clamp(intensity, 0, 0.92)
	for _, f in list do
		f.BackgroundColor3 = color
		f.BackgroundTransparency = t
	end
end

local function step()
	local now = os.clock()
	local active = false
	-- vignette pulses, strongest colour per layer wins (reused tables: no per-frame allocation)
	layerI.Hit, layerI.Status, layerI.KR = 0, 0, 0
	layerC.Hit, layerC.Status, layerC.KR = BLACK, BLACK, BLACK
	local i = 1
	while i <= #pulses do
		local p = pulses[i]
		local v = envelope(p, now)
		if v < 0 then
			table.remove(pulses, i)
		else
			active = true
			if v > layerI[p.Layer] then
				layerI[p.Layer] = v
				layerC[p.Layer] = p.Color
			end
			i += 1
		end
	end
	-- continuous states
	if krLevel > 0.01 then
		active = true
		local rate = 1.2 + 2.4 * krLevel
		local wave = 0.5 + 0.5 * math.sin(now * rate * math.pi * 2)
		local v = (0.12 + 0.3 * krLevel) * (0.55 + 0.45 * wave)
		if v > layerI.KR then
			layerI.KR = v
			layerC.KR = Color3.fromRGB(190, 40, 230)
		end
	end
	if lowHealth < 0.3 then
		active = true
		local beat = (now * 1.35) % 1
		local thump = math.max(math.exp(-beat * 9), 0.7 * math.exp(-math.max(0, beat - 0.22) * 9) * (if beat > 0.22 then 1 else 0))
		local severity = 1 - lowHealth / 0.3
		local v = (0.1 + 0.32 * severity) * (0.35 + 0.65 * thump)
		if v > layerI.Status then
			layerI.Status = v
			layerC.Status = Color3.fromRGB(200, 0, 20)
		end
	end
	if blueOn then
		active = true
		local v = 0.16 + 0.05 * math.sin(now * 3)
		if v > layerI.Status then
			layerI.Status = v
			layerC.Status = Color3.fromRGB(0, 60, 255)
		end
	end
	for _, layer in LAYERS do
		setLayer(layer, layerC[layer] or BLACK, layerI[layer])
	end
	-- flashes
	local flashV, flashC = 0, WHITE
	i = 1
	while i <= #flashes do
		local p = flashes[i]
		local v = envelope(p, now)
		if v < 0 then
			table.remove(flashes, i)
		else
			active = true
			if v > flashV then
				flashV = v
				flashC = p.Color
			end
			i += 1
		end
	end
	local ff = flashFrame
	if ff then
		ff.BackgroundColor3 = flashC
		ff.BackgroundTransparency = 1 - math.clamp(flashV, 0, 1)
	end
	-- colour correction
	local e = cc
	if e and e.Parent then
		local sat, bright, contrast = 0, 0, 0
		local tint = WHITE
		local tintAmt = 0
		i = 1
		while i <= #ccPulses do
			local p = ccPulses[i]
			local age = now - p.T0
			local total = p.Duration + p.Hold
			if age >= total then
				table.remove(ccPulses, i)
			else
				active = true
				local k: number
				if age < 0.06 then
					k = age / 0.06
				elseif age < 0.06 + p.Hold then
					k = 1
				else
					k = 1 - (age - 0.06 - p.Hold) / math.max(1e-3, p.Duration - 0.06)
				end
				k = math.clamp(k, 0, 1)
				if p.Kind == "Tint" then
					if p.Amount * k > tintAmt then
						tintAmt = p.Amount * k
						tint = WHITE:Lerp(p.Color, tintAmt)
					end
					contrast += 0.08 * p.Amount * k
				elseif p.Kind == "Desat" then
					sat -= p.Amount * k
					contrast += 0.1 * p.Amount * k
					bright -= 0.04 * p.Amount * k
				end
				i += 1
			end
		end
		e.Saturation = math.clamp(sat, -1, 1)
		e.Brightness = bright
		e.Contrast = contrast
		e.TintColor = tint
	end
	if not active and conn then
		conn:Disconnect()
		conn = nil
		setLayer("Hit", Color3.new(0, 0, 0), 0)
		setLayer("Status", Color3.new(0, 0, 0), 0)
		setLayer("KR", Color3.new(0, 0, 0), 0)
		if ff then
			ff.BackgroundTransparency = 1
		end
	end
end

local function run()
	if conn == nil then
		conn = RunService.PreRender:Connect(step)
	end
end

function ScreenFX.Flash(color: Color3, alpha: number, duration: number)
	if not ensureGui() then
		return
	end
	local peak = math.clamp(alpha, 0, 1)
	if reducedMotion() then
		peak = math.min(peak, 0.35)
	end
	table.insert(flashes, { Layer = "Flash", Color = color, Peak = peak, T0 = os.clock(), Duration = math.max(0.05, duration), Attack = 0.03 })
	run()
end

function ScreenFX.Vignette(color: Color3, intensity: number, duration: number, layer: string?)
	if not ensureGui() then
		return
	end
	table.insert(pulses, {
		Layer = layer or "Hit",
		Color = color,
		Peak = math.clamp(intensity, 0, 1),
		T0 = os.clock(),
		Duration = math.max(0.05, duration),
		Attack = 0.05,
	})
	run()
end

function ScreenFX.Tint(color: Color3, strength: number, duration: number, hold: number?)
	if ensureCC() == nil then
		return
	end
	table.insert(ccPulses, { Kind = "Tint", Color = color, Amount = math.clamp(strength, 0, 1), T0 = os.clock(), Duration = math.max(0.08, duration), Hold = hold or 0 })
	run()
end

function ScreenFX.Desaturate(amount: number, duration: number, hold: number?)
	if ensureCC() == nil then
		return
	end
	table.insert(ccPulses, { Kind = "Desat", Color = Color3.new(1, 1, 1), Amount = math.clamp(amount, 0, 1), T0 = os.clock(), Duration = math.max(0.08, duration), Hold = hold or 0 })
	run()
end

-- Presets used by FxController (intensity 0..1 scales them).
function ScreenFX.Pulse(kind: string, intensity: number?)
	local k = math.clamp(intensity or 1, 0, 1.5)
	if kind == "Hit" then
		ScreenFX.Vignette(Color3.fromRGB(255, 20, 20), 0.28 + 0.3 * k, 0.45)
		ScreenFX.Tint(Color3.fromRGB(255, 120, 120), 0.12 * k, 0.25)
	elseif kind == "Heavy" then
		ScreenFX.Vignette(Color3.fromRGB(255, 0, 0), 0.6 + 0.25 * k, 0.7)
		ScreenFX.Flash(Color3.fromRGB(255, 255, 255), 0.18 * k, 0.16)
		ScreenFX.Desaturate(0.35 * k, 0.4)
	elseif kind == "Heal" then
		ScreenFX.Vignette(Color3.fromRGB(60, 255, 110), 0.2 * k, 0.6, "Status")
	elseif kind == "KR" then
		ScreenFX.Vignette(Color3.fromRGB(200, 50, 255), 0.25 * k, 0.4, "KR")
	elseif kind == "Parry" then
		ScreenFX.Flash(Color3.fromRGB(255, 240, 190), 0.22 * k, 0.14)
		ScreenFX.Tint(Color3.fromRGB(255, 230, 150), 0.18 * k, 0.25)
	elseif kind == "GuardBreak" then
		ScreenFX.Vignette(Color3.fromRGB(255, 140, 30), 0.55 * k, 0.6)
		ScreenFX.Desaturate(0.3 * k, 0.5)
	elseif kind == "Death" then
		ScreenFX.Flash(Color3.fromRGB(255, 0, 0), 0.35 * k, 0.4)
		ScreenFX.Desaturate(0.85 * k, 1.6, 0.8)
	elseif kind == "Blue" then
		ScreenFX.Vignette(Color3.fromRGB(0, 80, 255), 0.45 * k, 0.6, "Status")
		ScreenFX.Tint(Color3.fromRGB(120, 170, 255), 0.25 * k, 0.5)
	elseif kind == "Ult" then
		ScreenFX.Flash(Color3.fromRGB(255, 255, 255), 0.25 * k, 0.2)
		ScreenFX.Tint(Color3.fromRGB(255, 255, 255), 0.1 * k, 0.4)
	end
end

function ScreenFX.SetKR(level: number)
	local v = math.clamp(level, 0, 1)
	if math.abs(v - krLevel) < 1e-3 then
		return
	end
	krLevel = v
	if v > 0.01 and ensureGui() then
		run()
	end
end

function ScreenFX.SetLowHealth(fraction: number)
	lowHealth = math.clamp(fraction, 0, 1)
	if lowHealth < 0.3 and ensureGui() then
		run()
	end
end

function ScreenFX.SetBlue(on: boolean)
	blueOn = on
	if on and ensureGui() then
		run()
	end
end

function ScreenFX.Clear()
	table.clear(pulses)
	table.clear(flashes)
	table.clear(ccPulses)
	krLevel = 0
	lowHealth = 1
	blueOn = false
	local e = cc
	if e then
		e.Saturation = 0
		e.Brightness = 0
		e.Contrast = 0
		e.TintColor = Color3.new(1, 1, 1)
	end
end

return ScreenFX
