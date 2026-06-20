-- GoogleMapsRBX/Movement/MovementTechDB.lua
-- Registry and dispatcher for all movement techniques.
-- New techniques can be registered at runtime; dispatch selects
-- the highest-value CanUse candidate by SuccessRate / Cost.
-- ModuleScript: child of Movement folder.

local MovementTechDB = {}
MovementTechDB.__index = MovementTechDB

function MovementTechDB.new(config)
	local self = setmetatable({}, MovementTechDB)
	self._cfg        = config
	self._techniques = {}   -- ordered list of {name, module}
	return self
end

-- Register a technique module (order matters: checked in registration order).
function MovementTechDB:Register(name, module)
	self._techniques[#self._techniques+1] = { name = name, module = module }
end

-- Return the best applicable technique for an edge + context.
-- excludeNames: optional set of technique names to skip.
function MovementTechDB:GetBestTechnique(edge, context, excludeNames)
	local best      = nil
	local bestValue = -math.huge

	for _, entry in ipairs(self._techniques) do
		if excludeNames and excludeNames[entry.name] then continue end

		local ok, canUse = pcall(function()
			return entry.module:CanUse(context)
		end)
		if not ok or not canUse then continue end

		local cost    = entry.module:EstimateCost(context)
		local success = entry.module:EstimateSuccessRate(context)
		local value   = success / math.max(0.01, cost)

		if value > bestValue then
			bestValue = value
			best      = entry
		end
	end

	return best and best.module or nil, best and best.name or nil
end

-- Get the next-best technique excluding a given name (for anti-stuck fallback).
function MovementTechDB:GetNextBestTechnique(edge, context, excludeName)
	local exclude = {}
	if excludeName then exclude[excludeName] = true end
	return self:GetBestTechnique(edge, context, exclude)
end

-- List all techniques that CanUse for a given context (for debugging).
function MovementTechDB:GetApplicable(context)
	local out = {}
	for _, entry in ipairs(self._techniques) do
		local ok, canUse = pcall(function()
			return entry.module:CanUse(context)
		end)
		if ok and canUse then
			out[#out+1] = {
				name        = entry.name,
				cost        = entry.module:EstimateCost(context),
				successRate = entry.module:EstimateSuccessRate(context),
				debug       = entry.module:DebugInfo(context),
			}
		end
	end
	-- Sort descending by value
	table.sort(out, function(a, b)
		local va = a.successRate / math.max(0.01, a.cost)
		local vb = b.successRate / math.max(0.01, b.cost)
		return va > vb
	end)
	return out
end

return MovementTechDB
