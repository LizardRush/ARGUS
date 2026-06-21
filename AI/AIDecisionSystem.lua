-- GoogleMapsRBX/AI/AIDecisionSystem.lua
-- Selects the optimal route from multiple A* candidates, manages
-- replanning lifecycle, and orchestrates the full navigation pipeline.
-- ModuleScript: child of AI folder.

local Players = game:GetService("Players")

local AIDecisionSystem = {}
AIDecisionSystem.__index = AIDecisionSystem

-- ── Constructor ───────────────────────────────────────────────────────────────

function AIDecisionSystem.new(config, pathfinder, scorer, obs, controller, graph, viz, humanSystem)
	local self = setmetatable({}, AIDecisionSystem)
	self._cfg      = config
	self._pf       = pathfinder
	self._scorer   = scorer
	self._obs      = obs
	self._ctrl     = controller
	self._graph    = graph
	self._viz      = viz
	self._human    = humanSystem

	self._goalPos      = nil
	self._goalPart     = nil   -- for Follow/GoToPart
	self._followPlayer = nil
	self._active       = false
	self._paused       = false
	self._lastReplan   = 0
	self._replanCount  = 0

	self._currentScores  = nil
	self._currentPath    = nil
	self._rationale      = ""

	-- Callbacks
	self.onRouteSelected = nil  -- function(path, scores, rationale)
	self.onNavigationDone = nil -- function()
	self.onNavigationFail = nil -- function()

	-- Wire controller callbacks
	controller.onSegmentFailed = function(wpIdx, techName)
		self:_onSegmentFailed(wpIdx, techName)
	end
	controller.onArrived = function()
		self:_onArrived()
	end
	controller.onStuck = function()
		self:_onStuck()
	end

	-- Wire graph changes
	graph.onChanged = function()
		self:_onGraphChanged()
	end

	self._followConn = nil
	self._char       = nil   -- injected via SetCharacter()
	return self
end

function AIDecisionSystem:SetCharacter(char)
	self._char = char
end

-- ── Public API ────────────────────────────────────────────────────────────────

function AIDecisionSystem:GoToPosition(position)
	self:_cancelFollow()
	self._goalPos  = position
	self._goalPart = nil
	self:_requestPath()
end

function AIDecisionSystem:GoToPart(partNameOrRef)
	self:_cancelFollow()
	local part
	if typeof(partNameOrRef) == "string" then
		part = workspace:FindFirstChild(partNameOrRef, true)
	else
		part = partNameOrRef
	end
	if not part then
		warn("ARGUS: GoToPart – part not found:", partNameOrRef)
		return
	end
	self._goalPos  = part.Position
	self._goalPart = part
	self:_requestPath()
end

function AIDecisionSystem:FollowPlayer(playerNameOrRef)
	self:_cancelFollow()
	local target
	if typeof(playerNameOrRef) == "string" then
		target = Players:FindFirstChild(playerNameOrRef)
	else
		target = playerNameOrRef
	end
	if not target then return end
	self._followPlayer = target

	-- Re-request path to follow target every 2 seconds
	self._followConn = task.spawn(function()
		while self._followPlayer do
			if target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
				self._goalPos = target.Character.HumanoidRootPart.Position
				self:_requestPath()
			end
			task.wait(2)
		end
	end)
end

function AIDecisionSystem:Stop()
	self:_cancelFollow()
	self._active  = false
	self._goalPos = nil
	self._ctrl:Stop()
	if self._viz then self._viz:ClearPath() end
end

function AIDecisionSystem:Pause()
	self._paused = true
	self._ctrl:Pause()
end

function AIDecisionSystem:Resume()
	self._paused = false
	self._ctrl:Resume()
end

function AIDecisionSystem:RecalculatePath()
	self._lastReplan = 0  -- bypass cooldown
	self:_requestPath()
end

