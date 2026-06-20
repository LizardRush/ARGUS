-- GoogleMapsRBX/Visualization/MinimapPanel.lua
-- 2D overhead mini-map rendered as a ScreenGui frame.
-- Uses Frame-based pixel rendering for broad Roblox compatibility.
-- ModuleScript: child of Visualization folder.

local RunService = game:GetService("RunService")
local Players    = game:GetService("Players")

local MinimapPanel = {}
MinimapPanel.__index = MinimapPanel

local MINIMAP_PX  = 200
local PIXEL_SIZE  = 2   -- each "pixel" is a 2×2 Frame

function MinimapPanel.new(config)
	local self = setmetatable({}, MinimapPanel)
	self._cfg      = config
	self._scale    = config.MinimapScale  -- studs per pixel
	self._gui      = nil
	self._frame    = nil
	self._pixelMap = {}   -- flat index → Frame (pooled)
	self._conn     = nil
	self._timer    = 0
	self._interval = 1 / config.MinimapUpdateHz
	self._visible  = true
	self._nodes    = {}   -- set externally
	self._path     = {}   -- flat Vector3 array
	self._origin   = Vector3.zero
	return self
end

-- ── Public API ────────────────────────────────────────────────────────────────

function MinimapPanel:Initialize()
	self:_buildGui()
	self:Start()
end

function MinimapPanel:SetVisible(v)
	self._visible = v
	if self._frame then self._frame.Visible = v end
end

function MinimapPanel:SetScale(studsPerPixel)
	self._scale = math.max(0.1, studsPerPixel)
end

function MinimapPanel:SetNodes(nodes)
	self._nodes = nodes
end

function MinimapPanel:SetPath(flatPositions)
	self._path = flatPositions or {}
end

function MinimapPanel:Start()
	self:Stop()
	self._conn = RunService.Heartbeat:Connect(function(dt)
		self._timer = self._timer + dt
		if self._timer >= self._interval then
			self._timer = 0
			self:_render()
		end
	end)
end

function MinimapPanel:Stop()
	if self._conn then self._conn:Disconnect() self._conn = nil end
end

-- ── GUI builder ───────────────────────────────────────────────────────────────

function MinimapPanel:_buildGui()
	local player    = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui    = Instance.new("ScreenGui")
	screenGui.Name     = "ARGUS_Minimap"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent   = playerGui

	local outer = Instance.new("Frame")
	outer.Name  = "MinimapOuter"
	outer.Size  = UDim2.new(0, MINIMAP_PX + 8, 0, MINIMAP_PX + 24)
	outer.Position = UDim2.new(1, -(MINIMAP_PX + 16), 1, -(MINIMAP_PX + 32))
	outer.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
	outer.BackgroundTransparency = 0.2
	outer.BorderSizePixel = 0
	outer.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = outer

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Text  = "Minimap"
	titleLabel.Font  = Enum.Font.GothamBold
	titleLabel.TextSize = 11
	titleLabel.TextColor3 = Color3.fromHex("00cc44")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size  = UDim2.new(1, 0, 0, 16)
	titleLabel.Position = UDim2.new(0, 4, 0, 2)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = outer

	-- Scale label
	local scaleLabel  = Instance.new("TextLabel")
	scaleLabel.Name   = "ScaleLabel"
	scaleLabel.Text   = string.format("%.1f s/px", self._scale)
	scaleLabel.Font   = Enum.Font.Gotham
	scaleLabel.TextSize = 9
	scaleLabel.TextColor3 = Color3.fromHex("888888")
	scaleLabel.BackgroundTransparency = 1
	scaleLabel.Size   = UDim2.new(0, 80, 0, 14)
	scaleLabel.Position = UDim2.new(1, -84, 0, 2)
	scaleLabel.TextXAlignment = Enum.TextXAlignment.Right
	scaleLabel.Parent = outer
	self._scaleLabel  = scaleLabel

	-- Canvas frame
	local canvas    = Instance.new("Frame")
	canvas.Name     = "Canvas"
	canvas.Size     = UDim2.new(0, MINIMAP_PX, 0, MINIMAP_PX)
	canvas.Position = UDim2.new(0, 4, 0, 20)
	canvas.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	canvas.BorderSizePixel  = 1
	canvas.Parent           = outer
	self._canvas            = canvas
	self._frame             = outer

	-- Pre-allocate pixel pool
	local cells = math.floor(MINIMAP_PX / PIXEL_SIZE)
	for i = 1, cells * cells do
		local dot        = Instance.new("Frame")
		dot.Size         = UDim2.new(0, PIXEL_SIZE, 0, PIXEL_SIZE)
		dot.BorderSizePixel = 0
		dot.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
		dot.Visible      = false
		dot.Parent       = canvas
		self._pixelMap[i] = dot
	end

	-- Player dot (always on top)
	local playerDot = Instance.new("Frame")
	playerDot.Name  = "PlayerDot"
	playerDot.Size  = UDim2.new(0, 5, 0, 5)
	playerDot.BackgroundColor3 = Color3.fromHex("ffffff")
	playerDot.BorderSizePixel  = 0
	playerDot.ZIndex           = 10
	playerDot.Parent           = canvas
	self._playerDot = playerDot

	local pCorner = Instance.new("UICorner")
	pCorner.CornerRadius = UDim.new(1, 0)
	pCorner.Parent = playerDot

	self._gui = screenGui
end

-- ── Render pass ───────────────────────────────────────────────────────────────

function MinimapPanel:_render()
	if not self._visible then return end
	local character = Players.LocalPlayer.Character
	if not character then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local origin  = root.Position
	self._origin  = origin
	local scale   = self._scale
	local cells   = math.floor(MINIMAP_PX / PIXEL_SIZE)
	local center  = math.floor(cells / 2)
	local cfg     = self._cfg

	-- Clear all pixels
	for _, dot in ipairs(self._pixelMap) do
		dot.Visible = false
		dot.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	end

	-- Draw nodes
	local nodeColor = cfg.Color.Node
	for _, node in pairs(self._nodes) do
		local px, pz = self:_worldToPx(node.position, origin, scale, center)
		self:_drawPx(px, pz, cells, nodeColor)
	end

	-- Draw path in route color
	for _, pos in ipairs(self._path) do
		local px, pz = self:_worldToPx(pos, origin, scale, center)
		self:_drawPx(px, pz, cells, cfg.Color.Walk)
	end

	-- Draw player dot at center
	self._playerDot.Position = UDim2.new(0,
		center * PIXEL_SIZE - 2, 0,
		center * PIXEL_SIZE - 2)
	self._playerDot.Visible = true

	-- Update scale label
	if self._scaleLabel then
		self._scaleLabel.Text = string.format("%.1f s/px", scale)
	end
end

function MinimapPanel:_worldToPx(pos, origin, scale, center)
	local dx = pos.X - origin.X
	local dz = pos.Z - origin.Z
	local px  = center + math.floor(dx / scale)
	local pz  = center + math.floor(dz / scale)
	return px, pz
end

function MinimapPanel:_drawPx(px, pz, cells, color)
	if px < 0 or px >= cells or pz < 0 or pz >= cells then return end
	local idx = pz * cells + px + 1
	local dot = self._pixelMap[idx]
	if dot then
		dot.Position = UDim2.new(0, px * PIXEL_SIZE, 0, pz * PIXEL_SIZE)
		dot.BackgroundColor3 = color
		dot.Visible = true
	end
end

return MinimapPanel
