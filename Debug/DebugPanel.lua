-- GoogleMapsRBX/Debug/DebugPanel.lua
-- Live stats ScreenGui panel. Reads from a shared StateTable that
-- all systems write into; updates at ≤10 Hz to minimize overhead.
-- ModuleScript: child of Debug folder.

local RunService   = game:GetService("RunService")
local Players      = game:GetService("Players")

local DebugPanel = {}
DebugPanel.__index = DebugPanel

-- ── Constructor ───────────────────────────────────────────────────────────────

function DebugPanel.new(config, stateTable)
	local self = setmetatable({}, DebugPanel)
	self._cfg      = config
	self._state    = stateTable
	self._gui      = nil
	self._conn     = nil
	self._timer    = 0
	self._interval = 1 / config.DebugUpdateHz
	self._labels   = {}
	self._logLines = {}
	self._maxLog   = 50
	self._visible  = false
	return self
end

-- ── Public API ────────────────────────────────────────────────────────────────

function DebugPanel:Initialize()
	self:_buildGui()
end

function DebugPanel:Show()
	self._visible = true
	if self._gui then self._gui.Enabled = true end
	if not self._conn then self:_start() end
end

function DebugPanel:Hide()
	self._visible = false
	if self._gui then self._gui.Enabled = false end
	self:_stop()
end

function DebugPanel:Toggle()
	if self._visible then self:Hide() else self:Show() end
end

function DebugPanel:AddLog(message)
	table.insert(self._logLines, 1, string.format("[%.1f] %s", tick() % 1000, message))
	if #self._logLines > self._maxLog then
		table.remove(self._logLines, #self._logLines)
	end
	self:_updateLog()
end

-- ── GUI builder ───────────────────────────────────────────────────────────────

function DebugPanel:_buildGui()
	local player    = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui    = Instance.new("ScreenGui")
	screenGui.Name     = "ARGUS_Debug"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled  = false
	screenGui.Parent   = playerGui

	-- Main frame
	local frame      = Instance.new("Frame")
	frame.Name       = "DebugFrame"
	frame.Size       = UDim2.new(0, 320, 0, 480)
	frame.Position   = UDim2.new(0, 8, 0.5, -240)
	frame.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Parent     = screenGui

	-- Corner rounding
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame

	-- Title
	local title = Instance.new("TextLabel")
	title.Text  = "ARGUS — Debug"
	title.Font  = Enum.Font.GothamBold
	title.TextSize = 13
	title.TextColor3 = Color3.fromHex("00cc44")
	title.BackgroundTransparency = 1
	title.Size  = UDim2.new(1, -8, 0, 22)
	title.Position = UDim2.new(0, 8, 0, 4)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = frame

	-- Scrolling stats frame
	local scroll    = Instance.new("ScrollingFrame")
	scroll.Name     = "StatsScroll"
	scroll.Size     = UDim2.new(1, -8, 0, 280)
	scroll.Position = UDim2.new(0, 4, 0, 30)
	scroll.BackgroundTransparency = 1
	scroll.ScrollBarThickness = 3
	scroll.ScrollBarImageColor3 = Color3.fromHex("00cc44")
	scroll.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding   = UDim.new(0, 1)
	layout.Parent    = scroll

	-- Stats labels
	local statKeys = {
		"CurrentNode", "NextNode", "Action",
		"WaypointIdx", "WaypointTotal",
		"Replans", "RouteScore",
		"NodeCount", "EdgeCount",
		"ScanTimeMs", "AStarIter",
		"FPS", "TrackedObjects",
		"Rationale",
	}

	for _, key in ipairs(statKeys) do
		local row = Instance.new("Frame")
		row.Size  = UDim2.new(1, 0, 0, 16)
		row.BackgroundTransparency = 1
		row.Parent = scroll

		local keyLabel      = Instance.new("TextLabel")
		keyLabel.Text       = key .. ":"
		keyLabel.Font       = Enum.Font.Gotham
		keyLabel.TextSize   = 11
		keyLabel.TextColor3 = Color3.fromHex("aaaaaa")
		keyLabel.BackgroundTransparency = 1
		keyLabel.Size       = UDim2.new(0.45, 0, 1, 0)
		keyLabel.TextXAlignment = Enum.TextXAlignment.Left
		keyLabel.Parent     = row

		local valLabel      = Instance.new("TextLabel")
		valLabel.Text       = "—"
		valLabel.Font       = Enum.Font.GothamBold
		valLabel.TextSize   = 11
		valLabel.TextColor3 = Color3.fromHex("ffffff")
		valLabel.BackgroundTransparency = 1
		valLabel.Size       = UDim2.new(0.55, 0, 1, 0)
		valLabel.Position   = UDim2.new(0.45, 0, 0, 0)
		valLabel.TextXAlignment = Enum.TextXAlignment.Left
		valLabel.Parent     = row

		self._labels[key] = valLabel
	end

	-- Update scroll canvas size
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y)
	end)

	-- Log frame (bottom half)
	local logFrame    = Instance.new("Frame")
	logFrame.Name     = "LogFrame"
	logFrame.Size     = UDim2.new(1, -8, 0, 145)
	logFrame.Position = UDim2.new(0, 4, 0, 320)
	logFrame.BackgroundColor3 = Color3.fromRGB(5, 5, 8)
	logFrame.BackgroundTransparency = 0.3
	logFrame.BorderSizePixel = 0
	logFrame.Parent   = frame

	local logTitle = Instance.new("TextLabel")
	logTitle.Text  = "Event Log"
	logTitle.Font  = Enum.Font.GothamBold
	logTitle.TextSize = 10
	logTitle.TextColor3 = Color3.fromHex("00cc44")
	logTitle.BackgroundTransparency = 1
	logTitle.Size  = UDim2.new(1, 0, 0, 14)
	logTitle.TextXAlignment = Enum.TextXAlignment.Left
	logTitle.Parent = logFrame

	local logScroll  = Instance.new("ScrollingFrame")
	logScroll.Name   = "LogScroll"
	logScroll.Size   = UDim2.new(1, 0, 1, -16)
	logScroll.Position = UDim2.new(0, 0, 0, 16)
	logScroll.BackgroundTransparency = 1
	logScroll.ScrollBarThickness = 2
	logScroll.Parent = logFrame

	local logLayout  = Instance.new("UIListLayout")
	logLayout.SortOrder = Enum.SortOrder.LayoutOrder
	logLayout.Parent = logScroll

	self._logScroll  = logScroll
	self._logLayout  = logLayout

	self._gui        = screenGui
	self._statsScroll = scroll
