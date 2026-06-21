-- GoogleMapsRBX/Core/WorldScanner.lua
-- Converts raw Roblox geometry into a spatial hash of walkable nodes.
-- Runs asynchronously via coroutines to stay within frame budget.
-- ModuleScript: child of Core folder.

local WorldScanner = {}
WorldScanner.__index = WorldScanner

-- ── Constructor ───────────────────────────────────────────────────────────────

function WorldScanner.new(config, observationSystem)
	local self = setmetatable({}, WorldScanner)
	self._cfg             = config
	self._obs             = observationSystem
	self._nodes           = {}      -- [hashKey] = NodeData
	self._dirtyCells      = {}      -- [hashKey] = true
	self._specialDetected = {}      -- [hashKey] = true; skip re-detection on repeat scans
	self._rayParams       = self:_buildRayParams()
	self._scanTime        = 0       -- ms of last full scan
	self._totalNodes      = 0
	self.onScanComplete   = nil     -- callback(nodeCount)
	return self
end

-- ── Public API ────────────────────────────────────────────────────────────────

function WorldScanner:GetNodes()
	return self._nodes
end

function WorldScanner:GetNodeCount()
	return self._totalNodes
end

function WorldScanner:GetScanTime()
	return self._scanTime
end

-- Main entry: start an async scan around origin.
function WorldScanner:ScanAround(origin, character)
	self._character = character
	self._rayParams = self:_buildRayParams()
	task.spawn(function()
		local t0 = tick()
		self:_fullScan(origin)
		self._scanTime = math.floor((tick() - t0) * 1000)
		if self.onScanComplete then
			self.onScanComplete(self._totalNodes)
		end
	end)
end

-- Lightweight incremental update: only rescan dirty cells.
function WorldScanner:UpdateAround(origin)
	task.spawn(function()
		self:_incrementalScan(origin)
	end)
end

-- Mark cells near a changed part as dirty.
function WorldScanner:InvalidateNear(position, radius)
	local spacing = self._cfg.NodeSpacing
	local cells   = math.ceil(radius / spacing)
	for dx = -cells, cells do
		for dy = -cells, cells do
			for dz = -cells, cells do
				local key = self:_hashVec(
					position + Vector3.new(dx*spacing, dy*spacing, dz*spacing)
				)
				self._dirtyCells[key] = true
			end
		end
	end
end

-- ── Spatial hash helpers ──────────────────────────────────────────────────────

function WorldScanner:_hashVec(pos)
	local s = self._cfg.NodeSpacing
	return string.format("%d,%d,%d",
		math.floor(pos.X / s),
		math.floor(pos.Y / s),
		math.floor(pos.Z / s)
	)
end

function WorldScanner:_hashXYZ(x, y, z)
	local s = self._cfg.NodeSpacing
	return string.format("%d,%d,%d",
		math.floor(x / s),
		math.floor(y / s),
		math.floor(z / s)
	)
end

-- ── Full scan ─────────────────────────────────────────────────────────────────

function WorldScanner:_fullScan(origin)
	local cfg      = self._cfg
	local radius   = cfg.ScanRadius
	local spacing  = cfg.NodeSpacing
	local stepsXZ  = math.ceil(radius / spacing)
	local stepsY   = math.ceil((cfg.ScanYRange or 16) / spacing)
	local newNodes = {}
	local count    = 0
	local iter     = 0
	local YIELD_MAIN = cfg.ScanYieldInterval or 1000

	-- Cylinder scan: full XZ radius, limited Y range.
	-- Old: 27³ = 19,683 iters. New (ScanYRange=16): 27 × 9 × 27 = 6,561 iters → 3× fewer probes.
	for xi = -stepsXZ, stepsXZ do
		for yi = -stepsY, stepsY do
			for zi = -stepsXZ, stepsXZ do
				iter = iter + 1
				if iter % YIELD_MAIN == 0 then task.wait() end

				local gx = origin.X + xi * spacing
				local gy = origin.Y + yi * spacing
				local gz = origin.Z + zi * spacing

				-- Cylinder cull: XZ only (Y is already bounded by stepsY loop).
				local dx = gx - origin.X
				local dz = gz - origin.Z
				if dx*dx + dz*dz > radius*radius then continue end

				local node = self:_probeFloor(gx, gy + spacing, gz)
				if node then
					local key = self:_hashVec(node.position)
					if not newNodes[key] then
						newNodes[key] = node
						count = count + 1
					end
				end
			end
		end
	end

	-- Special detection: skip nodes already tagged; only process newcomers.
	-- On a steady-state scan (player barely moved) this is near-zero work.
	local detected  = self._specialDetected
	local passIter  = 0
	for key, node in pairs(newNodes) do
		if not detected[key] then
			passIter = passIter + 1
			if passIter % 100 == 0 then task.wait() end
			self:_specialDetect(node)
			detected[key] = true
		end
	end
	-- Prune cache entries that left the scan radius.
	for key in pairs(detected) do
		if not newNodes[key] then detected[key] = nil end
	end

	self._nodes      = newNodes
	self._totalNodes = count
end

-- ── Incremental scan ──────────────────────────────────────────────────────────

