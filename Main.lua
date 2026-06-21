-- ARGUS/Main.lua
-- ModuleScript — works on both server and client.
--
-- Client usage (LocalScript or ModuleScript required from a LocalScript):
--   local ARGUS = require(script.Parent.ARGUS)
--   local nav   = ARGUS.new()
--   nav:GoToPosition(Vector3.new(100, 0, 200))
--
-- Server usage (Script or ModuleScript required from a Script):
--   local ARGUS     = require(game.ServerScriptService.ARGUS)
--   local character = workspace:FindFirstChild("SomeNPC")
--   local nav       = ARGUS.new({ character = character })
--   nav:GoToPosition(Vector3.new(100, 0, 200))
--
-- options (all optional on client; character required on server):
--   character : Model   -- the character/NPC to navigate
--   config    : table   -- partial Config overrides merged on top of defaults
--   visualize : bool    -- enable 3D beam visualization (default true)
--   humanize  : bool    -- enable humanization layer (default true on client)

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local IS_CLIENT = RunService:IsClient()

-- ── Load modules ──────────────────────────────────────────────────────────────

local Config              = require(script.Config)
local ObservationSystem   = require(script.Core.ObservationSystem)
local WorldScanner        = require(script.Core.WorldScanner)
local NavigationGraph     = require(script.Core.NavigationGraph)
local AStarPathfinder     = require(script.Core.AStarPathfinder)
local PathSmoother        = require(script.Core.PathSmoother)
local MovementTechDB      = require(script.Movement.MovementTechDB)
local MovementController  = require(script.Movement.MovementController)
local Walk                = require(script.Movement.Techniques.Walk)
local Jump                = require(script.Movement.Techniques.Jump)
local ClimbLadder         = require(script.Movement.Techniques.ClimbLadder)
local ClimbTruss          = require(script.Movement.Techniques.ClimbTruss)
local Swim                = require(script.Movement.Techniques.Swim)
local RideElevator        = require(script.Movement.Techniques.RideElevator)
local RideConveyor        = require(script.Movement.Techniques.RideConveyor)
local RidePlatform        = require(script.Movement.Techniques.RidePlatform)
local SafeFall            = require(script.Movement.Techniques.SafeFall)
local GapCross            = require(script.Movement.Techniques.GapCross)
local StairClimb          = require(script.Movement.Techniques.StairClimb)
local CornerCut           = require(script.Movement.Techniques.CornerCut)
local JumpChain           = require(script.Movement.Techniques.JumpChain)
local HumanizationSystem  = require(script.Humanization.HumanizationSystem)
local RouteScorer         = require(script.AI.RouteScorer)
local AIDecisionSystem    = require(script.AI.AIDecisionSystem)
local VisualizationSystem = require(script.Visualization.VisualizationSystem)

-- ── ARGUS class ───────────────────────────────────────────────────────────────

local ARGUS = {}
ARGUS.__index = ARGUS

