-- ARGUS/Main.lua
-- Roblox Studio entry point (LocalScript in StarterPlayerScripts).
-- All siblings must be ModuleScripts matching the folder tree:
--
--   Main (LocalScript)
--   ├── Config
--   ├── Core/            ObservationSystem · WorldScanner · NavigationGraph
--   │                    AStarPathfinder · PathSmoother
--   ├── Movement/        MovementTechDB · MovementController
--   │   └── Techniques/  Walk · Jump · ClimbLadder · ClimbTruss · Swim
--   │                    RideElevator · RideConveyor · RidePlatform
--   │                    SafeFall · GapCross · StairClimb · CornerCut · JumpChain
--   ├── AI/              RouteScorer · AIDecisionSystem
--   ├── Humanization/    HumanizationSystem
--   ├── Visualization/   VisualizationSystem · MinimapPanel
--   ├── UI/              UISystem
--   └── Debug/           DebugPanel

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local player    = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
character:WaitForChild("HumanoidRootPart")
character:WaitForChild("Humanoid")

-- ── Load modules via Roblox require() ────────────────────────────────────────

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
local MinimapPanel        = require(script.Visualization.MinimapPanel)
local VisualizationSystem = require(script.Visualization.VisualizationSystem)
local DebugPanel          = require(script.Debug.DebugPanel)
local UISystem            = require(script.UI.UISystem)

-- ── Shared state table ────────────────────────────────────────────────────────

local StateTable = {
	currentAction = "Idle", currentNodeId = nil, nextNodeId = nil,
	waypointIndex = 0, waypointTotal = 0, replanCount = 0,
	routeScore = nil, nodeCount = 0, edgeCount = 0,
	scanTimeMs = 0, astarIterations = 0, fps = 60,
	trackedObjects = 0, rationale = "", forceRescan = false,
}

-- ── Instantiate systems ───────────────────────────────────────────────────────

local obs      = ObservationSystem.new(Config)
local scanner  = WorldScanner.new(Config, obs)
local graph    = NavigationGraph.new(Config, obs)
local pf       = AStarPathfinder.new(Config, graph)
local smoother = PathSmoother.new(Config)
local techDB   = MovementTechDB.new(Config)

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

local controller  = MovementController.new(Config, techDB, smoother, graph, obs)
local humanizer   = HumanizationSystem.new(Config, controller)
local scorer      = RouteScorer.new(Config)
local minimap     = MinimapPanel.new(Config)
local viz         = VisualizationSystem.new(Config, minimap)
local debugPanel  = DebugPanel.new(Config, StateTable)
local ai          = AIDecisionSystem.new(Config, pf, scorer, obs, controller, graph, viz, humanizer)
local ui          = UISystem.new(Config, ai, controller, viz, humanizer, obs, debugPanel, StateTable)

-- ── Wire events ───────────────────────────────────────────────────────────────

scanner.onScanComplete = function(n)
	StateTable.nodeCount  = n
	StateTable.scanTimeMs = scanner:GetScanTime()
end

graph.onChanged = function()
	StateTable.nodeCount = graph.nodeCount
	StateTable.edgeCount = graph.edgeCount
	minimap:SetNodes(graph:GetAllNodes())
	viz:UpdateNodes(graph:GetAllNodes())
end

controller.onSegmentFailed = function(idx, tech)
	StateTable.replanCount = StateTable.replanCount + 1
	debugPanel:AddLog(("Segment %d failed [%s]"):format(idx, tech))
end
controller.onArrived = function()
	StateTable.currentAction = "Arrived"
	debugPanel:AddLog("Navigation complete.")
end
controller.onStuck = function()
	StateTable.currentAction = "Stuck"
	debugPanel:AddLog("Stuck – replanning")
end

ai.onRouteSelected = function(path, scores, rationale)
	StateTable.routeScore    = scores and scores.total
	StateTable.rationale     = rationale or ""
	StateTable.waypointTotal = path and path.nodes and #path.nodes or 0
	StateTable.replanCount   = ai:GetReplanCount()
	debugPanel:AddLog(("Route: %s"):format(rationale or "—"))
end
ai.onNavigationDone = function() StateTable.currentAction = "Arrived" end
ai.onNavigationFail = function()
	StateTable.currentAction = "No path found"
	debugPanel:AddLog("WARNING: No path found.")
end

-- ── Start systems ─────────────────────────────────────────────────────────────

viz:Initialize()
minimap:Initialize()
humanizer:Start()

task.spawn(function()
	while true do
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			if StateTable.forceRescan then StateTable.forceRescan = false end
			scanner:ScanAround(root.Position, character)
			task.wait(Config.ScanInterval)
			graph:IngestNodes(scanner:GetNodes())
		else
			task.wait(1)
		end
	end
end)

local fpsBuffer = {}
RunService.Heartbeat:Connect(function(dt)
	fpsBuffer[#fpsBuffer + 1] = 1 / math.max(0.001, dt)
	if #fpsBuffer > 30 then table.remove(fpsBuffer, 1) end
	local s = 0; for _, v in ipairs(fpsBuffer) do s = s + v end
	StateTable.fps             = s / #fpsBuffer
	StateTable.waypointIndex   = controller:GetWaypointIndex()
	StateTable.currentAction   = controller:GetCurrentAction()
	StateTable.astarIterations = pf.lastIterations
	StateTable.trackedObjects  = #obs:GetTrackedObjects()
	local c = player.Character
	if c and c ~= character then character = c end
end)

player.CharacterAdded:Connect(function(newChar)
	character = newChar
	newChar:WaitForChild("HumanoidRootPart", 10)
	controller:Stop()
	ai:Stop()
	StateTable.currentAction = "Idle"
	debugPanel:AddLog("Respawned.")
end)

task.wait(2)
ui:Initialize()

print(("[ARGUS] Studio ready — %d nodes."):format(graph.nodeCount))
