--[[
   █████╗ ██████╗  ██████╗ ██╗   ██╗███████╗
  ██╔══██╗██╔══██╗██╔════╝ ██║   ██║██╔════╝
  ███████║██████╔╝██║  ███╗██║   ██║███████╗
  ██╔══██║██╔══██╗██║   ██║██║   ██║╚════██║
  ██║  ██║██║  ██║╚██████╔╝╚██████╔╝███████║
  ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚══════╝

  Advanced Reasoning & Geographic Understanding System
  https://github.com/LizardRush/ARGUS

  USAGE: Paste this file into your executor and run.
  Requires: HttpService enabled (or a supported executor).
  Tested: Synapse X, KRNL, Fluxus, Script-Ware, Delta, Hydrogen.
--]]

-- ── HTTP compatibility layer ───────────────────────────────────────────────────
-- Tries each executor's HTTP API in order of prevalence.

local function httpGet(url)
	-- Synapse / most modern executors
	if syn and syn.request then
		local res = syn.request({ Url = url, Method = "GET" })
		if res and res.Body then return res.Body end
	end
	-- Generic request() (KRNL, Fluxus, Delta, etc.)
	if request then
		local ok, res = pcall(request, { Url = url, Method = "GET" })
		if ok and res and res.Body then return res.Body end
	end
	-- http.request (Script-Ware style)
	if http and http.request then
		local res = http.request({ Url = url, Method = "GET" })
		if res and res.Body then return res.Body end
	end
	-- game:HttpGet fallback (works when HttpService is enabled in Studio-run executors)
	local ok, res = pcall(function()
		return game:HttpGet(url, true)
	end)
	if ok and res and res ~= "" then return res end
	error("[ARGUS] No HTTP method available. Enable HttpService or use a supported executor.\nURL: " .. url)
end

-- ── Module loader ─────────────────────────────────────────────────────────────

local BASE = "https://raw.githubusercontent.com/LizardRush/ARGUS/main/"

local _moduleCache = {}

local function loadMod(path)
	if _moduleCache[path] then return _moduleCache[path] end
	local src = httpGet(BASE .. path)
	local fn, err = loadstring(src, "@" .. path)
	if not fn then
		error("[ARGUS] Parse error in " .. path .. ":\n" .. tostring(err))
	end
	local result = fn()
	_moduleCache[path] = result
	return result
end

-- ── Startup banner ────────────────────────────────────────────────────────────

print([[
[ARGUS] Advanced Reasoning & Geographic Understanding System
[ARGUS] github.com/LizardRush/ARGUS
[ARGUS] Loading modules from GitHub...]])

-- ── Guard: prevent double-execution ──────────────────────────────────────────

if getgenv and getgenv().ARGUS_LOADED then
	warn("[ARGUS] Already running. Stop the previous instance before re-loading.")
	if getgenv().ARGUS_STOP then getgenv().ARGUS_STOP() end
end
if getgenv then getgenv().ARGUS_LOADED = true end

-- ── Wait for character ────────────────────────────────────────────────────────

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local player    = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local function waitForChar()
	character = player.Character or player.CharacterAdded:Wait()
	character:WaitForChild("HumanoidRootPart", 10)
	character:WaitForChild("Humanoid", 10)
end
waitForChar()

-- ── Load all modules ──────────────────────────────────────────────────────────

local function loadStep(label, path)
	print("[ARGUS] Loading " .. label .. "...")
	return loadMod(path)
end

local Config            = loadStep("Config",            "Config.lua")
local ObservationSystem = loadStep("ObservationSystem", "Core/ObservationSystem.lua")
local WorldScanner      = loadStep("WorldScanner",      "Core/WorldScanner.lua")
local NavigationGraph   = loadStep("NavigationGraph",   "Core/NavigationGraph.lua")
local AStarPathfinder   = loadStep("AStarPathfinder",   "Core/AStarPathfinder.lua")
local PathSmoother      = loadStep("PathSmoother",      "Core/PathSmoother.lua")

local MovementTechDB     = loadStep("MovementTechDB",     "Movement/MovementTechDB.lua")
local MovementController = loadStep("MovementController", "Movement/MovementController.lua")

