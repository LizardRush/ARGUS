-- GoogleMapsRBX/UI/UISystem.lua
-- Obsidian-based GUI with 6 tabs: Navigation, Visualization,
-- Movement, Observation, AI, Debug.
-- ModuleScript: child of UI folder.

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local UISystem = {}
UISystem.__index = UISystem

-- ── Constructor ───────────────────────────────────────────────────────────────

function UISystem.new(config, ai, controller, viz, human, obs, debugPanel, stateTable, keybinds)
	local self = setmetatable({}, UISystem)
	self._cfg         = config
	self._ai          = ai
	self._ctrl        = controller
	self._viz         = viz
	self._human       = human
	self._obs         = obs
	self._debug       = debugPanel
	self._state       = stateTable
	self._keybinds    = keybinds  -- may be nil in Studio context
	self._lib         = nil
	self._conn        = nil
	self._updateTimer = 0
	self._paused      = false
	-- Live labels updated every 0.5s
	self._obsLabel      = nil
	self._aiScoreLabel  = nil
	self._aiRationale   = nil
	self._debugLabel    = nil
	return self
end

-- ── Public API ────────────────────────────────────────────────────────────────

function UISystem:Initialize()
	local ok, Library = pcall(function()
		return loadstring(game:HttpGet(
			"https://raw.githubusercontent.com/deividcomsono/Obsidian/refs/heads/main/Library.lua"
		))()
	end)
	if not ok or not Library then
		warn("ARGUS: Failed to load Obsidian UI — ensure HttpService is enabled.")
		return
	end
	self._lib = Library

	local Window = Library:CreateWindow({
		Title            = "ARGUS",
		Footer           = "Advanced Reasoning & Geographic Understanding System",
		NotifySide       = "Right",
		ShowCustomCursor = false,
		Center           = true,
		AutoShow         = true,
		ToggleKey        = self._keybinds and self._keybinds.toggleUI or Enum.KeyCode.RightControl,
	})

	self:_buildNavigationTab(Window)
	self:_buildVisualizationTab(Window)
	self:_buildMovementTab(Window)
	self:_buildObservationTab(Window)
	self:_buildAITab(Window)
	self:_buildDebugTab(Window)
	self:_buildSettingsTab(Window)

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
	local lib = self._lib
	local tab = window:AddTab("Navigation", "map-pin")

	-- Left: coordinate destination
	local destBox = tab:AddLeftGroupbox("Go To Position")
	destBox:AddInput("GotoX", { Text = "X", Placeholder = "0", Numeric = true, Callback = function() end })
	destBox:AddInput("GotoY", { Text = "Y", Placeholder = "0", Numeric = true, Callback = function() end })
	destBox:AddInput("GotoZ", { Text = "Z", Placeholder = "0", Numeric = true, Callback = function() end })
	destBox:AddButton({
		Text = "Navigate",
		Func = function()
			local x = tonumber(Options.GotoX.Value) or 0
			local y = tonumber(Options.GotoY.Value) or 0
			local z = tonumber(Options.GotoZ.Value) or 0
			self._ai:GoToPosition(Vector3.new(x, y, z))
			lib:Notify({
				Title       = "Navigation",
				Description = ("→ %.1f, %.1f, %.1f"):format(x, y, z),
				Time        = 3,
			})
		end,
	})

	-- Left: controls
	local ctrlBox = tab:AddLeftGroupbox("Controls")
	ctrlBox:AddButton({
		Text = "Stop",
		Func = function()
			self._ai:Stop()
			lib:Notify({ Title = "Navigation", Description = "Stopped.", Time = 2 })
		end,
	})
	ctrlBox:AddButton({
		Text = "Pause / Resume",
		Func = function()
			if self._paused then
				self._ai:Resume()
				self._paused = false
				lib:Notify({ Title = "Navigation", Description = "Resumed.", Time = 1 })
			else
				self._ai:Pause()
				self._paused = true
				lib:Notify({ Title = "Navigation", Description = "Paused.", Time = 1 })
			end
		end,
	})
	ctrlBox:AddButton({
		Text = "Recalculate Route",
		Func = function()
			self._ai:RecalculatePath()
			lib:Notify({ Title = "Navigation", Description = "Recalculating...", Time = 2 })
		end,
	})
	ctrlBox:AddButton({
		Text = "Export Route",
		Func = function()
			self._ai:ExportRoute()
			lib:Notify({ Title = "Export", Description = "Route printed to output.", Time = 2 })
		end,
	})

	-- Right: part navigation
	local partBox = tab:AddRightGroupbox("Go To Part")
	partBox:AddInput("GotoPartName", {
		Text        = "Part Name",
		Placeholder = "workspace part name",
		Callback    = function() end,
	})
	partBox:AddButton({
		Text = "Go To Part",
		Func = function()
			local name = Options.GotoPartName.Value
			if name and name ~= "" then
				self._ai:GoToPart(name)
				lib:Notify({ Title = "Navigation", Description = "→ " .. name, Time = 3 })
			end
		end,
	})

	-- Right: follow player
	local followBox = tab:AddRightGroupbox("Follow Player")
	local playerNames = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= Players.LocalPlayer then
			playerNames[#playerNames + 1] = p.Name
		end
	end
	if #playerNames == 0 then playerNames = { "No other players" } end

	followBox:AddDropdown("FollowTarget", {
		Values   = playerNames,
		Default  = 1,
		Text     = "Player",
		Callback = function() end,
	})
	followBox:AddButton({
		Text = "Follow Player",
		Func = function()
			local target = Options.FollowTarget.Value
			if target and target ~= "No other players" then
				self._ai:FollowPlayer(target)
				lib:Notify({ Title = "Following", Description = target, Time = 3 })
			end
		end,
	})
end

-- ── Tab: Visualization ────────────────────────────────────────────────────────

function UISystem:_buildVisualizationTab(window)
	local tab = window:AddTab("Visualization", "eye")

	local layerBox = tab:AddLeftGroupbox("Path Layers")
	for _, name in ipairs({ "Walk", "Jump", "Climb", "Advanced", "Platform", "Conveyor", "Fall" }) do
		layerBox:AddToggle("VizLayer" .. name, {
			Text     = name,
			Default  = true,
			Callback = function(val)
				if self._viz then self._viz:SetLayerVisible(name, val) end
			end,
		})
	end

	local mapBox = tab:AddRightGroupbox("Minimap")
	mapBox:AddToggle("MinimapVisible", {
		Text     = "Show Minimap",
		Default  = true,
		Callback = function(val)
			if self._viz and self._viz._minimap then
				self._viz._minimap:SetVisible(val)
			end
		end,
	})
	mapBox:AddSlider("MinimapScale", {
		Text     = "Scale (studs/px)",
		Default  = self._cfg.MinimapScale or 1,
		Min      = 0.2,
		Max      = 5,
		Rounding = 1,
		Callback = function(val)
			if self._viz and self._viz._minimap then
				self._viz._minimap:SetScale(val)
			end
		end,
	})
end

-- ── Tab: Movement ─────────────────────────────────────────────────────────────

function UISystem:_buildMovementTab(window)
	local tab = window:AddTab("Movement", "zap")

	local speedBox = tab:AddLeftGroupbox("Speed")
	speedBox:AddSlider("SpeedMult", {
		Text     = "Multiplier",
		Default  = 1.0,
		Min      = 0.5,
		Max      = 2.5,
		Rounding = 2,
		Suffix   = "×",
		Callback = function(val)
			self._cfg.WalkSpeed = 16 * val
		end,
	})

	local techBox = tab:AddLeftGroupbox("Techniques")
	for _, name in ipairs({
		"Walk", "Jump", "ClimbLadder", "ClimbTruss", "Swim",
		"RideElevator", "RideConveyor", "RidePlatform",
		"SafeFall", "GapCross", "StairClimb", "CornerCut", "JumpChain",
	}) do
		techBox:AddToggle("Tech" .. name, {
			Text     = name,
			Default  = true,
			Callback = function(val)
				if not self._cfg.DisabledTechniques then
					self._cfg.DisabledTechniques = {}
				end
				self._cfg.DisabledTechniques[name] = not val
			end,
		})
	end
end

-- ── Tab: Observation ─────────────────────────────────────────────────────────

function UISystem:_buildObservationTab(window)
	local tab    = window:AddTab("Observation", "activity")
	local obsBox = tab:AddLeftGroupbox("Tracked Objects")
	self._obsLabel = obsBox:AddLabel("No tracked objects.", true)
end

-- ── Tab: AI ───────────────────────────────────────────────────────────────────

function UISystem:_buildAITab(window)
	local tab = window:AddTab("AI", "cpu")

	local scoresBox = tab:AddLeftGroupbox("Route Scores")
	self._aiScoreLabel = scoresBox:AddLabel("No route computed.", true)

	local ratBox = tab:AddRightGroupbox("Decision Rationale")
	self._aiRationale = ratBox:AddLabel("—", true)

	local settingsBox = tab:AddRightGroupbox("Settings")
	settingsBox:AddSlider("ReplanCooldown", {
		Text     = "Replan Cooldown",
		Default  = self._cfg.ReplanCooldown or 0.5,
		Min      = 0.1,
		Max      = 5,
		Rounding = 1,
		Suffix   = "s",
		Callback = function(val)
			self._cfg.ReplanCooldown = val
		end,
	})
end

-- ── Tab: Debug ────────────────────────────────────────────────────────────────

function UISystem:_buildDebugTab(window)
	local lib = self._lib
	local tab = window:AddTab("Debug", "terminal")

	local statsBox = tab:AddLeftGroupbox("System State")
	self._debugLabel = statsBox:AddLabel("Waiting for navigation...", true)

	local actBox = tab:AddRightGroupbox("Actions")
	actBox:AddButton({
		Text = "Toggle Overlay Panel",
		Func = function()
			if self._debug then self._debug:Toggle() end
		end,
	})
	actBox:AddButton({
		Text = "Force Full Rescan",
		Func = function()
			if self._state then self._state.forceRescan = true end
			lib:Notify({ Title = "Scanner", Description = "Full rescan queued.", Time = 2 })
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
		if #tracked == 0 then
			self._obsLabel:SetText("No tracked objects.")
		else
			local lines = { ("Tracking %d object(s)"):format(#tracked) }
			for _, obj in ipairs(tracked) do
				local name  = obj.part and obj.part.Name or "?"
				local model = obj.model and obj.model.type or "Fitting"
				local conf  = obj.model and ("%.0f%%"):format(obj.model.confidence * 100) or "—"
				lines[#lines + 1] = ("• %s  [%s]  %s"):format(name, model, conf)
			end
			self._obsLabel:SetText(table.concat(lines, "\n"))
		end
	end

	-- AI tab
	if self._aiScoreLabel and self._ai then
		local scores = self._ai:GetCurrentScores()
		if scores then
			self._aiScoreLabel:SetText(
				("Total:  %.3f\nDist:   %.2f    Time: %.2f\nRisk:   %.2f    Complexity: %.2f\nNodes: %d    Edges: %d"):format(
					scores.total,
					scores.distance, scores.time,
					scores.risk, scores.complexity,
					scores.nodeCount or 0, scores.edgeCount or 0
				)
			)
		end
		if self._aiRationale then
			self._aiRationale:SetText(self._ai:GetRationale() or "—")
		end
	end

	-- Debug tab
	if self._debugLabel then
		self._debugLabel:SetText(
			("Action:   %s\nWaypoint: %d / %d\nReplans:  %d\nNodes:    %d    Edges: %d\nFPS:      %.0f\nScan:     %s ms"):format(
				s.currentAction or "—",
				s.waypointIndex or 0,
				s.waypointTotal or 0,
				s.replanCount   or 0,
				s.nodeCount     or 0,
				s.edgeCount     or 0,
				s.fps           or 0,
				tostring(s.scanTimeMs or "—")
			)
		)
	end
end

-- ── Tab: Settings ────────────────────────────────────────────────────────────

function UISystem:_buildSettingsTab(window)
	local lib = self._lib
	local tab = window:AddTab("Settings", "sliders-horizontal")

	-- Left: keybinds (executor-only; _keybinds is nil in Studio)
	local bindBox = tab:AddLeftGroupbox("Keybinds")
	if self._keybinds then
		bindBox:AddKeybind("FreecamKey", {
			Text     = "Freecam",
			Default  = self._keybinds.freecam  or Enum.KeyCode.G,
			Callback = function(val)
				self._keybinds.freecam = val
			end,
		})
		bindBox:AddKeybind("ToggleUIKey", {
			Text     = "Toggle UI",
			Default  = self._keybinds.toggleUI or Enum.KeyCode.RightControl,
			Callback = function(val)
				self._keybinds.toggleUI = val
				lib:Notify({ Title = "Settings", Description = "UI toggle key saved — takes effect next launch.", Time = 3 })
			end,
		})
	else
		bindBox:AddLabel("Keybinds are only configurable\nwhen running via the executor.", true)
	end

	-- Right: misc
	local miscBox = tab:AddRightGroupbox("Misc")
	miscBox:AddSlider("FreecamSpeed", {
		Text     = "Freecam Speed",
		Default  = self._cfg.FreecamSpeed or 32,
		Min      = 8,
		Max      = 128,
		Rounding = 0,
		Suffix   = " st/s",
		Callback = function(val)
			self._cfg.FreecamSpeed = val
		end,
	})
	miscBox:AddSlider("ScanRadius", {
		Text     = "Scan Radius",
		Default  = self._cfg.ScanRadius or 50,
		Min      = 20,
		Max      = 150,
		Rounding = 0,
		Suffix   = " st",
		Callback = function(val)
			self._cfg.ScanRadius = val
		end,
	})
	miscBox:AddSlider("NodeSpacing", {
		Text     = "Node Spacing",
		Default  = self._cfg.NodeSpacing or 4,
		Min      = 1,
		Max      = 10,
		Rounding = 1,
		Suffix   = " st",
		Callback = function(val)
			self._cfg.NodeSpacing = val
		end,
	})
end

function UISystem:Notify(title, description, time)
	if not self._lib then return end
	pcall(function()
		self._lib:Notify({ Title = title, Description = description, Time = time or 3 })
	end)
end

return UISystem
