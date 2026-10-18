--!nocheck
-- "fast": the core scenario with event timers shortened (patched in Config before the game boots) so that
-- every server event happens several times in 12.5 simulated minutes: Supercell from 1:00 every 2:30,
-- Ball lightning from 2:00 every 3:20, Rainbow from 3:00 every 4:20, Perun 1/15 on island 5, city fills fast.
local core = require("./core")

return {
	run = function(S)
		return core.Core.run(S, {
			patchConfig = function(Config)
				local E = Config.Events
				E.Supercell.Period, E.Supercell.Offset, E.Supercell.Duration = 150, 60, 40
				E.BallLightning.Period, E.BallLightning.Offset, E.BallLightning.Duration = 200, 120, 60
				E.Rainbow.Period, E.Rainbow.Offset = 260, 180
				E.Perun.Chance = 1 / 15
				E.WarnBefore = 15
				Config.City.PointsBase = 4
				Config.City.PointsPerPlayer = 2
			end,
			supercellAt = 60,
			ballAt = 120,
			rainbowAt = 180,
			checkSupercellRate = false,
		})
	end,
}
