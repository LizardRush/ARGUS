-- GoogleMapsRBX/Movement/Techniques/CornerCut.lua
-- When a path turns sharply (>45°), cut the corner by targeting
-- a point on the diagonal to reduce total travel distance.

local CornerCut = {}
CornerCut.__index = CornerCut

function CornerCut.new()
	return setmetatable({}, CornerCut)
end

-- Requires access to the next waypoint to detect the turn angle.
-- ctx.nextNode must be populated by MovementController.
function CornerCut:CanUse(ctx)
	if ctx.edge.edgeType ~= "Walk" then return false end
	if not ctx.nextNode then return false end

	local a = ctx.fromNode.position
	local b = ctx.toNode.position
	local c = ctx.nextNode.position

	local ab = (b - a)
	local bc = (c - b)
	if ab.Magnitude < 0.1 or bc.Magnitude < 0.1 then return false end

	local dot = ab.Unit:Dot(bc.Unit)
	-- Activate when direction changes by more than 45° (cos 45° ≈ 0.707)
	return dot < 0.707
end

function CornerCut:Execute(ctx)
	local humanoid = ctx.humanoid
	local root     = ctx.rootPart
	local b        = ctx.toNode.position
	local c        = ctx.nextNode.position
	local cfg      = ctx.config

	-- Target point 1.5 studs before the corner on the diagonal
	local bc      = (c - b)
	local cutDist = math.min(1.5, bc.Magnitude * 0.4)
	local cutPt   = b + bc.Unit * cutDist

	humanoid.WalkSpeed = cfg.WalkSpeed * 1.05
	humanoid:MoveTo(cutPt)

	local t0   = tick()
	local arrived = false
	local conn = humanoid.MoveToFinished:Connect(function(reached)
		arrived = reached
	end)

	while not arrived do
		task.wait(0.04)
		if (root.Position - cutPt).Magnitude < cfg.ReachDistance then
			arrived = true
			break
		end
		if tick() - t0 > 6 then break end
	end

	humanoid.WalkSpeed = cfg.WalkSpeed
	conn:Disconnect()
	return arrived or (root.Position - b).Magnitude < cfg.ReachDistance * 2
end

function CornerCut:EstimateCost(ctx)
	return ctx.config.EdgeCost.Walk * 0.85  -- slightly cheaper than a full Walk
end

function CornerCut:EstimateSuccessRate(_ctx)
	return 0.95
end

function CornerCut:DebugInfo(ctx)
	local b   = ctx.toNode.position
	local c   = ctx.nextNode and ctx.nextNode.position or b
	local dot = (b - ctx.fromNode.position).Unit:Dot((c - b).Unit)
	return string.format("CornerCut angle=%.0f°", math.deg(math.acos(math.clamp(dot,-1,1))))
end

return CornerCut
