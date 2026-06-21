-- GoogleMapsRBX/Core/PathSmoother.lua
-- Post-processes raw A* paths: string-pulling and Catmull-Rom spline.
-- ModuleScript: child of Core folder.

local PathSmoother = {}
PathSmoother.__index = PathSmoother

-- ── Constructor ───────────────────────────────────────────────────────────────

function PathSmoother.new(config)
	local self = setmetatable({}, PathSmoother)
	self._cfg       = config
	self._rayParams = self:_buildRayParams()
	return self
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Smooth a raw path ({nodes, edges}).
-- Returns a flat array of Vector3 waypoints.
function PathSmoother:Smooth(path)
	if not path or not path.nodes or #path.nodes < 2 then
		return path and path.nodes and
			self:_extractPositions(path.nodes) or {}
	end

	local positions = self:_extractPositions(path.nodes)

	-- String-pulling: up to 3 passes
	for pass = 1, 3 do
		local changed = false
		local i = 1
		while i <= #positions - 2 do
			if self:_lineOfSight(positions[i], positions[i+2]) then
				table.remove(positions, i+1)
				changed = true
			else
				i = i + 1
			end
		end
		if not changed then break end
	end

	return positions
end

-- Catmull-Rom interpolation along a smoothed position array.
-- t: 0..1 over the entire path.
function PathSmoother:GetSplinePoint(positions, t)
	if #positions == 0 then return Vector3.zero end
	if #positions == 1 then return positions[1] end

	local n       = #positions
	local scaled  = t * (n - 1)
	local seg     = math.floor(scaled)
	local frac    = scaled - seg

	seg = math.clamp(seg, 0, n - 2)

	local p0 = positions[math.max(1, seg)]
	local p1 = positions[seg + 1]
	local p2 = positions[math.min(n, seg + 2)]
	local p3 = positions[math.min(n, seg + 3)]

	return self:_catmullRom(p0, p1, p2, p3, frac)
end

-- ── Private ───────────────────────────────────────────────────────────────────

function PathSmoother:_extractPositions(nodes)
	local out = {}
	for _, node in ipairs(nodes) do
		out[#out+1] = node.position
	end
	return out
end

function PathSmoother:_lineOfSight(a, b)
	-- Cast at head height (1.25 studs up from floor) and at ground level.
	local up  = Vector3.new(0, 1.25, 0)
	local dir = b - a
	local r1  = workspace:Raycast(a + up, dir, self._rayParams)
	if r1 then return false end
	local r2  = workspace:Raycast(a + Vector3.new(0, 0.25, 0), dir, self._rayParams)
	if r2 then return false end
	return true
end

function PathSmoother:_catmullRom(p0, p1, p2, p3, t)
	-- Standard centripetal Catmull-Rom formula.
	local t2 = t * t
	local t3 = t2 * t
	local x = 0.5 * ((2*p1.X)
		+ (-p0.X + p2.X) * t
		+ (2*p0.X - 5*p1.X + 4*p2.X - p3.X) * t2
		+ (-p0.X + 3*p1.X - 3*p2.X + p3.X) * t3)
	local y = 0.5 * ((2*p1.Y)
		+ (-p0.Y + p2.Y) * t
		+ (2*p0.Y - 5*p1.Y + 4*p2.Y - p3.Y) * t2
		+ (-p0.Y + 3*p1.Y - 3*p2.Y + p3.Y) * t3)
	local z = 0.5 * ((2*p1.Z)
		+ (-p0.Z + p2.Z) * t
		+ (2*p0.Z - 5*p1.Z + 4*p2.Z - p3.Z) * t2
		+ (-p0.Z + 3*p1.Z - 3*p2.Z + p3.Z) * t3)
	return Vector3.new(x, y, z)
end

function PathSmoother:_buildRayParams()
	local params = RaycastParams.new()
	params.FilterType        = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true   -- non-collidable parts don't block sight lines
	local excludes = {}
	local vizFolder = workspace:FindFirstChild("ARGUS_Viz")
	if vizFolder then excludes[#excludes+1] = vizFolder end
	params.FilterDescendantsInstances = excludes
	return params
end

return PathSmoother
