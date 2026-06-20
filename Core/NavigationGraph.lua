-- GoogleMapsRBX/Core/NavigationGraph.lua
-- Builds and maintains a typed edge graph from WorldScanner nodes.
-- Edges encode traversal type, cost, and optional moving-part reference.
-- ModuleScript: child of Core folder.

local NavigationGraph = {}
NavigationGraph.__index = NavigationGraph

-- ── Constructor ───────────────────────────────────────────────────────────────

function NavigationGraph.new(config, observationSystem)
	local self = setmetatable({}, NavigationGraph)
	self._cfg      = config
	self._obs      = observationSystem
	self._nodes    = {}     -- [hashKey] = node
	self._edges    = {}     -- [nodeId]  = {Edge, ...}
	self._nodeById = {}     -- [nodeId]  = node
	self._nextId   = 1
	self.version   = 0
	self.nodeCount = 0
	self.edgeCount = 0
	self.onChanged = nil    -- callback()
	self._rayParams = self:_buildRayParams()
	return self
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Ingest nodes from WorldScanner (replaces current node set).
function NavigationGraph:IngestNodes(rawNodes)
	self._nodes    = {}
	self._edges    = {}
	self._nodeById = {}
	self._nextId   = 1
	self.nodeCount  = 0

	for key, raw in pairs(rawNodes) do
		local node = {
			id       = self._nextId,
			hashKey  = key,
			position = raw.position,
			tags     = raw.tags,
			part     = raw.part,
			movingPart = raw.movingPart,
		}
		self._nextId   = self._nextId + 1
		self._nodes[key]         = node
		self._nodeById[node.id]  = node
		self.nodeCount = self.nodeCount + 1
	end

	task.spawn(function()
		self:BuildEdges()
	end)
end

-- Rebuild all edges from current node set.
function NavigationGraph:BuildEdges()
	self._edges    = {}
	self.edgeCount = 0
	local iter     = 0

	for key, node in pairs(self._nodes) do
		iter = iter + 1
		if iter % 20 == 0 then task.wait() end
		self._edges[node.id] = {}
		self:_generateEdgesFrom(node)
	end

	self.version = self.version + 1
	if self.onChanged then self.onChanged() end
end

-- Get edges from a node id.
function NavigationGraph:GetEdges(nodeId)
	return self._edges[nodeId] or {}
end

-- Find the nearest node to a world position.
function NavigationGraph:GetNearestNode(position)
	local best  = nil
	local bestD = math.huge
	-- Check the cell and 26 neighbors
	local s = self._cfg.NodeSpacing
	local cx = math.floor(position.X / s)
	local cy = math.floor(position.Y / s)
	local cz = math.floor(position.Z / s)
	for dx = -2, 2 do
		for dy = -2, 2 do
			for dz = -2, 2 do
				local key = string.format("%d,%d,%d", cx+dx, cy+dy, cz+dz)
				local node = self._nodes[key]
				if node then
					local d = (node.position - position).Magnitude
					if d < bestD then
						bestD = d
						best  = node
					end
				end
			end
		end
	end
	-- Fallback: linear search (costly but rare)
	if not best then
		for _, node in pairs(self._nodes) do
			local d = (node.position - position).Magnitude
			if d < bestD then
				bestD = d
				best  = node
			end
		end
	end
	return best
end

function NavigationGraph:GetNodeById(id)
	return self._nodeById[id]
end

function NavigationGraph:GetAllNodes()
	return self._nodes
end