local Walk         = loadStep("Walk",         "Movement/Techniques/Walk.lua")
local Jump         = loadStep("Jump",         "Movement/Techniques/Jump.lua")
local ClimbLadder  = loadStep("ClimbLadder",  "Movement/Techniques/ClimbLadder.lua")
local ClimbTruss   = loadStep("ClimbTruss",   "Movement/Techniques/ClimbTruss.lua")
local Swim         = loadStep("Swim",         "Movement/Techniques/Swim.lua")
local RideElevator = loadStep("RideElevator", "Movement/Techniques/RideElevator.lua")
local RideConveyor = loadStep("RideConveyor", "Movement/Techniques/RideConveyor.lua")
local RidePlatform = loadStep("RidePlatform", "Movement/Techniques/RidePlatform.lua")
local SafeFall     = loadStep("SafeFall",     "Movement/Techniques/SafeFall.lua")
local GapCross     = loadStep("GapCross",     "Movement/Techniques/GapCross.lua")
local StairClimb   = loadStep("StairClimb",   "Movement/Techniques/StairClimb.lua")
local CornerCut    = loadStep("CornerCut",    "Movement/Techniques/CornerCut.lua")
local JumpChain    = loadStep("JumpChain",    "Movement/Techniques/JumpChain.lua")

local HumanizationSystem = loadStep("HumanizationSystem", "Humanization/HumanizationSystem.lua")
local RouteScorer        = loadStep("RouteScorer",        "AI/RouteScorer.lua")
local AIDecisionSystem   = loadStep("AIDecisionSystem",   "AI/AIDecisionSystem.lua")
local MinimapPanel       = loadStep("MinimapPanel",       "Visualization/MinimapPanel.lua")
local VisualizationSystem = loadStep("VisualizationSystem","Visualization/VisualizationSystem.lua")
local DebugPanel         = loadStep("DebugPanel",         "Debug/DebugPanel.lua")
local UISystem           = loadStep("UISystem",           "UI/UISystem.lua")

print("[ARGUS] All modules loaded. Initializing systems...")

-- ── Shared state table ────────────────────────────────────────────────────────

local StateTable = {
	currentAction   = "Idle",
	currentNodeId   = nil,
	nextNodeId      = nil,
	waypointIndex   = 0,
	waypointTotal   = 0,
	replanCount     = 0,
	routeScore      = nil,
	nodeCount       = 0,
	edgeCount       = 0,
	scanTimeMs      = 0,
	astarIterations = 0,
	fps             = 60,
	trackedObjects  = 0,
	rationale       = "",
	forceRescan     = false,
}

-- ── System instantiation ──────────────────────────────────────────────────────

local obs      = ObservationSystem.new(Config)
local scanner  = WorldScanner.new(Config, obs)
local graph    = NavigationGraph.new(Config, obs)
local pf       = AStarPathfinder.new(Config, graph)
local smoother = PathSmoother.new(Config)

local techDB   = MovementTechDB.new(Config)

-- Technique registration — most-specific first so dispatcher priority is correct
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

local controller = MovementController.new(Config, techDB, smoother, graph, obs)
local humanizer  = HumanizationSystem.new(Config, controller)
local scorer     = RouteScorer.new(Config)
local minimap    = MinimapPanel.new(Config)
local viz        = VisualizationSystem.new(Config, minimap)
local debugPanel = DebugPanel.new(Config, StateTable)
local ai         = AIDecisionSystem.new(Config, pf, scorer, obs, controller, graph, viz, humanizer)
local ui         = UISystem.new(Config, ai, controller, viz, humanizer, obs, debugPanel, StateTable)

-- ── Event wiring ──────────────────────────────────────────────────────────────

scanner.onScanComplete = function(nodeCount)
	StateTable.nodeCount  = nodeCount
	StateTable.scanTimeMs = scanner:GetScanTime()
end

graph.onChanged = function()
	StateTable.nodeCount = graph.nodeCount
	StateTable.edgeCount = graph.edgeCount
	minimap:SetNodes(graph:GetAllNodes())
	viz:UpdateNodes(graph:GetAllNodes())
end

