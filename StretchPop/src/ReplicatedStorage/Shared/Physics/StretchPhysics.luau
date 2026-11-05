--!strict
-- STRETCH-POP · Общая физика рогатки, резинок, отскоков и пробития.
-- Клиент использует её для симуляции и предпросмотра дуги, сервер — для валидации.
-- Одни и те же формулы на обеих сторонах = нет рассинхрона «у меня пробилось, а сервер не засчитал».

local Shared = script.Parent.Parent
local Types = require(Shared.Types)
local PhysicsConfig = require(Shared.Config.PhysicsConfig)
local GloveConfig = require(Shared.Config.GloveConfig)

export type StretchParams = {
	Stiffness: number, -- k одной резинки на земле (рогатка)
	AirStiffness: number, -- k резинки в воздухе (банджи)
	MaxStretch: number, -- x_max
	GrabRange: number,
	ImpactMass: number, -- m в E = ½mv²
	FlightMass: number,
	Restitution: number, -- упругость пружинного шара
}

export type Band = {
	Anchor: Vector3,
	Rest: number,
}

local StretchPhysics = {}

local function curve(statCurve: PhysicsConfig.StatCurve, level: number): number
	return math.min(statCurve.Base + statCurve.PerLevel * math.max(level, 0), statCurve.Max)
end

function StretchPhysics.Derive(stats: Types.PhysicalStats, gloveId: string?): StretchParams
	local glove = GloveConfig.Get(gloveId)
	local stiffness = curve(PhysicsConfig.Stiffness, stats.SpringPower)
	return {
		Stiffness = stiffness,
		AirStiffness = stiffness * PhysicsConfig.AirStiffnessScale,
		MaxStretch = curve(PhysicsConfig.MaxStretch, stats.Elasticity),
		GrabRange = curve(PhysicsConfig.GrabRange, stats.Elasticity),
		ImpactMass = curve(PhysicsConfig.ImpactMass, stats.SmashMass) * (1 + glove.ImpactMassBonus),
		FlightMass = PhysicsConfig.FlightMass,
		Restitution = curve(PhysicsConfig.Restitution, stats.SpringPower),
	}
end

function StretchPhysics.Gravity(): Vector3
	return Vector3.new(0, -workspace.Gravity * PhysicsConfig.FlightGravityScale, 0)
end

-- Квадратичное сопротивление воздуха: a = −c·|v|·v
function StretchPhysics.Drag(velocity: Vector3): Vector3
	return velocity * (-PhysicsConfig.AirDrag * velocity.Magnitude)
end

-- Резинка работает только на растяжение. F = k·x·û (x = d − L₀ > 0),
-- плюс радиальное демпфирование при удалении от якоря (гасит «йо-йо», не съедая тягу).
-- Возвращает силу и текущее растяжение x.
function StretchPhysics.BandForce(
	body: Vector3,
	anchor: Vector3,
	restLength: number,
	stiffness: number,
	velocity: Vector3,
	damping: number
): (Vector3, number)
	local offset = anchor - body
	local distance = offset.Magnitude
	if distance < 1e-4 then
		return Vector3.zero, 0
	end
	local stretch = distance - restLength
	if stretch <= 0 then
		return Vector3.zero, 0
	end
	local direction = offset / distance
	local force = direction * (stiffness * stretch)
	local radialSpeed = velocity:Dot(direction)
	if radialSpeed < 0 then
		force -= direction * (damping * radialSpeed)
	end
	return force, stretch
end

-- Энергия рогатки E = Σ ½·k·xᵢ² и скорость запуска v = √(2E/m) вдоль равнодействующей сил резинок.
-- Возвращает (скорость запуска, энергия, натяжение 0..1 относительно максимума для этих резинок).
function StretchPhysics.SlingshotLaunch(body: Vector3, bands: { Band }, params: StretchParams): (Vector3, number, number)
	local netForce = Vector3.zero
	local energy = 0
	local maxEnergy = 0
	for _, band in bands do
		local offset = band.Anchor - body
		local distance = offset.Magnitude
		maxEnergy += 0.5 * params.Stiffness * params.MaxStretch * params.MaxStretch
		if distance > 1e-4 then
			local stretch = math.clamp(distance - band.Rest, 0, params.MaxStretch)
			if stretch > 0 then
				netForce += (offset / distance) * (params.Stiffness * stretch)
				energy += 0.5 * params.Stiffness * stretch * stretch
			end
		end
	end
	if energy <= 0 or netForce.Magnitude < 1e-4 or maxEnergy <= 0 then
		return Vector3.zero, 0, 0
	end
	local direction = (netForce.Unit + Vector3.yAxis * PhysicsConfig.LaunchUpBias).Unit
	local speed = math.min(math.sqrt(2 * energy / params.FlightMass), PhysicsConfig.LaunchSpeedCap)
	return direction * speed, energy, math.clamp(energy / maxEnergy, 0, 1)
