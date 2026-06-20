-- GoogleMapsRBX/Core/AStarPathfinder.lua
-- Custom A* pathfinder with a pure-Lua binary min-heap.
-- Supports multi-layer 3D navigation, partial-path recovery,
-- and three bias modes for AIDecisionSystem candidate generation.
-- ModuleScript: child of Core folder.

local AStarPathfinder = {}
AStarPathfinder.__index = AStarPathfinder

-- ── Min-heap (priority queue) ─────────────────────────────────────────────────

local Heap = {}
Heap.__index = Heap

function Heap.new()
	return setmetatable({ _data = {}, _size = 0 }, Heap)
end

function Heap:push(element, priority)
	local size = self._size + 1
	self._size = size
	self._data[size] = { element, priority }
	self:_siftUp(size)
end

function Heap:pop()
	if self._size == 0 then return nil end
	local top  = self._data[1][1]
	local last = self._data[self._size]
	self._data[1] = last
	self._data[self._size] = nil
	self._size = self._size - 1
	if self._size > 1 then self:_siftDown(1) end
	return top
end

function Heap:isEmpty()
	return self._size == 0
end

function Heap:_siftUp(i)
	local data = self._data
	while i > 1 do
		local parent = math.floor(i / 2)
		if data[parent][2] > data[i][2] then
			data[parent], data[i] = data[i], data[parent]
			i = parent
		else
			break
		end
	end
end

function Heap:_siftDown(i)
	local data = self._data
	local size = self._size
	while true do
		local smallest = i
		local left     = 2 * i
		local right    = 2 * i + 1
		if left  <= size and data[left][2]  < data[smallest][2] then smallest = left  end
		if right <= size and data[right][2] < data[smallest][2] then smallest = right end
		if smallest == i then break end
		data[i], data[smallest] = data[smallest], data[i]
		i = smallest
	end
end

-- ── Constructor ───────────────────────────────────────────────────────────────

function AStarPathfinder.new(config, graph)
	local self = setmetatable({}, AStarPathfinder)
	self._cfg   = config
	self._graph = graph
	self.lastIterations = 0
	return self
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- bias: "balanced" | "distance" | "safe"
-- Returns { nodes={Node,...}, edges={Edge,...} } or nil
function AStarPathfinder:FindPath(startPos, goalPos, bias)
	bias = bias or "balanced"
	return self:_runAStar(startPos, goalPos, bias)
end

-- Attempt a local repair: re-run from current position using cached goal.
function AStarPathfinder:RepairPath(currentPos, goalPos)
	return self:FindPath(currentPos, goalPos, "balanced")
end

-- ── Core A* ──────────────────────────────────────────────────────────────────

function AStarPathfinder:_runAStar(startPos, goalPos, bias)
	local graph = self._graph
	local cfg   = self._cfg

	local startNode = graph:GetNearestNode(startPos)
	local goalNode  = graph:GetNearestNode(goalPos)
	if not startNode or not goalNode then return nil end
	if startNode.id == goalNode.id then
		return { nodes = {startNode}, edges = {} }
	end

	local heuristicMult = 1.0
	local riskMult      = 1.0
	if bias == "distance" then
		heuristicMult = 2.0   -- greedier, faster but less optimal
		riskMult      = 0.5
	elseif bias == "safe" then
		heuristicMult = 0.5   -- thorough search, avoids hazards
		riskMult      = 3.0
	end

	local openSet  = Heap.new()
	local gScore   = {}      -- [nodeId] = cost from start
	local fScore   = {}      -- [nodeId] = g + h
	local cameFrom = {}      -- [nodeId] = {fromNodeId, edge}
	local closed   = {}      -- [nodeId] = true
	local iters    = 0

	-- Track best node for partial path
	local bestNode  = startNode
	local bestH     = (goalNode.position - startNode.position).Magnitude

	gScore[startNode.id] = 0
	local h0 = self:_heuristic(startNode, goalNode) * heuristicMult
	fScore[startNode.id] = h0
	openSet:push(startNode.id, h0)

	while not openSet:isEmpty() do
		iters = iters + 1
		if iters > cfg.MaxAStarIter then break end
		if iters % 500 == 0 then task.wait() end

		local currentId = openSet:pop()
		if not currentId then break end
		if closed[currentId] then continue end
		closed[currentId] = true

		local currentNode = graph:GetNodeById(currentId)
		if not currentNode then continue end

		-- Track closest node to goal for partial path
		local hCur = (currentNode.position - goalNode.position).Magnitude
		if hCur < bestH then
			bestH    = hCur
			bestNode = currentNode
		end

		-- Goal reached
		if currentId == goalNode.id then
			self.lastIterations = iters
			return self:_reconstructPath(cameFrom, goalNode.id, startNode.id, graph)
		end

		local edges = graph:GetEdges(currentId)
		for _, edge in ipairs(edges) do
			local neighborId = edge.toId
			if closed[neighborId] then continue end

			local neighborNode = graph:GetNodeById(neighborId)
			if not neighborNode then continue end

			local edgeCost = edge.cost
			-- Apply risk multiplier to hazard/platform edges
			if edge.movingPart then edgeCost = edgeCost * riskMult end
			if neighborNode.tags.hazard then edgeCost = edgeCost * riskMult * 2 end

			local tentativeG = (gScore[currentId] or math.huge) + edgeCost

			if tentativeG < (gScore[neighborId] or math.huge) then
				cameFrom[neighborId] = { fromId = currentId, edge = edge }
				gScore[neighborId]   = tentativeG
				local h    = self:_heuristic(neighborNode, goalNode) * heuristicMult
				local f    = tentativeG + h
				fScore[neighborId] = f
				openSet:push(neighborId, f)
			end
		end
	end

	self.lastIterations = iters

	-- Return partial path to closest reached node
	if bestNode.id ~= startNode.id then
		return self:_reconstructPath(cameFrom, bestNode.id, startNode.id, graph)
	end
	return nil
end

function AStarPathfinder:_heuristic(node, goalNode)
	return (node.position - goalNode.position).Magnitude
end

function AStarPathfinder:_reconstructPath(cameFrom, goalId, startId, graph)
	local nodes = {}
	local edges = {}
	local cur   = goalId

	while cur ~= startId do
		local entry = cameFrom[cur]
		if not entry then break end
		local node = graph:GetNodeById(cur)
		if node then table.insert(nodes, 1, node) end
		table.insert(edges, 1, entry.edge)
		cur = entry.fromId
	end

	local startNode = graph:GetNodeById(startId)
	if startNode then table.insert(nodes, 1, startNode) end

	return { nodes = nodes, edges = edges }
end

return AStarPathfinder
