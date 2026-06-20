-- GoogleMapsRBX/UI/UISystem.lua
-- Rayfield-based GUI with 6 tabs: Navigation, Visualization,
-- Movement, Observation, AI, Debug.
-- ModuleScript: child of UI folder.

local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")

local UISystem = {}
UISystem.__index = UISystem

-- ── Constructor ───────────────────────────────────────────────────────────────

function UISystem.new(config, ai, controller, viz, human, obs, debugPanel, stateTable)
	local self = setmetatable({}, UISystem)
	self._cfg        = config
	self._ai         = ai
	self._ctrl       = controller
	self._viz        = viz
	self._human      = human
	self._obs        = obs
	self._debug      = debugPanel
	self._state      = stateTable
	self._window     = nil
	self._tabs       = {}
	self._conn       = nil
	self._updateTimer = 0
	return self
end

-- ── Public API ────────────────────────────────────────────────────────────────

function UISystem:Initialize()
	-- Load Rayfield
	local ok, Rayfield = pcall(function()
		return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
	end)
	if not ok or not Rayfield then
		warn("ARGUS: Failed to load Rayfield UI — ensure HttpService is enabled.")
		return
	end

	self._rf = Rayfield

	local window = Rayfield:CreateWindow({
		Name             = "ARGUS",
		LoadingTitle     = "ARGUS",
		LoadingSubtitle  = "Advanced Reasoning & Geographic Understanding System",
		ConfigurationSaving = {
			Enabled  = true,
			FileName = "ARGUS_Config",
		},
		KeySystem = false,
	})
	self._window = window

	self:_buildNavigationTab(window)
	self:_buildVisualizationTab(window)
	self:_buildMovementTab(window)
	self:_buildObservationTab(window)
	self:_buildAITab(window)
	self:_buildDebugTab(window)

	-- Periodic UI refresh for live data tabs
	self._conn = RunService.Heartbeat:Connect(function(dt)
		self._updateTimer = self._updateTimer + dt
		if self._updateTimer >= 0.5 then
			self._updateTimer = 0
			self:_refreshLiveTabs()
		end
	end)

	if self._debug then self._debug:Initialize() end
end

-- ── Tab: Navigation ───────────────────────────────────────────────────────────