-- Export route as a table of positions (prints to output).
function AIDecisionSystem:ExportRoute()
	if not self._currentPath then
		print("ARGUS: No current route.")
		return
	end
	local out = {}
	for i, node in ipairs(self._currentPath.nodes) do
		local p = node.position
		out[#out+1] = string.format("[%d] %.2f, %.2f, %.2f", i, p.X, p.Y, p.Z)
	end
	print("ARGUS Route Export:\n" .. table.concat(out, "\n"))
end

function AIDecisionSystem:GetCurrentScores()
	return self._currentScores
end

function AIDecisionSystem:GetRationale()
	return self._rationale
end

function AIDecisionSystem:GetReplanCount()
	return self._replanCount
end

-- ── Path request ──────────────────────────────────────────────────────────────

function AIDecisionSystem:_requestPath()
	if not self._goalPos then return end

	local now = tick()
	if now - self._lastReplan < self._cfg.ReplanCooldown then return end
	self._lastReplan = now

	local character = self._char
	if not character then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local startPos = root.Position
	local goalPos  = self._goalPos
	local slDist   = (goalPos - startPos).Magnitude

	-- Generate 3 candidate routes
	local candidates = {
		{ bias = "balanced", path = self._pf:FindPath(startPos, goalPos, "balanced") },
		{ bias = "distance", path = self._pf:FindPath(startPos, goalPos, "distance") },
		{ bias = "safe",     path = self._pf:FindPath(startPos, goalPos, "safe")     },
	}

	-- Score each candidate
	local best = nil
	local bestScore = math.huge
	for _, c in ipairs(candidates) do
		if c.path then
			local s = self._scorer:Score(c.path, slDist)
			c.score = s
			if s.total < bestScore then
				bestScore = s.total
				best      = c
			end
		end
	end

	if not best or not best.path then
		warn("ARGUS: No path found to goal.")
		if self.onNavigationFail then self.onNavigationFail() end
		return
	end

	self._currentPath   = best.path
	self._currentScores = best.score
	self._rationale     = self._scorer:Rationale(best.score, best.bias)
	self._active        = true
	self._replanCount   = self._replanCount + 1

	-- Update visualization
	if self._viz then
		self._viz:SetPath(best.path)
	end
	if self._human then
		-- Pass smoothed waypoints to humanizer after smoother runs
	end

	if self.onRouteSelected then
		self.onRouteSelected(best.path, best.score, self._rationale)
	end

	-- Execute
	self._ctrl:ExecutePath(best.path, true)
end

-- ── Event handlers ────────────────────────────────────────────────────────────

function AIDecisionSystem:_onSegmentFailed(wpIdx, techName)
	if not self._active then return end
	warn(string.format("ARGUS: Segment %d failed [%s], replanning", wpIdx, techName))
	self:RecalculatePath()
end

function AIDecisionSystem:_onArrived()
	if self._followPlayer then return end  -- keep following
	self._active  = false
	self._goalPos = nil
	if self._viz then self._viz:ClearPath() end
	if self.onNavigationDone then self.onNavigationDone() end
end

function AIDecisionSystem:_onStuck()
	warn("ARGUS: Character stuck, requesting replan")
	self:RecalculatePath()
end

function AIDecisionSystem:_onGraphChanged()
	if not self._active or not self._currentPath then return end
	-- Quick validity check: if >20% of remaining edges are gone, replan
	local edges  = self._currentPath.edges
	local wpIdx  = self._ctrl:GetWaypointIndex()
	local total  = #edges - wpIdx + 1
	if total <= 0 then return end
	local invalid = 0
	for i = wpIdx, #edges do
		local edge = edges[i]
		if edge then
			local nodeEdges = self._graph:GetEdges(edge.fromId)
			local found     = false
			for _, e in ipairs(nodeEdges) do
				if e.toId == edge.toId then found = true break end
			end
			if not found then invalid = invalid + 1 end
		end
	end
	if invalid / total > 0.2 then
		self:RecalculatePath()
	end
end

function AIDecisionSystem:_cancelFollow()
	self._followPlayer = nil
	if self._followConn then
		-- followConn is a coroutine thread; set player to nil to stop it
		self._followConn = nil
	end
end

return AIDecisionSystem
