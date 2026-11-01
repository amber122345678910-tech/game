--!strict
-- Controls strings (owned by the client core: InputController / CameraController / SpectateController). Lune-safe.
-- Keys:
--   controls.action.<Action>[.monster|.human]   action display names (InputController.ActionName)
--   controls.device.<Device>                    "KeyboardMouse" | "Gamepad" | "Touch"
--   controls.key.<KeyCodeName>                  keyboard / mouse key labels that need words (LMB, Space, ...)
--   controls.pad.<KeyCodeName>                  gamepad button labels (Xbox naming; glyphs via InputController.KeyImage)
--   controls.chord / hold / press / tap         hint templates ({1} = key label)
--   controls.lock.* / controls.photo.* / controls.spectate.* / controls.camera.*
return {
	-- actions -------------------------------------------------------------------------------------
	["controls.action.M1"] = { en = "Basic attack", ru = "Обычная атака" },
	["controls.action.Q"] = { en = "Ability 1", ru = "Способность 1" },
	["controls.action.E"] = { en = "Ability 2", ru = "Способность 2" },
	["controls.action.R"] = { en = "Ability 3", ru = "Способность 3" },
	["controls.action.R.human"] = { en = "Ultimate", ru = "Ультимейт" },
	["controls.action.T"] = { en = "Ability 4", ru = "Способность 4" },
	["controls.action.F"] = { en = "Block / Parry", ru = "Блок / Парирование" },
	["controls.action.F.monster"] = { en = "Verdict Box", ru = "Коробка приговора" },
	["controls.action.F.human"] = { en = "Block / Parry", ru = "Блок / Парирование" },
	["controls.action.G"] = { en = "Ultimate", ru = "Ультимейт" },
	["controls.action.Shift"] = { en = "Dash", ru = "Рывок" },
	["controls.action.Shift.monster"] = { en = "Mobility", ru = "Перемещение" },
	["controls.action.Shift.human"] = { en = "Dash", ru = "Рывок" },
	["controls.action.Jump"] = { en = "Jump", ru = "Прыжок" },
	["controls.action.Menu"] = { en = "Menu", ru = "Меню" },
	["controls.action.Emote"] = { en = "Emotes", ru = "Эмоции" },
	["controls.action.CameraLock"] = { en = "Camera lock", ru = "Фиксация камеры" },
	["controls.action.Interact"] = { en = "Interact / Revive", ru = "Действие / Поднять" },
	["controls.action.Back"] = { en = "Back", ru = "Назад" },
	["controls.action.Confirm"] = { en = "Confirm", ru = "Подтвердить" },
	["controls.action.Prev"] = { en = "Previous", ru = "Предыдущий" },
	["controls.action.Next"] = { en = "Next", ru = "Следующий" },

	-- devices -------------------------------------------------------------------------------------
	["controls.device.KeyboardMouse"] = { en = "Keyboard & mouse", ru = "Клавиатура и мышь" },
	["controls.device.Gamepad"] = { en = "Gamepad", ru = "Геймпад" },
	["controls.device.Touch"] = { en = "Touch", ru = "Сенсорный экран" },

	-- keyboard & mouse labels ---------------------------------------------------------------------
	["controls.key.MouseButton1"] = { en = "LMB", ru = "ЛКМ" },
	["controls.key.MouseButton2"] = { en = "RMB", ru = "ПКМ" },
	["controls.key.MouseButton3"] = { en = "MMB", ru = "СКМ" },
	["controls.key.MouseWheel"] = { en = "Wheel", ru = "Колесо" },
	["controls.key.LeftShift"] = { en = "Shift", ru = "Shift" },
	["controls.key.RightShift"] = { en = "Shift", ru = "Shift" },
	["controls.key.LeftControl"] = { en = "Ctrl", ru = "Ctrl" },
	["controls.key.RightControl"] = { en = "Ctrl", ru = "Ctrl" },
	["controls.key.LeftAlt"] = { en = "Alt", ru = "Alt" },
	["controls.key.RightAlt"] = { en = "Alt", ru = "Alt" },
	["controls.key.Space"] = { en = "Space", ru = "Пробел" },
	["controls.key.Tab"] = { en = "Tab", ru = "Tab" },
	["controls.key.Return"] = { en = "Enter", ru = "Enter" },
	["controls.key.KeypadEnter"] = { en = "Enter", ru = "Enter" },
	["controls.key.Backspace"] = { en = "Backspace", ru = "Backspace" },
	["controls.key.Escape"] = { en = "Esc", ru = "Esc" },

	-- gamepad labels (Xbox naming) ----------------------------------------------------------------
	["controls.pad.ButtonA"] = { en = "A", ru = "A" },
	["controls.pad.ButtonB"] = { en = "B", ru = "B" },
	["controls.pad.ButtonX"] = { en = "X", ru = "X" },
	["controls.pad.ButtonY"] = { en = "Y", ru = "Y" },
	["controls.pad.ButtonL1"] = { en = "LB", ru = "LB" },
	["controls.pad.ButtonR1"] = { en = "RB", ru = "RB" },
	["controls.pad.ButtonL2"] = { en = "LT", ru = "LT" },
	["controls.pad.ButtonR2"] = { en = "RT", ru = "RT" },
	["controls.pad.ButtonL3"] = { en = "LS", ru = "LS" },
	["controls.pad.ButtonR3"] = { en = "RS", ru = "RS" },
	["controls.pad.DPadUp"] = { en = "D-pad ↑", ru = "Крестовина ↑" },
	["controls.pad.DPadDown"] = { en = "D-pad ↓", ru = "Крестовина ↓" },
	["controls.pad.DPadLeft"] = { en = "D-pad ←", ru = "Крестовина ←" },
	["controls.pad.DPadRight"] = { en = "D-pad →", ru = "Крестовина →" },
	["controls.pad.ButtonStart"] = { en = "Menu", ru = "Меню" },
	["controls.pad.ButtonSelect"] = { en = "View", ru = "Обзор" },
	["controls.pad.Thumbstick1"] = { en = "Left stick", ru = "Левый стик" },
	["controls.pad.Thumbstick2"] = { en = "Right stick", ru = "Правый стик" },

	-- hint templates ------------------------------------------------------------------------------
	["controls.chord"] = { en = "{1}+{2}", ru = "{1}+{2}" },
	["controls.hold"] = { en = "Hold {1}", ru = "Удерживайте {1}" },
	["controls.press"] = { en = "Press {1}", ru = "Нажмите {1}" },
	["controls.tap"] = { en = "Tap {1}", ru = "Коснитесь {1}" },
	["controls.hint"] = { en = "{1} — {2}", ru = "{1} — {2}" },

	-- camera --------------------------------------------------------------------------------------
	["controls.lock.on"] = { en = "Camera lock: ON", ru = "Фиксация камеры: ВКЛ" },
	["controls.lock.off"] = { en = "Camera lock: OFF", ru = "Фиксация камеры: ВЫКЛ" },
	["controls.camera.Follow"] = { en = "Follow camera", ru = "Камера за игроком" },
	["controls.camera.Spectate"] = { en = "Spectator camera", ru = "Камера наблюдателя" },
	["controls.camera.Photo"] = { en = "Photo mode", ru = "Фоторежим" },
	["controls.photo.on"] = { en = "Photo mode", ru = "Фоторежим" },
	["controls.photo.off"] = { en = "Photo mode closed", ru = "Фоторежим закрыт" },
	["controls.photo.hint"] = {
		en = "WASD move · Q/E down/up · RMB look · Shift fast · Wheel zoom · Backspace exit",
		ru = "WASD — движение · Q/E — вниз/вверх · ПКМ — обзор · Shift — быстрее · Колесо — зум · Backspace — выход",
	},
	["controls.photo.hint.gamepad"] = {
		en = "Sticks move/look · LT/RT down/up · B exit",
		ru = "Стики — движение/обзор · LT/RT — вниз/вверх · B — выход",
	},
	["controls.touch.look"] = { en = "Drag to look around", ru = "Проведите пальцем, чтобы осмотреться" },

	-- spectating ----------------------------------------------------------------------------------
	["controls.spectate.title"] = { en = "Spectating", ru = "Наблюдение" },
	["controls.spectate.hint"] = { en = "{1} / {2} — switch player", ru = "{1} / {2} — сменить игрока" },
	["controls.spectate.none"] = { en = "No one left to watch", ru = "Не за кем наблюдать" },
}