function UISystem:_buildNavigationTab(window)
	local Rayfield = self._rf
	local tab = window:CreateTab("Navigation", "map-pin")

	-- Go To Position
	tab:CreateSection("Destination")

	local xInput, yInput, zInput
	xInput = tab:CreateInput({
		Name        = "X",
		PlaceholderText = "X coordinate",
		RemoveTextAfterFocusLost = false,
		Callback    = function(val) self._gotoX = tonumber(val) end,
	})
	yInput = tab:CreateInput({
		Name        = "Y",
		PlaceholderText = "Y coordinate",
		RemoveTextAfterFocusLost = false,
		Callback    = function(val) self._gotoY = tonumber(val) end,
	})
	zInput = tab:CreateInput({
		Name        = "Z",
		PlaceholderText = "Z coordinate",
		RemoveTextAfterFocusLost = false,
		Callback    = function(val) self._gotoZ = tonumber(val) end,
	})

	tab:CreateButton({
		Name     = "Go To Position",
		Callback = function()
			local x = self._gotoX or 0
			local y = self._gotoY or 0
			local z = self._gotoZ or 0
			self._ai:GoToPosition(Vector3.new(x, y, z))
			Rayfield:Notify({ Title="Navigation", Content="Navigating to "..math.floor(x)..","..math.floor(y)..","..math.floor(z), Duration=3 })
		end,
	})

	-- Go To Part
	tab:CreateSection("Part Navigation")

	local partNameInput
	partNameInput = tab:CreateInput({
		Name        = "Part Name",
		PlaceholderText = "workspace part name",
		RemoveTextAfterFocusLost = false,
		Callback    = function(val) self._gotoPartName = val end,
	})

	tab:CreateButton({
		Name     = "Go To Part",
		Callback = function()
			if self._gotoPartName and self._gotoPartName ~= "" then
				self._ai:GoToPart(self._gotoPartName)
				Rayfield:Notify({ Title="Navigation", Content="Navigating to: "..self._gotoPartName, Duration=3 })
			end
		end,
	})

	-- Follow Player
	tab:CreateSection("Follow Player")

	local playerNames = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= Players.LocalPlayer then
			playerNames[#playerNames+1] = p.Name
		end
	end
	if #playerNames == 0 then playerNames = { "No other players" } end

	tab:CreateDropdown({
		Name    = "Player to Follow",
		Options = playerNames,
		Callback = function(val)
			self._followTarget = val
		end,
	})

	tab:CreateButton({
		Name     = "Follow Player",
		Callback = function()
			if self._followTarget then
				self._ai:FollowPlayer(self._followTarget)
				Rayfield:Notify({ Title="Following", Content=self._followTarget, Duration=3 })
			end
		end,
	})

	-- Control buttons
	tab:CreateSection("Controls")

	tab:CreateButton({
		Name     = "Stop",
		Callback = function()
			self._ai:Stop()
			Rayfield:Notify({ Title="Navigation", Content="Stopped.", Duration=2 })
		end,
	})

	tab:CreateButton({
		Name     = "Pause / Resume",
		Callback = function()
			if self._paused then
				self._ai:Resume()
				self._paused = false
				Rayfield:Notify({ Title="Navigation", Content="Resumed.", Duration=1 })
			else
				self._ai:Pause()
				self._paused = true
				Rayfield:Notify({ Title="Navigation", Content="Paused.", Duration=1 })
			end
		end,
	})

	tab:CreateButton({
		Name     = "Recalculate Route",
		Callback = function()
			self._ai:RecalculatePath()
			Rayfield:Notify({ Title="Navigation", Content="Recalculating...", Duration=2 })
		end,
	})

	tab:CreateButton({
		Name     = "Export Route",
		Callback = function()
			self._ai:ExportRoute()
			Rayfield:Notify({ Title="Export", Content="Route printed to output.", Duration=2 })
		end,
	})
end

-- ── Tab: Visualization ────────────────────────────────────────────────────────

function UISystem:_buildVisualizationTab(window)
	local Rayfield = self._rf
	local tab = window:CreateTab("Visualization", "eye")

	tab:CreateSection("Path Layers")

	local layers = { "Walk", "Jump", "Climb", "Advanced", "Platform", "Conveyor", "Fall" }
	for _, name in ipairs(layers) do
		tab:CreateToggle({
			Name          = name .. " edges",
			CurrentValue  = true,
			Flag          = "VizLayer_" .. name,
			Callback      = function(val)
				if self._viz then self._viz:SetLayerVisible(name, val) end
			end,
		})
	end

	tab:CreateSection("Minimap")

	tab:CreateToggle({
		Name         = "Show Minimap",
		CurrentValue = true,
		Flag         = "MinimapVisible",
		Callback     = function(val)
			if self._viz and self._viz._minimap then
				self._viz._minimap:SetVisible(val)
			end
		end,
	})

	tab:CreateSlider({
		Name     = "Minimap Scale (studs/px)",
		Range    = { 0.2, 5 },
		Increment = 0.1,
		CurrentValue = self._cfg.MinimapScale,
		Flag     = "MinimapScale",
		Callback = function(val)
			if self._viz and self._viz._minimap then
				self._viz._minimap:SetScale(val)
			end
		end,
	})
end

-- ── Tab: Movement ─────────────────────────────────────────────────────────────

function UISystem:_buildMovementTab(window)
	local Rayfield = self._rf
	local tab = window:CreateTab("Movement", "zap")

	tab:CreateSection("Speed")

	tab:CreateSlider({
		Name     = "Speed Multiplier",
		Range    = { 0.5, 2.5 },
		Increment = 0.05,
		CurrentValue = 1.0,
		Flag     = "SpeedMult",
		Callback = function(val)
			self._cfg.WalkSpeed = 16 * val
		end,
	})

	tab:CreateSection("Technique Toggles")

	local techNames = {
		"Walk", "Jump", "ClimbLadder", "ClimbTruss", "Swim",
		"RideElevator", "RideConveyor", "RidePlatform",
		"SafeFall", "GapCross", "StairClimb", "CornerCut", "JumpChain",
	}
	for _, name in ipairs(techNames) do
		tab:CreateToggle({
			Name         = name,
			CurrentValue = true,
			Flag         = "Tech_" .. name,
			Callback     = function(val)
				-- Communicate enable/disable to TechDB via config flag
				if not self._cfg.DisabledTechniques then
					self._cfg.DisabledTechniques = {}
				end
				self._cfg.DisabledTechniques[name] = not val
			end,
		})
	end

	tab:CreateSection("Humanization")

	tab:CreateToggle({
		Name         = "Enable Humanization",
		CurrentValue = true,
		Flag         = "HumanizeMaster",
		Callback     = function(val)
			if self._human then self._human:SetEnabled(val) end
		end,
	})
	tab:CreateToggle({
		Name         = "Camera Follow",
		CurrentValue = true,
		Flag         = "HumanizeCamera",
		Callback     = function(val)
			if self._human then self._human:SetCamera(val) end
		end,
	})
	tab:CreateToggle({
		Name         = "Random Head Turns",
		CurrentValue = true,
		Flag         = "HumanizeHead",
		Callback     = function(val)
			if self._human then self._human:SetHeadTurns(val) end
		end,
	})
	tab:CreateToggle({
		Name         = "Idle Pauses",
		CurrentValue = true,
		Flag         = "HumanizeIdle",
		Callback     = function(val)
			if self._human then self._human:SetIdlePauses(val) end
		end,
	})
end

-- ── Tab: Observation ─────────────────────────────────────────────────────────

function UISystem:_buildObservationTab(window)
	local Rayfield = self._rf
	local tab = window:CreateTab("Observation", "activity")

	tab:CreateSection("Tracked Objects")

	-- Placeholder label; refreshed by _refreshLiveTabs
	self._obsLabel = tab:CreateParagraph({
		Title   = "Live tracker list",
		Content = "No tracked objects yet.",
	})
end

-- ── Tab: AI ───────────────────────────────────────────────────────────────────

function UISystem:_buildAITab(window)
	local Rayfield = self._rf
	local tab = window:CreateTab("AI", "cpu")

	tab:CreateSection("Current Route")

	self._aiScoreLabel = tab:CreateParagraph({
		Title   = "Route Scores",
		Content = "No route computed.",
	})

	self._aiRationaleLabel = tab:CreateParagraph({
		Title   = "Decision Rationale",
		Content = "—",
	})

	tab:CreateSection("Replanning")

	tab:CreateSlider({
		Name     = "Replan Cooldown (s)",
		Range    = { 0.1, 5 },
		Increment = 0.1,
		CurrentValue = self._cfg.ReplanCooldown,
		Flag     = "ReplanCooldown",
		Callback = function(val)
			self._cfg.ReplanCooldown = val
		end,
	})
end

-- ── Tab: Debug ────────────────────────────────────────────────────────────────

function UISystem:_buildDebugTab(window)
	local Rayfield = self._rf
	local tab = window:CreateTab("Debug", "terminal")

	tab:CreateSection("Live Stats")

	self._debugLabel = tab:CreateParagraph({
		Title   = "System State",
		Content = "Waiting for navigation...",
	})

	tab:CreateSection("Debug Panel")

	tab:CreateButton({
		Name     = "Toggle Overlay Panel",
		Callback = function()
			if self._debug then self._debug:Toggle() end
		end,
	})

	tab:CreateSection("Graph")

	tab:CreateButton({
		Name     = "Force Full Rescan",
		Callback = function()
			-- Signal via state table; WorldScanner will pick it up next interval
			if self._state then
				self._state.forceRescan = true
			end
			Rayfield:Notify({ Title="Scanner", Content="Full rescan queued.", Duration=2 })
		end,
	})
end

-- ── Live tab refreshes ────────────────────────────────────────────────────────

function UISystem:_refreshLiveTabs()
	local s = self._state
	if not s then return end

	-- Observation tab
	if self._obsLabel and self._obs then
		local tracked = self._obs:GetTrackedObjects()
		local lines   = {}
		for _, obj in ipairs(tracked) do
			local name  = obj.part and obj.part.Name or "?"
			local model = obj.model and obj.model.type or "Fitting"
			local conf  = obj.model and string.format("%.0f%%", obj.model.confidence * 100) or "—"
			lines[#lines+1] = string.format("• %s [%s] conf=%s", name, model, conf)
		end
		self._obsLabel:Set({
			Title   = string.format("Tracked Objects (%d)", #tracked),
			Content = #lines > 0 and table.concat(lines, "\n") or "None",
		})
	end

	-- AI tab
	if self._aiScoreLabel and self._ai then
		local scores = self._ai:GetCurrentScores()
		if scores then
			self._aiScoreLabel:Set({
				Title   = "Route Scores",
				Content = string.format(
					"Total: %.3f\nDist: %.2f  Time: %.2f  Risk: %.2f  Complexity: %.2f\nNodes: %d  Edges: %d",
					scores.total, scores.distance, scores.time, scores.risk, scores.complexity,
					scores.nodeCount or 0, scores.edgeCount or 0
				),
			})
		end
		if self._aiRationaleLabel then
			self._aiRationaleLabel:Set({
				Title   = "Decision Rationale",
				Content = self._ai:GetRationale() or "—",
			})
		end
	end

	-- Debug tab
	if self._debugLabel then
		self._debugLabel:Set({
			Title   = "System State",
			Content = string.format(
				"Action: %s\nWaypoint: %d / %d\nReplans: %d\nNodes: %d  Edges: %d\nFPS: %.0f\nScan: %s ms",
				s.currentAction  or "—",
				s.waypointIndex  or 0,
				s.waypointTotal  or 0,
				s.replanCount    or 0,
				s.nodeCount      or 0,
				s.edgeCount      or 0,
				s.fps            or 0,
				s.scanTimeMs     or "—"
			),
		})
	end
end

return UISystem