end

-- Максимальное растяжение среди резинок (для ограничения оттягивания).
function StretchPhysics.MaxBandStretch(body: Vector3, bands: { Band }): number
	local maxStretch = 0
	for _, band in bands do
		local stretch = (band.Anchor - body).Magnitude - band.Rest
		if stretch > maxStretch then
			maxStretch = stretch
		end
	end
	return maxStretch
end

function StretchPhysics.MaxLaunchSpeed(params: StretchParams): number
	-- две резинки на полном натяжении: v = x_max·√(2k/m)
	return math.min(params.MaxStretch * math.sqrt(2 * params.Stiffness / params.FlightMass), PhysicsConfig.LaunchSpeedCap)
end

-- Верхняя граница честной скорости: запуск, бамперы, гравитационный разгон до терминальной скорости.
function StretchPhysics.MaxPlausibleSpeed(params: StretchParams): number
	local gravity = workspace.Gravity * PhysicsConfig.FlightGravityScale
	local terminal = math.sqrt(gravity / PhysicsConfig.AirDrag)
	local candidate = math.max(StretchPhysics.MaxLaunchSpeed(params), PhysicsConfig.BouncySurfaceMaxSpeed, terminal)
	return math.min(candidate, PhysicsConfig.MaxFlightSpeed)
end

function StretchPhysics.KineticEnergy(mass: number, speed: number): number
	return 0.5 * mass * speed * speed
end

-- Прочность препятствия в тех же единицах энергии: D = ½·m_base·v_req²·множитель_тира
function StretchPhysics.DurabilityFromSpeed(requiredSpeed: number, tierMultiplier: number): number
	return 0.5 * PhysicsConfig.ImpactMass.Base * requiredSpeed * requiredSpeed * tierMultiplier
end

-- Минимальная скорость, при которой ½mv² ≥ D
function StretchPhysics.SpeedToBreak(durability: number, impactMass: number): number
	return math.sqrt(2 * durability / math.max(impactMass, 1e-3))
end

-- Эффективная скорость удара: нормальная составляющая, но не меньше 60% полной
-- (касательный удар тоже ломает, но слабее лобового).
function StretchPhysics.ImpactSpeed(velocity: Vector3, normal: Vector3): number
	return math.max(math.abs(velocity:Dot(normal)), velocity.Magnitude * 0.6)
end

function StretchPhysics.CanSmash(durability: number, impactMass: number, impactSpeed: number): boolean
	return StretchPhysics.KineticEnergy(impactMass, impactSpeed) >= durability
end

-- Отражение с сохранением импульса: касательная часть сохраняется (·tangentKeep),
-- нормальная разворачивается и масштабируется коэффициентом восстановления e.
function StretchPhysics.Reflect(velocity: Vector3, normal: Vector3, restitution: number, tangentKeep: number): Vector3
	local normalSpeed = velocity:Dot(normal)
	if normalSpeed >= 0 then
		return velocity
	end
	local normalPart = normal * normalSpeed
	local tangentPart = velocity - normalPart
	return tangentPart * tangentKeep - normalPart * restitution
end

-- Полунеявный Эйлер (симплектический): сначала скорость, потом позиция.
function StretchPhysics.Integrate(position: Vector3, velocity: Vector3, acceleration: Vector3, dt: number): (Vector3, Vector3)
	local newVelocity = velocity + acceleration * dt
	return position + newVelocity * dt, newVelocity
end

function StretchPhysics.ClampSpeed(velocity: Vector3, maxSpeed: number): Vector3
	local speed = velocity.Magnitude
	if speed > maxSpeed then
		return velocity * (maxSpeed / speed)
	end
	return velocity
end

function StretchPhysics.UpgradeCost(level: number): number
	local upgrade = PhysicsConfig.StatUpgrade
	return math.floor(upgrade.BaseCost * upgrade.CostGrowth ^ math.max(level, 0) + 0.5)
end

function StretchPhysics.IsFiniteVector(value: Vector3, limit: number): boolean
	local x, y, z = value.X, value.Y, value.Z
	return x == x and y == y and z == z and math.abs(x) < limit and math.abs(y) < limit and math.abs(z) < limit
end

return StretchPhysics