function ARGUS.new(options)
	options = options or {}

	-- Resolve character
	local character
	if options.character then
		character = options.character
	elseif IS_CLIENT then
		local player = Players.LocalPlayer
		character = player.Character or player.CharacterAdded:Wait()
	else
		error("ARGUS.new: options.character is required when running on the server", 2)
	end
	character:WaitForChild("HumanoidRootPart", 15)
	character:WaitForChild("Humanoid", 15)

	-- Merge config overrides
	local cfg = Config
	if options.config then
		cfg = setmetatable(options.config, { __index = Config })
	end

	local enableViz      = options.visualize ~= false
	local enableHumanize = options.humanize  ~= false and IS_CLIENT

	-- ── Instantiate systems ───────────────────────────────────────────────

	local obs      = ObservationSystem.new(cfg)
	local scanner  = WorldScanner.new(cfg, obs)
	local graph    = NavigationGraph.new(cfg, obs)
	local pf       = AStarPathfinder.new(cfg, graph)
	local smoother = PathSmoother.new(cfg)
	local techDB   = MovementTechDB.new(cfg)

	techDB:Register("JumpChain",    JumpChain.new())
	techDB:Register("CornerCut",    CornerCut.new())
	techDB:Register("GapCross",     GapCross.new())
	techDB:Register("RidePlatform", RidePlatform.new())
	techDB:Register("RideElevator", RideElevator.new())
	techDB:Register("RideConveyor", RideConveyor.new())
	techDB:Register("ClimbLadder",  ClimbLadder.new())
	techDB:Register("ClimbTruss",   ClimbTruss.new())
	techDB:Register("StairClimb",   StairClimb.new())
	techDB:Register("SafeFall",     SafeFall.new())
	techDB:Register("Swim",         Swim.new())
	techDB:Register("Jump",         Jump.new())
	techDB:Register("Walk",         Walk.new())

	local controller = MovementController.new(cfg, techDB, smoother, graph, obs)
	controller:SetCharacter(character)

	local humanizer = HumanizationSystem.new(cfg, controller)
	humanizer:SetCharacter(character)

	local scorer = RouteScorer.new(cfg)
	local viz    = enableViz and VisualizationSystem.new(cfg, nil) or nil
	local ai     = AIDecisionSystem.new(cfg, pf, scorer, obs, controller, graph, viz, humanizer)
	ai:SetCharacter(character)

	-- ── Wire graph → viz ──────────────────────────────────────────────────

	graph.onChanged = function()
		if viz then viz:UpdateNodes(graph:GetAllNodes()) end
	end

	-- ── Start systems ─────────────────────────────────────────────────────

	if viz then viz:Initialize() end
	if enableHumanize then humanizer:Start() end

	-- ── Scan loop ─────────────────────────────────────────────────────────

	local _running     = true
	local _connections = {}

	task.spawn(function()
		while _running do
			local root = character:FindFirstChild("HumanoidRootPart")
			if root then
				scanner:ScanAround(root.Position, character)
				task.wait(cfg.ScanInterval)
				graph:IngestNodes(scanner:GetNodes())
			else
				task.wait(1)
			end
		end
	end)

	-- ── Respawn handling (client only) ────────────────────────────────────

	if IS_CLIENT then
		local player = Players.LocalPlayer
		local conn = player.CharacterAdded:Connect(function(newChar)
			character = newChar
			newChar:WaitForChild("HumanoidRootPart", 10)
			controller:Stop()
			controller:SetCharacter(newChar)
			humanizer:SetCharacter(newChar)
			ai:Stop()
			ai:SetCharacter(newChar)
		end)
		_connections[#_connections + 1] = conn
	end

	-- ── Build instance ────────────────────────────────────────────────────

	local self        = setmetatable({}, ARGUS)
	self._cfg         = cfg
	self._obs         = obs
	self._graph       = graph
	self._controller  = controller
	self._humanizer   = humanizer
	self._ai          = ai
	self._viz         = viz
	self._running     = _running
	self._connections = _connections

	return self
end

-- ── Navigation API ────────────────────────────────────────────────────────────

function ARGUS:GoToPosition(position)
	self._ai:GoToPosition(position)
end

function ARGUS:GoToPart(partOrName)
	self._ai:GoToPart(partOrName)
end

function ARGUS:FollowPlayer(playerOrName)
	self._ai:FollowPlayer(playerOrName)
end

function ARGUS:Stop()
	self._ai:Stop()
end

function ARGUS:Pause()
	self._ai:Pause()
end

function ARGUS:Resume()
	self._ai:Resume()
end

function ARGUS:Recalculate()
	self._ai:RecalculatePath()
end

-- ── Inspection API ────────────────────────────────────────────────────────────

function ARGUS:GetState()
	return {
		action         = self._controller:GetCurrentAction(),
		waypointIndex  = self._controller:GetWaypointIndex(),
		waypointTotal  = self._controller:GetWaypointCount(),
		nodeCount      = self._graph.nodeCount,
		edgeCount      = self._graph.edgeCount,
		replanCount    = self._ai:GetReplanCount(),
		routeScore     = self._ai:GetCurrentScores(),
		rationale      = self._ai:GetRationale(),
		trackedObjects = #self._obs:GetTrackedObjects(),
	}
end

-- ── Config API ────────────────────────────────────────────────────────────────

function ARGUS:SetVisualization(enabled)
	if not self._viz then return end
	for _, layer in ipairs({ "Walk","Jump","Climb","Advanced","Platform","Conveyor","Fall" }) do
		self._viz:SetLayerVisible(layer, enabled)
	end
end

function ARGUS:SetHumanization(enabled)
	self._humanizer:SetEnabled(enabled)
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

function ARGUS:Destroy()
	self._running = false
	pcall(function() self._ai:Stop() end)
	pcall(function() self._controller:Stop() end)
	pcall(function() self._obs:Destroy() end)
	pcall(function() self._humanizer:Stop() end)
	for _, c in ipairs(self._connections) do
		if c and c.Disconnect then pcall(c.Disconnect, c) end
	end
	local f = workspace:FindFirstChild("ARGUS_Viz")
	if f then f:Destroy() end
end

return ARGUS
