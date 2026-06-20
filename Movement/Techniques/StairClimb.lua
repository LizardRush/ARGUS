-- GoogleMapsRBX/Movement/Techniques/StairClimb.lua
-- Rapid MoveTo updates stepping up each individual stair face.
-- Activated when the edge is a Walk with a small positive Y delta
-- indicating a step (0.5 - 2.5 studs tall).

local StairClimb = {}
StairClimb.__index = StairClimb

function StairClimb.new()
	return setmetatable({}, StairClimb)
end

function StairClimb:CanUse(ctx)
	if ctx.edge.edgeType ~= "Walk" then return false end
	local dy = ctx.toNode.position.Y - ctx.fromNode.position.Y
	return dy >= 0.4 and dy <= 2.5
end

function StairClimb:Execute(ctx)
	local humanoid = ctx.humanoid
	local root     = ctx.rootPart
	local toPos    = ctx.toNode.position
	local cfg      = ctx.config

	-- Jump-assist for stair height
	humanoid.WalkSpeed = cfg.WalkSpeed * 0.85
	humanoid:MoveTo(toPos)

	-- Small jump to crest the stair lip
	humanoid.Jump = true

	local arrived = false
	local t0      = tick()
	local conn    = humanoid.MoveToFinished:Connect(function(reached)
		arrived = reached
	end)

	while not arrived do
		task.wait(0.05)
		if (root.Position - toPos).Magnitude < cfg.ReachDistance then
			arrived = true
			break
		end
		if tick() - t0 > 6 then break end
	end

	humanoid.WalkSpeed = cfg.WalkSpeed
	conn:Disconnect()
	return arrived or (root.Position - toPos).Magnitude < cfg.ReachDistance * 2
end

function StairClimb:EstimateCost(ctx)
	return ctx.config.EdgeCost.Walk * 1.2
end

function StairClimb:EstimateSuccessRate(ctx)
	local dy = ctx.toNode.position.Y - ctx.fromNode.position.Y
	return math.clamp(1 - dy * 0.05, 0.7, 0.95)
end

function StairClimb:DebugInfo(ctx)
	return string.format("StairClimb ↑%.1f",
		ctx.toNode.position.Y - ctx.fromNode.position.Y)
end

return StairClimb
