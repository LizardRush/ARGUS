-- GoogleMapsRBX/Movement/MovementController.lua
-- State machine that drives the local character through a smoothed
-- waypoint path using the MovementTechDB dispatcher.
-- States: Idle → Executing → Stuck → Replanning → Arrived / Stopped
-- ModuleScript: child of Movement folder.

local RunService = game:GetService("RunService")
local Players    = game:GetService("Players")

local MovementController = {}
MovementController.__index = MovementController

-- ── Constructor ───────────────────────────────────────────────────────────────

function MovementController.new(config, techDB, smoother, graph, observationSystem)
	local self = setmetatable({}, MovementController)
	self._cfg       = config
	self._techDB    = techDB
	self._smoother  = smoother
	self._graph     = graph
	self._obs       = observationSystem

	-- State
	self._state       = "Idle"       -- Idle | Executing | Paused | Stopping
	self._path        = nil          -- raw path {nodes, edges}
	self._waypoints   = nil          -- smoothed Vector3 array
	self._wpIndex     = 1
	self._currentTech = nil
	self._currentTechName = ""
	self._paused      = false
	self._stopping    = false

	-- Anti-stuck tracking
	self._stuckTimer   = 0
	self._stuckCount   = 0
	self._lastPos      = Vector3.zero
	self._lastPosTime  = 0

	-- Stats
	self.replanCount   = 0
	self.currentAction = "Idle"

	-- Callbacks (set these from Main.lua or AIDecisionSystem)
	self.onSegmentFailed = nil   -- function(wpIndex, techName)
	self.onArrived       = nil   -- function()
	self.onStuck         = nil   -- function()
	self.onReplan        = nil   -- function()

	self._heartbeatConn = nil
	return self
end

-- ── Public API ────────────────────────────────────────────────────────────────

function MovementController:ExecutePath(rawPath, humanize)
	self:Stop()
	if not rawPath or not rawPath.nodes or #rawPath.nodes < 1 then return end

	self._path      = rawPath
	self._waypoints = self._smoother:Smooth(rawPath, humanize or false)
	self._wpIndex   = 1
	self._stuckCount = 0
	self._paused    = false
	self._stopping  = false
	self._state     = "Executing"

	-- Reset stuck position baseline
	local root = self:_getRoot()
	if root then
		self._lastPos     = root.Position
		self._lastPosTime = tick()
	end

	self:_startHeartbeat()
end

function MovementController:Stop()
	self._stopping = true
	self._state    = "Idle"
	self:_stopHeartbeat()
	local humanoid = self:_getHumanoid()
	if humanoid then
		humanoid:MoveTo(humanoid.RootPart and humanoid.RootPart.Position or Vector3.zero)
	end
end

function MovementController:Pause()
	self._paused = true
end

function MovementController:Resume()
	self._paused = false
end

function MovementController:IsActive()
	return self._state == "Executing"
end

function MovementController:GetCurrentAction()
	return self.currentAction
end

function MovementController:GetWaypointIndex()
	return self._wpIndex
end

function MovementController:GetWaypointCount()
	return self._waypoints and #self._waypoints or 0
end

-- ── Internal: Heartbeat loop ──────────────────────────────────────────────────

function MovementController:_startHeartbeat()
	self:_stopHeartbeat()
	self._heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		self:_tick(dt)
	end)
end

function MovementController:_stopHeartbeat()
	if self._heartbeatConn then
		self._heartbeatConn:Disconnect()
		self._heartbeatConn = nil
	end
end

function MovementController:_tick(dt)
	if self._stopping then return end
	if self._paused   then return end

	local character = Players.LocalPlayer.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root     = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then return end
	if humanoid.Health <= 0 then
		self:Stop()
		return
	end

	-- ── Anti-stuck detection ───────────────────────────────────────────────
	self._stuckTimer = self._stuckTimer + dt
	if self._stuckTimer >= self._cfg.StuckCheckInterval then
		self._stuckTimer = 0
		local nowPos  = root.Position
		local elapsed = tick() - self._lastPosTime
		if elapsed >= 2 and (nowPos - self._lastPos).Magnitude < self._cfg.StuckThreshold then
			self._stuckCount = self._stuckCount + 1
			if self._stuckCount >= self._cfg.MaxStuckCount then
				self._stuckCount = 0
				self.currentAction = "Stuck – replanning"
				if self.onStuck then self.onStuck() end
				if self.onSegmentFailed then
					self.onSegmentFailed(self._wpIndex, self._currentTechName)
				end
				return
			end
		else
			self._stuckCount = 0
		end
		self._lastPos     = nowPos
		self._lastPosTime = tick()
	end

	-- ── Waypoint execution ─────────────────────────────────────────────────
	local wps = self._waypoints
	if not wps or self._wpIndex > #wps then
		self._state = "Idle"
		self:_stopHeartbeat()
		self.currentAction = "Arrived"
		if self.onArrived then self.onArrived() end
		return
	end

	local target   = wps[self._wpIndex]
	local dist     = (root.Position - target).Magnitude

	if dist < self._cfg.ReachDistance then
		self._wpIndex  = self._wpIndex + 1
		self._stuckCount = 0
		return
	end

	-- Build execution context
	local edge    = self._path.edges[self._wpIndex]
	local fromNode = self._path.nodes[self._wpIndex]
	local toNode   = self._path.nodes[self._wpIndex + 1]
	local nextNode = self._path.nodes[self._wpIndex + 2]
	local nextEdge = self._path.edges[self._wpIndex + 1]

	local ctx = {
		character        = character,
		humanoid         = humanoid,
		rootPart         = root,
		fromNode         = fromNode or { position = root.Position, tags = {} },
		toNode           = toNode   or { position = target, tags = {} },
		nextNode         = nextNode,
		edge             = edge     or { edgeType = "Walk", cost = 1 },
		nextEdge         = nextEdge,
		observationSystem = self._obs,
		config           = self._cfg,
		humanize         = self._humanize,
	}

	-- Select technique
	local tech, techName = self._techDB:GetBestTechnique(edge, ctx)
	if not tech then
		-- Fallback to raw MoveTo
		humanoid.WalkSpeed = self._cfg.WalkSpeed
		humanoid:MoveTo(target)
		self._currentTechName = "RawMove"
		self.currentAction    = "RawMove"
		return
	end

	self._currentTech     = tech
	self._currentTechName = techName or "Unknown"
	self.currentAction    = tech:DebugInfo(ctx)

	-- Anti-robot delay
	if self._cfg.AntiRobotMaxDelay > 0 then
		local delay = math.random() * self._cfg.AntiRobotMaxDelay
		if delay > 0.01 then task.wait(delay) end
	end

	-- Execute on a separate thread so heartbeat isn't blocked
	task.spawn(function()
		local success = false
		local ok, err = pcall(function()
			success = tech:Execute(ctx)
		end)
		if not ok then
			warn("ARGUS: technique error:", err)
			success = false
		end
		if not success and not self._stopping then
			if self.onSegmentFailed then
				self.onSegmentFailed(self._wpIndex, self._currentTechName)
			end
		end
	end)
end

-- ── Private helpers ───────────────────────────────────────────────────────────

function MovementController:_getHumanoid()
	local char = Players.LocalPlayer.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

function MovementController:_getRoot()
	local char = Players.LocalPlayer.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

return MovementController
