-- Menu logic shared by every menu style.
-- A style module only decides how things LOOK (see MenuStyles/*). This file decides what they DO.
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Widgets = require(script.Parent.Widgets)
local Settings = require(script.Parent.Settings)
local Config = require(script.Parent.Config)
local Audio = require(script.Parent.Audio)

local MenuController = {}
MenuController.__index = MenuController

export type Ctx = {
	Gui: ScreenGui,
	Canvas: Frame,
	Full: Frame,
	Mode: string, -- "main" | "pause"
	Actions: { [string]: () -> () },
}

function MenuController.new(styleModule, ctx)
	local self = setmetatable({}, MenuController)
	self.ctx = ctx
	self.connections = {}
	self.pages = {}
	self.buttons = {}
	self.current = nil
	self.selected = 0
	self.busy = false
	self.alive = true

	local style = styleModule.Build(ctx)
	self.style = style
	style.Theme.Sound = function(kind: string)
		if kind == "hover" then
			Audio.play("UIHover")
		elseif kind == "tick" then
			Audio.play("UITick")
		else
			Audio.play("UIClick")
		end
	end

	self:_buildMain()
	self:_buildSettings()
	self:_buildCredits()
	self:_buildConfirm()
	self:Show("Main", true)
	style.Intro()

	table.insert(self.connections, UserInputService.InputBegan:Connect(function(input, processed)
		self:_onKey(input, processed)
	end))
	if style.Update then
		table.insert(self.connections, RunService.RenderStepped:Connect(function(dt)
			style.Update(dt)
		end))
	end
	return self
end

function MenuController:_page(name: string): GuiObject
	local page = self.style.NewPage(name)
	page.Visible = false
	self.pages[name] = page
	self.buttons[name] = {}
	return page
end

function MenuController:_addButton(pageName: string, text: string, kind: string, action: () -> ())
	local list = self.buttons[pageName]
	local index = #list + 1
	local button, setHover = self.style.MakeButton(self.pages[pageName], text, 100 + index, kind)
	local entry = { Button = button, SetHover = setHover, Action = action, Kind = kind }
	table.insert(list, entry)
	button.MouseEnter:Connect(function()
		self:_select(index, true)
	end)
	button.MouseLeave:Connect(function()
		if self.selected == index then
			setHover(false)
			self.selected = 0
		end
	end)
	button.Activated:Connect(function()
		self:_activate(entry)
	end)
	return entry
end

function MenuController:_select(index: number, playSound: boolean)
	local list = self.buttons[self.current]
	if not list then
		return
	end
	if self.selected ~= index then
		local old = list[self.selected]
		if old then
			old.SetHover(false)
		end
		self.selected = index
		local entry = list[index]
		if entry then
			entry.SetHover(true)
			if playSound then
				Audio.play("UIHover")
			end
		end
	end
end

function MenuController:_activate(entry)
	if self.busy or not self.alive then
		return
	end
	if entry.Kind == "back" then
		Audio.play("UIBack")
	else
		Audio.play("UIClick")
	end
	entry.Action()
end

function MenuController:_onKey(input: InputObject, _processed: boolean)
	if not self.alive or self.busy then
		return
	end
	local key = input.KeyCode
	local list = self.buttons[self.current]
	if not list or #list == 0 then
		return
	end
	if key == Enum.KeyCode.Down or key == Enum.KeyCode.S or key == Enum.KeyCode.DPadDown then
		self:_select(if self.selected == 0 then 1 else (self.selected % #list) + 1, true)
	elseif key == Enum.KeyCode.Up or key == Enum.KeyCode.W or key == Enum.KeyCode.DPadUp then
		self:_select(if self.selected <= 1 then #list else self.selected - 1, true)
	elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter or key == Enum.KeyCode.ButtonA then
		local entry = list[self.selected]
		if entry then
			self:_activate(entry)
		end
	elseif key == Enum.KeyCode.Backspace or key == Enum.KeyCode.ButtonB then
		if self.current ~= "Main" then
			Audio.play("UIBack")
			self:Show("Main")
		end
	end
end

function MenuController:Show(name: string, instant: boolean?)
	local page = self.pages[name]
	if not page or self.current == name then
		return
	end
	local old = self.current and self.pages[self.current]
	local list = self.buttons[self.current]
	if list and list[self.selected] then
		list[self.selected].SetHover(false)
	end
	self.current = name
	self.selected = 0
	if self.style.ShowPage then
		self.style.ShowPage(page, old, instant)
	else
		if old then
			old.Visible = false
		end
		page.Visible = true
	end
	if not instant then
		Audio.play("UISwoosh")
	end
end

function MenuController:_buildMain()
	local page = self:_page("Main")
	if self.style.MakeTitle then
		self.style.MakeTitle(page)
	end
	local a = self.ctx.Actions
	if self.ctx.Mode == "pause" then
		self:_addButton("Main", "Resume", "primary", function()
			a.Resume()
		end)
		self:_addButton("Main", "Settings", "normal", function()
			self:Show("Settings")
		end)
		self:_addButton("Main", "Main Menu", "danger", function()
			self:_confirm("Back to the main menu?", a.MainMenu)
		end)
	else
		self:_addButton("Main", "Play", "primary", function()
			a.Play()
		end)
		self:_addButton("Main", "Settings", "normal", function()
			self:Show("Settings")
		end)
		self:_addButton("Main", "Credits", "normal", function()
			self:Show("Credits")
		end)
		self:_addButton("Main", "Quit", "danger", function()
			self:_confirm("Leave the game?", a.Quit)
		end)
	end
end

function MenuController:_buildSettings()
	local page = self:_page("Settings")
	local theme = self.style.Theme
	self.style.MakeHeading(page, "Settings", 1)
	local order = 2
	local function nextOrder()
		order += 1
		return order
	end
	Widgets.Choice(page, theme, {
		Label = "Graphics",
		Options = Config.GraphicsPresets,
		Value = Settings.Get("Graphics"),
		Order = nextOrder(),
		OnChanged = function(v)
			Settings.Set("Graphics", v)
		end,
	})
	local function pct(v)
		return tostring(math.floor(v * 100 + 0.5)) .. "%"
	end
	Widgets.Slider(page, theme, {
		Label = "Music",
		Min = 0,
		Max = 1,
		Step = 0.05,
		Value = Settings.Get("Music"),
		Format = pct,
		Order = nextOrder(),
		OnChanged = function(v)
			Settings.Set("Music", v)
		end,
	})
	Widgets.Slider(page, theme, {
		Label = "Sounds",
		Min = 0,
		Max = 1,
		Step = 0.05,
		Value = Settings.Get("Sound"),
		Format = pct,
		Order = nextOrder(),
		OnChanged = function(v)
			Settings.Set("Sound", v)
		end,
	})
	Widgets.Slider(page, theme, {
		Label = "Mouse speed",
		Min = 0.2,
		Max = 2,
		Step = 0.1,
		Value = Settings.Get("Sensitivity"),
		Format = function(v)
			return string.format("%.1fx", v)
		end,
		Order = nextOrder(),
		OnChanged = function(v)
			Settings.Set("Sensitivity", v)
		end,
	})
	Widgets.Slider(page, theme, {
		Label = "Field of view",
		Min = 60,
		Max = 100,
		Step = 1,
		Value = Settings.Get("FOV"),
		Format = function(v)
			return tostring(math.floor(v)) .. "°"
		end,
		Order = nextOrder(),
		OnChanged = function(v)
			Settings.Set("FOV", v)
		end,
	})
	Widgets.Slider(page, theme, {
		Label = "Brightness",
		Min = -1,
		Max = 1,
		Step = 0.1,
		Value = Settings.Get("Brightness"),
		Format = function(v)
			return (if v > 0 then "+" else "") .. string.format("%.1f", v)
		end,
		Order = nextOrder(),
		OnChanged = function(v)
			Settings.Set("Brightness", v)
		end,
	})
	Widgets.Toggle(page, theme, {
		Label = "Head bob",
		Value = Settings.Get("HeadBob"),
		Order = nextOrder(),
		OnChanged = function(v)
			Settings.Set("HeadBob", v)
		end,
	})
	Widgets.Toggle(page, theme, {
		Label = "See your body",
		Value = Settings.Get("ShowBody"),
		Order = nextOrder(),
		OnChanged = function(v)
			Settings.Set("ShowBody", v)
		end,
	})
	self:_addButton("Settings", "Back", "back", function()
		self:Show("Main")
	end)
end

function MenuController:_buildCredits()
	local page = self:_page("Credits")
	self.style.MakeHeading(page, "Credits", 1)
	local lines = {
		"Rick and Morty fan game. Not affiliated with Adult Swim.",
		"Made in Roblox Studio.",
		"Music: APM Music (Roblox licensed library).",
		"Sound effects: Pro Sound Effects & Roblox.",
	}
	for i, line in lines do
		self.style.MakeText(page, line, 1 + i)
	end
	self:_addButton("Credits", "Back", "back", function()
		self:Show("Main")
	end)
end

function MenuController:_buildConfirm()
	local page = self:_page("Confirm")
	self.confirmHeading = self.style.MakeHeading(page, "Are you sure?", 1)
	self:_addButton("Confirm", "Yes", "danger", function()
		if self.confirmAction then
			self.confirmAction()
		end
	end)
	self:_addButton("Confirm", "No", "back", function()
		self:Show("Main")
	end)
end

function MenuController:_confirm(question: string, action: () -> ())
	self.confirmAction = action
	local heading = self.confirmHeading
	if heading then
		local theme = self.style.Theme
		local text = if theme.Uppercase then string.upper(question) else question
		if heading:IsA("TextLabel") then
			heading.Text = text
		end
		for _, d in heading:GetDescendants() do
			if d:IsA("TextLabel") then
				d.Text = text
			end
		end
	end
	self:Show("Confirm")
end

-- Play the style's exit animation, then call done().
function MenuController:Close(done: (() -> ())?)
	if not self.alive then
		return
	end
	self.busy = true
	self.style.Outro(function()
		self:Destroy()
		if done then
			done()
		end
	end)
end

function MenuController:Destroy()
	if not self.alive then
		return
	end
	self.alive = false
	for _, c in self.connections do
		c:Disconnect()
	end
	self.style.Destroy()
end

return MenuController
