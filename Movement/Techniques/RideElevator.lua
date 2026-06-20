-- GoogleMapsRBX/Movement/Techniques/RideElevator.lua
-- Board an elevator platform, wait for it to carry the character
-- to the destination floor, then step off.

local RideElevator = {}
RideElevator.__index = RideElevator

function RideElevator.new()
	return setmetatable({}, RideElevator)
end

function RideElevator:CanUse(ctx)
	return ctx.edge.edgeType == "RideElevator"
		and ctx.edge.movingPart ~= nil
end

function RideElevator:Execute(ctx)
	local humanoid = ctx.humanoid
	local root     = ctx.rootPart
	local edge     = ctx.edge
	local toPos    = ctx.toNode.position
	local cfg      = ctx.config
	local obs      = ctx.observationSystem
	local part     = edge.movingPart

	if not part or not part.Parent then return false end

	-- Get track id
	local trkId = obs._partMap and obs._partMap[part]

	-- Phase 1: wait for elevator to reach our level
	local fromY  = ctx.fromNode.position.Y
	local waitT  = 0
	if trkId then
		local jt = obs:GetOptimalJumpTime(trkId, ctx.fromNode.position)
		if jt then waitT = jt.waitTime end
	end

	if waitT > 0.1 then
		task.wait(waitT)
	end

	-- Phase 2: walk onto the elevator
	humanoid.WalkSpeed = cfg.WalkSpeed
	local elevCenter = part.Position
	humanoid:MoveTo(Vector3.new(elevCenter.X, root.Position.Y, elevCenter.Z))
	task.wait(1.5)

	-- Phase 3: stand still and ride (set WalkTo to current position)
	-- Poll until the part reaches destination Y ±2
	local t0 = tick()
	while math.abs(part.Position.Y - toPos.Y) > 2.5 do
		humanoid:MoveTo(root.Position)  -- stay still
		task.wait(0.1)
		if tick() - t0 > 30 then return false end
	end

	-- Phase 4: step off
	humanoid:MoveTo(toPos)
	task.wait(2)

	return (root.Position - toPos).Magnitude < cfg.ReachDistance * 3
end

function RideElevator:EstimateCost(ctx)
	return ctx.config.EdgeCost.RideElevator
end

function RideElevator:EstimateSuccessRate(ctx)
	local obs    = ctx.observationSystem
	local part   = ctx.edge.movingPart
	if not part then return 0.5 end
	local trkId  = obs._partMap and obs._partMap[part]
	if not trkId then return 0.6 end
	local model  = obs._tracks[trkId] and obs._tracks[trkId].model
	if model then return model.confidence * 0.9 end
	return 0.6
end

function RideElevator:DebugInfo(ctx)
	return string.format("RideElevator ↕%.1f",
		ctx.toNode.position.Y - ctx.fromNode.position.Y)
end

return RideElevator
