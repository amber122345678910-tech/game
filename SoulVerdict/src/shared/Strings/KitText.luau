--!strict
-- Combat feedback text (VFX/DamageNumbers, FxController, CombatController, client kits). Lune-safe.
-- Keys: "fx.*" = world popups (Undertale style, short and uppercase), "combat.*" = HUD feedback for refused input.
return {
	-- world popups
	["fx.miss"] = { en = "MISS", ru = "ПРОМАХ" },
	["fx.parry"] = { en = "PARRY!", ru = "ПАРИРОВАНО!" },
	["fx.blocked"] = { en = "BLOCK", ru = "БЛОК" },
	["fx.guardBreak"] = { en = "GUARD BREAK", ru = "ЗАЩИТА СЛОМАНА" },
	["fx.counter"] = { en = "COUNTER", ru = "КОНТРУДАР" },
	["fx.dodgeDrain"] = { en = "-{1} DODGE", ru = "-{1} УКЛОН." },
	["fx.immune"] = { en = "IMMUNE", ru = "НЕУЯЗВИМ" },
	["fx.revived"] = { en = "REVIVED", ru = "ВОЗРОЖДЁН" },
	-- refused input (CombatController.Feedback kinds)
	["combat.Cooldown"] = { en = "Not ready", ru = "Ещё не готово" },
	["combat.NoTarget"] = { en = "No target", ru = "Нет цели" },
	["combat.NoUlt"] = { en = "Ultimate not charged", ru = "Ульта не заряжена" },
	["combat.NoAmmo"] = { en = "Reloading", ru = "Перезарядка" },
	["combat.NoCharges"] = { en = "No dash charges", ru = "Нет зарядов рывка" },
	["combat.Suppressed"] = { en = "Can't act now", ru = "Сейчас нельзя" },
	["combat.Rejected"] = { en = "Cancelled", ru = "Отменено" },
}