local origSegFailed = controller.onSegmentFailed
controller.onSegmentFailed = function(wpIdx, techName)
	StateTable.replanCount = StateTable.replanCount + 1
	debugPanel:AddLog(string.format("Segment %d failed [%s]", wpIdx, techName))
	if origSegFailed then origSegFailed(wpIdx, techName) end
end

controller.onArrived = function()
	StateTable.currentAction = "Arrived"
	debugPanel:AddLog("Navigation complete.")
end

controller.onStuck = function()
	StateTable.currentAction = "Stuck"
	debugPanel:AddLog("Stuck detected – replanning")
end

ai.onRouteSelected = function(path, scores, rationale)
	StateTable.routeScore    = scores and scores.total
	StateTable.rationale     = rationale or ""
	StateTable.waypointTotal = path and path.nodes and #path.nodes or 0
	StateTable.replanCount   = ai:GetReplanCount()
	debugPanel:AddLog(string.format("Route selected: %s", rationale or "—"))
end

ai.onNavigationDone = function()
	StateTable.currentAction = "Arrived"
	StateTable.waypointIndex = 0
end

ai.onNavigationFail = function()
	StateTable.currentAction = "No path found"
	debugPanel:AddLog("WARNING: No path found to goal.")
end

-- ── Initialize presentation layer ────────────────────────────────────────────

viz:Initialize()
minimap:Initialize()
humanizer:Start()

-- ── Stop handler (for getgenv re-run guard) ───────────────────────────────────

local _connections = {}

if getgenv then
	getgenv().ARGUS_STOP = function()
		ai:Stop()
		controller:Stop()
		obs:Destroy()
		humanizer:Stop()
		minimap:Stop()
		for _, c in ipairs(_connections) do
			if c and c.Disconnect then c:Disconnect() end
		end
		local vizFolder = workspace:FindFirstChild("ARGUS_Viz")
		if vizFolder then vizFolder:Destroy() end
		if getgenv then
			getgenv().ARGUS_LOADED = false
			getgenv().ARGUS_STOP   = nil
		end
		print("[ARGUS] Stopped.")
	end
end

-- ── World scanner loop ────────────────────────────────────────────────────────

task.spawn(function()
	while getgenv == nil or getgenv().ARGUS_LOADED do
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			if StateTable.forceRescan then
				StateTable.forceRescan = false
			end
			scanner:ScanAround(root.Position, character)
			task.wait(Config.ScanInterval)
			graph:IngestNodes(scanner:GetNodes())
		else
			task.wait(1)
		end
	end
end)

-- ── Heartbeat: live StateTable updates ────────────────────────────────────────

local fpsBuffer = {}
local hbConn    = RunService.Heartbeat:Connect(function(dt)
	-- FPS rolling average (30-frame window)
	fpsBuffer[#fpsBuffer+1] = 1 / math.max(0.001, dt)
	if #fpsBuffer > 30 then table.remove(fpsBuffer, 1) end
	local sum = 0
	for _, v in ipairs(fpsBuffer) do sum = sum + v end
	StateTable.fps = sum / #fpsBuffer

	StateTable.waypointIndex   = controller:GetWaypointIndex()
	StateTable.currentAction   = controller:GetCurrentAction()
	StateTable.astarIterations = pf.lastIterations
	StateTable.trackedObjects  = #obs:GetTrackedObjects()

	-- Keep character reference fresh after respawn
	local char = player.Character
	if char and char ~= character then
		character = char
	end
end)
_connections[#_connections+1] = hbConn

-- ── Character respawn ─────────────────────────────────────────────────────────

local respawnConn = player.CharacterAdded:Connect(function(newChar)
	character = newChar
	newChar:WaitForChild("HumanoidRootPart", 10)
	controller:Stop()
	ai:Stop()
	StateTable.currentAction = "Idle"
	StateTable.replanCount   = 0
	debugPanel:AddLog("Character respawned.")
end)
_connections[#_connections+1] = respawnConn

-- ── Launch UI ─────────────────────────────────────────────────────────────────

task.wait(1.5)
ui:Initialize()

print(string.format(
	"[ARGUS] Ready — %d nodes scanned. Use the ARGUS window to navigate.",
	graph.nodeCount
))