-- Remove nodes and edges in a sphere; caller re-triggers scan.
function NavigationGraph:InvalidateRegion(center, radius)
	local toRemove = {}
	for key, node in pairs(self._nodes) do
		if (node.position - center).Magnitude <= radius then
			toRemove[#toRemove+1] = key
		end
	end
	for _, key in ipairs(toRemove) do
		local node = self._nodes[key]
		if node then
			self._edges[node.id] = nil
			self._nodeById[node.id] = nil
			self._nodes[key] = nil
			self.nodeCount = self.nodeCount - 1
		end
	end
	self.version = self.version + 1
	if self.onChanged then self.onChanged() end
end

-- ── Edge generation ───────────────────────────────────────────────────────────

function NavigationGraph:_generateEdgesFrom(node)
	local cfg     = self._cfg
	local pos     = node.position
	local s       = cfg.NodeSpacing
	local cx      = math.floor(pos.X / s)
	local cy      = math.floor(pos.Y / s)
	local cz      = math.floor(pos.Z / s)
	local maxHoriz = cfg.NodeSpacing * 1.5
	local edges   = self._edges[node.id]

	-- Iterate 26-neighbor cells
	for dx = -3, 3 do
		for dy = -4, 4 do
			for dz = -3, 3 do
				if dx == 0 and dy == 0 and dz == 0 then continue end
				local key  = string.format("%d,%d,%d", cx+dx, cy+dy, cz+dz)
				local neighbor = self._nodes[key]
				if not neighbor then continue end

				local diff    = neighbor.position - pos
				local horizD  = Vector3.new(diff.X, 0, diff.Z).Magnitude
				local vertD   = diff.Y

				-- ── Walk edge ──
				if horizD <= maxHoriz and math.abs(vertD) <= 1.5 then
					if self:_hasClearance(pos, neighbor.position) then
						self:_addEdge(edges, node, neighbor, "Walk", cfg.EdgeCost.Walk)
					end
				end

				-- ── Jump edge (going up) ──
				if vertD >= 1.5 and vertD <= cfg.MaxJumpHeight
					and horizD <= cfg.MaxJumpHorizontal then
					if self:_jumpArcClears(pos, neighbor.position) then
						local cost = cfg.EdgeCost.Jump
						if neighbor.tags.movingPlatform then
							cost = cost * cfg.CostMult.MovingPlatform
							-- add wait cost from observation
							local trkId = neighbor.movingPart and
								self._obs._partMap and
								self._obs._partMap[neighbor.movingPart]
							if trkId then
								local jt = self._obs:GetOptimalJumpTime(trkId, pos)
								if jt then cost = cost + jt.waitTime end
							end
						end
						self:_addEdge(edges, node, neighbor, "Jump", cost,
							neighbor.movingPart)
					end
				end

				-- ── Fall edge (going down) ──
				if vertD <= -0.5 and vertD >= -cfg.MaxFallDistance
					and horizD <= maxHoriz then
					if not self:_floorBetween(pos, neighbor.position) then
						local cost = cfg.EdgeCost.Fall
						if neighbor.tags.hazard then cost = cost * cfg.CostMult.Hazard end
						self:_addEdge(edges, node, neighbor, "Fall", cost)
					end
				end

				-- ── Climb Ladder ──
				if (node.tags.ladder or neighbor.tags.ladder)
					and horizD <= s
					and math.abs(vertD) <= s * 2 then
					self:_addEdge(edges, node, neighbor, "ClimbLadder",
						cfg.EdgeCost.ClimbLadder)
				end

				-- ── Climb Truss ──
				if (node.tags.truss or neighbor.tags.truss)
					and horizD <= s
					and math.abs(vertD) <= s * 2 then
					self:_addEdge(edges, node, neighbor, "ClimbTruss",
						cfg.EdgeCost.ClimbTruss)
				end

				-- ── Swim ──
				if node.tags.water and neighbor.tags.water
					and horizD <= maxHoriz then
					self:_addEdge(edges, node, neighbor, "Swim", cfg.EdgeCost.Swim)
				end

				-- ── Gap cross (long jump over gap) ──
				if node.tags.hasGap and horizD > maxHoriz
					and horizD <= cfg.MaxJumpHorizontal
					and math.abs(vertD) <= cfg.MaxJumpHeight then
					if self:_jumpArcClears(pos, neighbor.position) then
						self:_addEdge(edges, node, neighbor, "GapCross",
							cfg.EdgeCost.GapCross)
					end
				end

				-- ── Ride conveyor ──
				if node.tags.conveyor and node.movingPart then
					local bv = node.movingPart:FindFirstChildWhichIsA("BodyVelocity")
					if bv then
						local convDir = bv.Velocity.Unit
						local dot = convDir:Dot(diff.Unit)
						if dot > 0.7 and horizD <= cfg.ScanRadius * 0.5 then
							self:_addEdge(edges, node, neighbor, "RideConveyor",
								cfg.EdgeCost.RideConveyor, node.movingPart)
						end
					end
				end

				-- ── Ride moving platform ──
				if node.tags.movingPlatform and node.movingPart
					and not node.tags.conveyor then
					-- Connect vertically if elevator-like
					if horizD <= s and math.abs(vertD) <= cfg.MaxJumpHeight * 3 then
						local cost = cfg.EdgeCost.RideElevator
						local trkId = self._obs._partMap and
							self._obs._partMap[node.movingPart]
						if trkId then
							local jt = self._obs:GetOptimalJumpTime(trkId, pos)
							if jt then cost = cost + jt.waitTime * 0.5 end
						end
						self:_addEdge(edges, node, neighbor, "RideElevator",
							cost, node.movingPart)
					else
						self:_addEdge(edges, node, neighbor, "RidePlatform",
							cfg.EdgeCost.RidePlatform, node.movingPart)
					end
				end
			end
		end
	end
end

function NavigationGraph:_addEdge(edgeList, from, to, edgeType, cost, movingPart)
	local tags    = to.tags
	local adjCost = cost
	if tags.water   then adjCost = adjCost * self._cfg.CostMult.Water end
	if tags.hazard  then adjCost = adjCost * self._cfg.CostMult.Hazard end

	edgeList[#edgeList+1] = {
		fromId      = from.id,
		toId        = to.id,
		fromPos     = from.position,
		toPos       = to.position,
		edgeType    = edgeType,
		cost        = adjCost,
		movingPart  = movingPart,
	}
	self.edgeCount = self.edgeCount + 1
end

-- ── Geometry helpers ─────────────────────────────────────────────────────────

function NavigationGraph:_hasClearance(fromPos, toPos)
	local midPos = (fromPos + toPos) * 0.5 + Vector3.new(0, 1.25, 0)
	local diff   = (toPos - fromPos)
	local result = workspace:Raycast(
		fromPos + Vector3.new(0, 1.25, 0),
		diff,
		self._rayParams
	)
	return result == nil
end

function NavigationGraph:_jumpArcClears(fromPos, toPos)
	-- Sample parabolic arc at 5 points and raycast between consecutive points.
	-- v0y = sqrt(2 * g * maxJump), g = ~196 (Roblox workspace.Gravity default)
	local g       = workspace.Gravity
	local maxH    = self._cfg.MaxJumpHeight
	local v0y     = math.sqrt(2 * g * maxH)
	local diff    = toPos - fromPos
	local horizD  = Vector3.new(diff.X, 0, diff.Z).Magnitude
	if horizD < 0.1 then return true end
	local horizDir = Vector3.new(diff.X, 0, diff.Z).Unit
	local horizSpd = horizD / (2 * v0y / g)  -- approximate horizontal speed
	local tArc    = horizD / math.max(horizSpd, 0.01)
	local steps   = 5
	local lastPt  = fromPos + Vector3.new(0, 0.5, 0)
	local clear   = true
	for i = 1, steps do
		local t    = tArc * i / steps
		local xz   = horizDir * horizSpd * t
		local y    = fromPos.Y + v0y * t - 0.5 * g * t * t
		local pt   = Vector3.new(fromPos.X + xz.X, y, fromPos.Z + xz.Z)
		local seg  = pt - lastPt
		local r    = workspace:Raycast(lastPt, seg, self._rayParams)
		if r then clear = false break end
		lastPt = pt
	end
	return clear
end

function NavigationGraph:_floorBetween(fromPos, toPos)
	-- Returns true if there's a floor between two vertically separated nodes.
	local dir    = Vector3.new(0, toPos.Y - fromPos.Y, 0)
	local result = workspace:Raycast(fromPos + Vector3.new(0, -0.1, 0), dir, self._rayParams)
	if result and result.Normal.Y > self._cfg.MinSurfaceNormal then
		-- Check if this floor is between the two nodes
		local hitY = result.Position.Y
		if hitY > toPos.Y + 0.5 and hitY < fromPos.Y - 0.5 then
			return true
		end
	end
	return false
end

function NavigationGraph:_buildRayParams()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local excludes = {}
	local vizFolder = workspace:FindFirstChild("ARGUS_Viz")
	if vizFolder then excludes[#excludes+1] = vizFolder end
	params.FilterDescendantsInstances = excludes
	return params
end

return NavigationGraph