end

-- ── Update loop ───────────────────────────────────────────────────────────────

function DebugPanel:_start()
	self._conn = RunService.Heartbeat:Connect(function(dt)
		self._timer = self._timer + dt
		if self._timer >= self._interval then
			self._timer = 0
			self:_refresh()
		end
	end)
end

function DebugPanel:_stop()
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
end

function DebugPanel:_refresh()
	local s = self._state
	if not s then return end

	local function set(key, val)
		local lbl = self._labels[key]
		if lbl then lbl.Text = tostring(val) end
	end

	set("CurrentNode",   s.currentNodeId   or "—")
	set("NextNode",      s.nextNodeId      or "—")
	set("Action",        s.currentAction   or "—")
	set("WaypointIdx",   s.waypointIndex   or 0)
	set("WaypointTotal", s.waypointTotal   or 0)
	set("Replans",       s.replanCount     or 0)
	set("RouteScore",    s.routeScore and string.format("%.3f", s.routeScore) or "—")
	set("NodeCount",     s.nodeCount       or 0)
	set("EdgeCount",     s.edgeCount       or 0)
	set("ScanTimeMs",    s.scanTimeMs and (s.scanTimeMs .. " ms") or "—")
	set("AStarIter",     s.astarIterations or 0)
	set("FPS",           s.fps and string.format("%.0f", s.fps) or "—")
	set("TrackedObjects", s.trackedObjects or 0)
	set("Rationale",     s.rationale and s.rationale:sub(1, 60) or "—")
end

function DebugPanel:_updateLog()
	if not self._logScroll then return end
	-- Clear and rebuild (pool would be better but this is ≤50 lines)
	for _, child in ipairs(self._logScroll:GetChildren()) do
		if child:IsA("TextLabel") then child:Destroy() end
	end
	for i, line in ipairs(self._logLines) do
		local lbl = Instance.new("TextLabel")
		lbl.Text  = line
		lbl.Font  = Enum.Font.Code
		lbl.TextSize = 9
		lbl.TextColor3 = Color3.fromHex("88ff88")
		lbl.BackgroundTransparency = 1
		lbl.Size  = UDim2.new(1, 0, 0, 12)
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.LayoutOrder = i
		lbl.Parent = self._logScroll
	end
	self._logScroll.CanvasSize = UDim2.new(0, 0, 0,
		self._logLayout.AbsoluteContentSize.Y)
end

return DebugPanel
