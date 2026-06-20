-- GoogleMapsRBX/Config.lua
-- Single source of truth for all tunable constants.
-- ModuleScript: place as child of the Main LocalScript.

local Config = {}

-- ── Scanner ─────────────────────────────────────────────────────────────────
Config.NodeSpacing       = 4      -- studs between navigation grid points
Config.ScanRadius        = 50     -- studs around character to scan
Config.ScanInterval      = 0.5    -- seconds between full rescans
Config.ClearanceHeight   = 4.5    -- vertical clearance needed above a node
Config.MinSurfaceNormal  = 0.7    -- Y-component threshold for walkable floor
Config.RayMaxDistance    = 200    -- max raycast distance
Config.SpecialScanRadius = 3      -- radius for per-node special-detection pass

-- ── Pathfinding ──────────────────────────────────────────────────────────────
Config.MaxJumpHeight     = 8      -- studs, max upward jump
Config.MaxFallDistance   = 20     -- studs, safe fall distance
Config.MaxJumpHorizontal = 12     -- studs, max horizontal jump distance
Config.MaxAStarIter      = 5000   -- iteration cap before returning partial path
Config.ReplanCooldown    = 0.5    -- min seconds between replans

-- ── Edge costs ───────────────────────────────────────────────────────────────
Config.EdgeCost = {
	Walk         = 1.0,
	Jump         = 2.0,
	ClimbLadder  = 1.5,
	ClimbTruss   = 1.3,
	Swim         = 2.5,
	RideElevator = 1.0,
	RideConveyor = 0.8,
	RidePlatform = 1.2,
	Fall         = 0.5,
	GapCross     = 2.2,
}

-- ── Cost multipliers ─────────────────────────────────────────────────────────
Config.CostMult = {
	Water          = 1.5,
	MovingPlatform = 1.2,
	Hazard         = 10.0,
}

-- ── Observation / prediction ──────────────────────────────────────────────────
Config.ObsBufferSize     = 120   -- position samples kept per tracked object
Config.ObsFitInterval    = 1.0   -- seconds between model refits
Config.PredictionHorizon = 3.0   -- seconds ahead to search for jump window

-- ── Movement controller ───────────────────────────────────────────────────────
Config.WalkSpeed          = 16   -- studs/s (matches Roblox humanoid default)
Config.StuckThreshold     = 1.0  -- min displacement in 2 s before "stuck"
Config.StuckCheckInterval = 1.0  -- how often to sample for stuck detection
Config.MaxStuckCount      = 5    -- stuck checks before replan
Config.ReachDistance      = 1.5  -- studs to a node before it counts as reached

-- ── Humanization ─────────────────────────────────────────────────────────────
Config.MaxJitter            = 0.5   -- ±studs of XZ noise on waypoints
Config.PauseProbability     = 0.05  -- per-segment idle-pause chance
Config.PauseMaxDuration     = 1.2   -- max idle pause seconds
Config.HeadTurnProbability  = 0.08  -- per-frame chance of head turn
Config.SpeedVariation       = 0.1   -- ±fraction of WalkSpeed per segment
Config.CameraLag            = 0.15  -- lerp factor for camera follow
Config.AntiRobotMaxDelay    = 0.1   -- max pre-segment jitter delay (seconds)

-- ── Visualization ─────────────────────────────────────────────────────────────
Config.NodeRadius        = 0.3   -- sphere marker radius
Config.BeamWidth         = 0.15  -- beam edge width
Config.VizUpdateThrottle = 0.1   -- min seconds between viz rebuilds
Config.MinimapSize       = 200   -- minimap frame px dimension
Config.MinimapScale      = 0.5   -- studs per pixel
Config.MinimapUpdateHz   = 4     -- minimap refreshes per second
Config.DebugUpdateHz     = 10    -- debug panel refreshes per second

-- ── Colors ────────────────────────────────────────────────────────────────────
Config.Color = {
	Walk        = Color3.fromHex("00cc44"),
	Jump        = Color3.fromHex("ffcc00"),
	Climb       = Color3.fromHex("0088ff"),
	Advanced    = Color3.fromHex("ff8800"),
	Platform    = Color3.fromHex("aa00ff"),
	Conveyor    = Color3.fromHex("ff66aa"),
	Hazard      = Color3.fromHex("ff2200"),
	Destination = Color3.fromHex("ffffff"),
	Node        = Color3.fromHex("aaaaaa"),
}

-- ── AI / route scoring ────────────────────────────────────────────────────────
Config.RouteScoreWeights = {
	Distance   = 0.4,
	Time       = 0.3,
	Risk       = 0.2,
	Complexity = 0.1,
}

-- ── Hazard / tag detection ────────────────────────────────────────────────────
Config.HazardNamePatterns = { "kill", "lava", "spike", "hurt", "damage", "fire" }
Config.HazardTagName      = "Hazard"
Config.ConveyorTagName    = "Conveyor"
Config.DoorTagName        = "Door"
Config.LadderTagName      = "Ladder"

-- ── Fallback ─────────────────────────────────────────────────────────────────
Config.UseFallbackPFS = false  -- enable PathfindingService as last resort

return Config
