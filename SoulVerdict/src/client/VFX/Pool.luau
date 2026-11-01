--!strict
-- VFX/Pool: tiny object pool for client VFX instances (parts, models, guis, emitter hosts).
-- Pooled objects are never destroyed while pooled: they are "parked" (moved far away / hidden) and handed
-- out again by Get(). Every VFX module allocates through pools so a busy fight creates (almost) no new
-- instances after warm-up.
--
--   local pool = Pool.new(factory: () -> T, opts?) -> Pool<T>
--       opts = { Max: number? [64]  (objects kept when released; extra ones are destroyed),
--                Reset: ((T) -> ())?  (called on Release, before parking),
--                Name: string? (debug) }
--   pool:Get() -> T                 a free object (or a new one from factory())
--   pool:Release(obj)               give it back (calls Reset, parks BaseParts/Models, keeps <= Max)
--   pool:Prewarm(n)                 create up to n free objects now
--   pool:Counts() -> (free, live)   live = handed out and not yet released
--   pool:Clear()                    destroy every FREE object (live ones are released later as usual)
-- Module helpers:
--   Pool.PARK                        CFrame far outside every map (y = 25000)
--   Pool.Park(obj)                   parks a BasePart (CFrame + Transparency 1) or a Model (PivotTo)
--   Pool.Owner(obj) -> Pool?         the pool an object belongs to (weak map)
--   Pool.ReleaseAny(obj)             Release through the owner pool, or Destroy when it has none
-- Lune-safe at require time (no services touched).

local Pool = {}
Pool.__index = Pool

Pool.PARK = CFrame.new(0, 25000, 0)

export type Pool<T> = {
	Get: (self: Pool<T>) -> T,
	Release: (self: Pool<T>, obj: T) -> (),
	Prewarm: (self: Pool<T>, n: number) -> (),
	Counts: (self: Pool<T>) -> (number, number),
	Clear: (self: Pool<T>) -> (),
	Name: string,
}

type PoolImpl = {
	_factory: () -> any,
	_reset: ((any) -> ())?,
	_free: { any },
	_live: number,
	_max: number,
	Name: string,
}

local owners: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any
local livePool: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any

function Pool.Park(obj: any)
	if typeof(obj) ~= "Instance" then
		return
	end
	if obj:IsA("BasePart") then
		obj.CFrame = Pool.PARK
		obj.Transparency = 1
	elseif obj:IsA("Model") then
		local ok = pcall(function()
			obj:PivotTo(Pool.PARK)
		end)
		if not ok then
			for _, d in obj:GetDescendants() do
				if d:IsA("BasePart") then
					d.CFrame = Pool.PARK
				end
			end
		end
	end
end

function Pool.new<T>(factory: () -> T, opts: { Max: number?, Reset: ((T) -> ())?, Name: string? }?): Pool<T>
	local o = opts or {}
	local self: PoolImpl = {
		_factory = factory :: any,
		_reset = o.Reset :: any,
		_free = {},
		_live = 0,
		_max = o.Max or 64,
		Name = o.Name or "Pool",
	}
	return setmetatable(self :: any, Pool) :: any
end

function Pool.Get(self: PoolImpl): any
	local free = self._free
	local n = #free
	local obj
	if n > 0 then
		obj = free[n]
		free[n] = nil
	else
		obj = self._factory()
		owners[obj] = self
	end
	livePool[obj] = true
	self._live += 1
	return obj
end

function Pool.Release(self: PoolImpl, obj: any)
	if obj == nil or not livePool[obj] then
		return -- double release / foreign object
	end
	livePool[obj] = nil
	self._live = math.max(0, self._live - 1)
	if typeof(obj) == "Instance" and obj.Parent == nil and not obj:IsA("Model") then
		-- destroyed (or detached) while live: just forget it
		owners[obj] = nil
		return
	end
	local reset = self._reset
	if reset then
		local ok, err = pcall(reset, obj)
		if not ok then
			warn("[VFX.Pool] reset failed in " .. self.Name .. ": " .. tostring(err))
			pcall(function()
				obj:Destroy()
			end)
			owners[obj] = nil
			return
		end
	end
	if #self._free >= self._max then
		owners[obj] = nil
		if typeof(obj) == "Instance" then
			obj:Destroy()
		elseif type(obj) == "table" and type(obj.Destroy) == "function" then
			obj:Destroy()
		end
		return
	end
	Pool.Park(obj)
	table.insert(self._free, obj)
end

function Pool.Prewarm(self: PoolImpl, n: number)
	for _ = #self._free + 1, n do
		local obj = self._factory()
		owners[obj] = self
		Pool.Park(obj)
		table.insert(self._free, obj)
	end
end

function Pool.Counts(self: PoolImpl): (number, number)
	return #self._free, self._live
end

function Pool.Clear(self: PoolImpl)
	for _, obj in self._free do
		owners[obj] = nil
		if typeof(obj) == "Instance" then
			obj:Destroy()
		elseif type(obj) == "table" and type(obj.Destroy) == "function" then
			obj:Destroy()
		end
	end
	table.clear(self._free)
end

function Pool.Owner(obj: any): any?
	return owners[obj]
end

function Pool.ReleaseAny(obj: any)
	local owner = owners[obj]
	if owner then
		owner:Release(obj)
	elseif typeof(obj) == "Instance" then
		obj:Destroy()
	end
end

return Pool
