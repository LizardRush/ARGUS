-- GoogleMapsRBX/Visualization/VisualizationSystem.lua
-- Renders the navigation path in 3D using Beams, Attachments,
-- BillboardGuis, and SelectionBoxes. Uses object pooling so no
-- instances are created/destroyed during runtime updates.
-- ModuleScript: child of Visualization folder.

local RunService = game:GetService("RunService")
local Players    = game:GetService("Players")

local VisualizationSystem = {}
VisualizationSystem.__index = VisualizationSystem

-- ── Layer names and their edge types ─────────────────────────────────────────
local LAYERS = {
	Walk        = { edgeTypes = { Walk=true },          colorKey = "Walk"        },
	Jump        = { edgeTypes = { Jump=true },           colorKey = "Jump"        },
	Climb       = { edgeTypes = { ClimbLadder=true, ClimbTruss=true }, colorKey="Climb" },
	Advanced    = { edgeTypes = { GapCross=true, JumpChain=true, StairClimb=true }, colorKey="Advanced" },
	Platform    = { edgeTypes = { RideElevator=true, RidePlatform=true }, colorKey="Platform" },
	Conveyor    = { edgeTypes = { RideConveyor=true },   colorKey = "Conveyor"    },
	Fall        = { edgeTypes = { Fall=true },            colorKey = "Advanced"    },
	Destination = { edgeTypes = { Destination=true },    colorKey = "Destination" },
}

-- ── Constructor ───────────────────────────────────────────────────────────────

function VisualizationSystem.new(config, minimap)
	local self = setmetatable({}, VisualizationSystem)
	self._cfg       = config
	self._minimap   = minimap
	self._rootFolder = nil
	self._layerFolders = {}
	self._layerVisible = {}
	self._beamPool    = {}    -- free beams
	self._labelPool   = {}    -- free BillboardGuis
	self._activeBeams = {}    -- currently displayed beams
	self._activeLabels = {}
	self._selBoxes    = {}    -- {current, destination} SelectionBoxes
	self._path        = nil
	self._conn        = nil
	self._timer       = 0
	self._dirty       = false

	for name in pairs(LAYERS) do
		self._layerVisible[name] = true
	end
	return self
end

-- ── Public API ────────────────────────────────────────────────────────────────

function VisualizationSystem:Initialize()
	self:_buildWorldFolder()
	self:_buildSelectionBoxes()
end