function WorldScanner:_incrementalScan(origin)
	local dirty = self._dirtyCells
	self._dirtyCells = {}
	local iter = 0
	for key in pairs(dirty) do
		iter = iter + 1
		if iter % 200 == 0 then task.wait() end
		local parts = string.split(key, ",")
		local ns = self._cfg.NodeSpacing
		local cx = tonumber(parts[1]) * ns + ns * 0.5
		local cy = tonumber(parts[2]) * ns + ns * 0.5
		local cz = tonumber(parts[3]) * ns + ns * 0.5
		local node = self:_probeFloor(cx, cy + ns, cz)
		if node then
			self._nodes[key] = node
			-- Re-detect: geometry changed so cached tags are stale.
			self._specialDetected[key] = nil
			self:_specialDetect(node)
			self._specialDetected[key] = true
		else
			if self._nodes[key] then
				self._nodes[key] = nil
				self._totalNodes = self._totalNodes - 1
			end
			self._specialDetected[key] = nil
		end
	end
end

-- ── Floor probe ───────────────────────────────────────────────────────────────

function WorldScanner:_probeFloor(ox, oy, oz)
	local cfg    = self._cfg
	local origin = Vector3.new(ox, oy, oz)
	local dir    = Vector3.new(0, -cfg.NodeSpacing * 2, 0)
	local result = workspace:Raycast(origin, dir, self._rayParams)
	if not result then return nil end
	if result.Normal.Y < cfg.MinSurfaceNormal then return nil end

	local hitPos = result.Position
	-- Clearance check
	local clearResult = workspace:Raycast(
		hitPos + Vector3.new(0, 0.1, 0),
		Vector3.new(0, cfg.ClearanceHeight, 0),
		self._rayParams
	)
	if clearResult then return nil end

	return {
		position = hitPos,
		normal   = result.Normal,
		part     = result.Instance,
		tags     = {},
	}
end

-- ── Special detection ─────────────────────────────────────────────────────────

function WorldScanner:_specialDetect(node)
	local cfg = self._cfg
	local pos = node.position

	-- ── Walls (4 cardinal rays horizontal) ──
	local wallDirs = {
		Vector3.new(1,0,0), Vector3.new(-1,0,0),
		Vector3.new(0,0,1), Vector3.new(0,0,-1),
	}
	for _, wd in ipairs(wallDirs) do
		local r = workspace:Raycast(pos + Vector3.new(0,1,0), wd * 2, self._rayParams)
		if r and math.abs(r.Normal.Y) < 0.3 then
			node.tags.nearWall = true
			break
		end
	end

	-- ── Gaps (downward probe 2 studs ahead in each direction) ──
	for _, wd in ipairs(wallDirs) do
		local ahead = pos + wd * 2
		local gr = workspace:Raycast(
			ahead + Vector3.new(0, 0.5, 0),
			Vector3.new(0, -cfg.NodeSpacing * 2, 0),
			self._rayParams
		)
		if not gr then
			node.tags.hasGap = true
			break
		end
	end

	-- ── Part-based detection ──
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { self._character or workspace }

	local nearby = workspace:GetPartBoundsInRadius(pos, cfg.SpecialScanRadius, overlapParams)
	for _, part in ipairs(nearby) do
		-- Ladder tag
		if part:IsA("TrussPart") then
			node.tags.truss = true
		end
		if part:HasTag(cfg.LadderTagName) or string.find(part.Name:lower(), "ladder") then
			node.tags.ladder = true
		end

		-- Moving platform
		local linVel = part.AssemblyLinearVelocity
		local angVel = part.AssemblyAngularVelocity
		if linVel.Magnitude > 0.1 or angVel.Magnitude > 0.01 then
			node.tags.movingPlatform = true
			node.movingPart = part
			self._obs:Track(part)
			-- Conveyor detection: BodyVelocity child
			if part:FindFirstChildWhichIsA("BodyVelocity") then
				node.tags.conveyor = true
			end
			-- Rotating platform
			if angVel.Magnitude > 0.01 then
				node.tags.rotating = true
			end
		end

		-- Conveyor tag
		if part:HasTag(cfg.ConveyorTagName) or string.find(part.Name:lower(), "conveyor") then
			node.tags.conveyor = true
			node.movingPart   = part
		end

		-- Door
		if part:HasTag(cfg.DoorTagName) or part:FindFirstChildWhichIsA("ProximityPrompt") then
			node.tags.door = true
		end

		-- Hazard detection
		if part:HasTag(cfg.HazardTagName) or not part.CastShadow then
			node.tags.hazard = true
		else
			local nameLower = part.Name:lower()
			for _, pattern in ipairs(cfg.HazardNamePatterns) do
				if string.find(nameLower, pattern) then
					node.tags.hazard = true
					break
				end
			end
		end

		-- Water: check terrain material
		if part:IsA("Terrain") then
			local region = Region3.new(pos - Vector3.new(1,1,1), pos + Vector3.new(1,1,1))
			local resolution = 4
			local ok, mats = pcall(function()
				return workspace.Terrain:ReadVoxels(region, resolution)
			end)
			if ok and mats then
				for _, row in ipairs(mats) do
					for _, col in ipairs(row) do
						for _, mat in ipairs(col) do
							if mat == Enum.Material.Water then
								node.tags.water = true
							end
						end
					end
				end
			end
		end

		-- Slope
		if node.normal and node.normal.Y < 0.9 and node.normal.Y >= cfg.MinSurfaceNormal then
			node.tags.slope = true
		end
	end
end

-- ── RaycastParams factory ──────────────────────────────────────────────────────

function WorldScanner:_buildRayParams()
	local params = RaycastParams.new()
	params.FilterType         = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide  = true   -- ignore non-collidable parts as surfaces
	local excludes = {}
	local vizFolder = workspace:FindFirstChild("ARGUS_Viz")
	if vizFolder then excludes[#excludes+1] = vizFolder end
	if self._character then excludes[#excludes+1] = self._character end
	params.FilterDescendantsInstances = excludes
	return params
end

return WorldScanner