function VisualizationSystem:SetPath(path)
	self._path  = path
	self._dirty = true
	-- Update minimap with flat positions
	if self._minimap and path and path.nodes then
		local flat = {}
		for _, node in ipairs(path.nodes) do
			flat[#flat+1] = node.position
		end
		self._minimap:SetPath(flat)
	end
	self:_rebuildVisuals()
end

function VisualizationSystem:ClearPath()
	self._path = nil
	self:_returnAllToPool()
	self:_hideSelectionBoxes()
	if self._minimap then self._minimap:SetPath({}) end
end

function VisualizationSystem:SetLayerVisible(layerName, visible)
	self._layerVisible[layerName] = visible
	local folder = self._layerFolders[layerName]
	if folder then
		-- Simply parent/unparent children to hide/show efficiently
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("BasePart") or child:IsA("Model") then
				child.Transparency = visible and 0 or 1
			end
		end
	end
	if self._path then self:_rebuildVisuals() end
end

function VisualizationSystem:UpdateNodes(nodes)
	if self._minimap then
		self._minimap:SetNodes(nodes)
	end
end

-- ── World folder ──────────────────────────────────────────────────────────────

function VisualizationSystem:_buildWorldFolder()
	-- Remove old folder if it exists
	local existing = workspace:FindFirstChild("ARGUS_Viz")
	if existing then existing:Destroy() end

	local root      = Instance.new("Folder")
	root.Name       = "ARGUS_Viz"
	root.Parent     = workspace
	self._rootFolder = root

	for name in pairs(LAYERS) do
		local f     = Instance.new("Folder")
		f.Name      = name
		f.Parent    = root
		self._layerFolders[name] = f
	end
end

function VisualizationSystem:_buildSelectionBoxes()
	local function makeSB(color)
		local sb = Instance.new("SelectionBox")
		sb.Color3 = color
		sb.LineThickness = 0.05
		sb.SurfaceTransparency = 0.8
		sb.Parent = self._rootFolder
		sb.Adornee = nil
		return sb
	end
	self._selBoxes.current     = makeSB(Color3.fromHex("00ff88"))
	self._selBoxes.destination = makeSB(Color3.fromHex("ffffff"))
end

function VisualizationSystem:_hideSelectionBoxes()
	if self._selBoxes.current then self._selBoxes.current.Adornee = nil end
	if self._selBoxes.destination then self._selBoxes.destination.Adornee = nil end
end

-- ── Beam/Label pool ───────────────────────────────────────────────────────────

function VisualizationSystem:_getBeam(layerName)
	local pooled = table.remove(self._beamPool)
	if pooled then
		pooled.beam.Parent = self._layerFolders[layerName] or self._rootFolder
		return pooled
	end
	-- Create anchor parts and beam
	local partA = Instance.new("Part")
	partA.Anchored   = true
	partA.CanCollide = false
	partA.Transparency = 1
	partA.Size = Vector3.new(0.1, 0.1, 0.1)
	partA.CastShadow = false

	local partB = partA:Clone()

	local attA = Instance.new("Attachment", partA)
	local attB = Instance.new("Attachment", partB)

	local beam = Instance.new("Beam")
	beam.Attachment0   = attA
	beam.Attachment1   = attB
	beam.Width0        = self._cfg.BeamWidth
	beam.Width1        = self._cfg.BeamWidth
	beam.FaceCamera    = true
	beam.Transparency  = NumberSequence.new(0.2)
	beam.LightEmission = 0.4
	beam.Segments      = 4

	local folder = self._layerFolders[layerName] or self._rootFolder
	partA.Parent = folder
	partB.Parent = folder
	beam.Parent  = folder

	return { beam=beam, partA=partA, partB=partB, attA=attA, attB=attB }
end

function VisualizationSystem:_returnBeam(entry)
	if entry.partA then entry.partA.Parent = self._rootFolder end
	if entry.partB then entry.partB.Parent = self._rootFolder end
	if entry.beam  then entry.beam.Parent  = self._rootFolder end
	table.insert(self._beamPool, entry)
end

function VisualizationSystem:_getLabel()
	local pooled = table.remove(self._labelPool)
	if pooled then return pooled end

	local part = Instance.new("Part")
	part.Anchored    = true
	part.CanCollide  = false
	part.Transparency = 1
	part.Size        = Vector3.new(0.1, 0.1, 0.1)
	part.CastShadow  = false

	local bb = Instance.new("BillboardGui", part)
	bb.Size  = UDim2.new(0, 60, 0, 20)
	bb.AlwaysOnTop = false
	bb.StudsOffset = Vector3.new(0, 1.2, 0)
	bb.MaxDistance = 60

	local lbl = Instance.new("TextLabel", bb)
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 10
	lbl.TextColor3 = Color3.fromHex("ffffff")
	lbl.TextStrokeTransparency = 0.5

	return { part=part, bb=bb, label=lbl }
end

function VisualizationSystem:_returnLabel(entry)
	if entry.part then entry.part.Parent = self._rootFolder end
	table.insert(self._labelPool, entry)
end

function VisualizationSystem:_returnAllToPool()
	for _, entry in ipairs(self._activeBeams) do
		self:_returnBeam(entry)
	end
	for _, entry in ipairs(self._activeLabels) do
		self:_returnLabel(entry)
	end
	self._activeBeams  = {}
	self._activeLabels = {}
end

-- ── Main rebuild ─────────────────────────────────────────────────────────────

function VisualizationSystem:_rebuildVisuals()
	self:_returnAllToPool()
	self:_hideSelectionBoxes()

	local path = self._path
	if not path or not path.nodes or #path.nodes < 2 then return end

	local cfg    = self._cfg
	local nodes  = path.nodes
	local edges  = path.edges
	local goalDist = (nodes[1].position - nodes[#nodes].position).Magnitude

	-- Camera position for distance culling
	local cam     = workspace.CurrentCamera
	local camPos  = cam.CFrame.Position
	local cullR   = cfg.ScanRadius * 2

	for i = 1, #edges do
		local edge     = edges[i]
		local fromNode = nodes[i]
		local toNode   = nodes[i+1]
		if not edge or not fromNode or not toNode then continue end

		-- Cull distant edges
		local midPt = (fromNode.position + toNode.position) * 0.5
		if (midPt - camPos).Magnitude > cullR then continue end

		-- Determine layer
		local layerName  = self:_edgeLayer(edge.edgeType)
		if not self._layerVisible[layerName] then continue end

		local colorKey   = LAYERS[layerName] and LAYERS[layerName].colorKey or "Walk"
		local color      = cfg.Color[colorKey] or cfg.Color.Walk

		-- Beam
		local beamEntry = self:_getBeam(layerName)
		beamEntry.partA.Position = fromNode.position + Vector3.new(0, 0.3, 0)
		beamEntry.partB.Position = toNode.position   + Vector3.new(0, 0.3, 0)
		beamEntry.beam.Color     = ColorSequence.new(color)
		self._activeBeams[#self._activeBeams+1] = beamEntry

		-- Distance label on every 3rd node
		if i % 3 == 1 then
			local distToGoal = (toNode.position - nodes[#nodes].position).Magnitude
			local labelEntry = self:_getLabel()
			labelEntry.part.Position = toNode.position + Vector3.new(0, 1.5, 0)
			labelEntry.part.Parent   = self._layerFolders[layerName] or self._rootFolder
			labelEntry.label.Text    = string.format("%.0fm\n%s", distToGoal, edge.edgeType)
			labelEntry.label.TextColor3 = color
			self._activeLabels[#self._activeLabels+1] = labelEntry
		end
	end

	-- SelectionBox on current node and destination
	local character = Players.LocalPlayer.Character
	if character then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			-- Nearest node to current position: just highlight the first remaining node
			local firstNode = nodes[1]
			if firstNode and firstNode.part then
				self._selBoxes.current.Adornee = firstNode.part
			end
		end
	end
	local lastNode = nodes[#nodes]
	if lastNode and lastNode.part then
		self._selBoxes.destination.Adornee = lastNode.part
	end
end

function VisualizationSystem:_edgeLayer(edgeType)
	for name, layerDef in pairs(LAYERS) do
		if layerDef.edgeTypes[edgeType] then return name end
	end
	return "Walk"
end

return VisualizationSystem
