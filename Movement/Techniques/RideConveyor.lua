-- GoogleMapsRBX/Movement/Techniques/RideConveyor.lua
-- Step onto a conveyor and let its BodyVelocity carry the character.
-- We walk in the conveyor direction to stay aligned.

local RideConveyor = {}
RideConveyor.__index = RideConveyor

function RideConveyor.new()
	return setmetatable({}, RideConveyor)
end

function RideConveyor:CanUse(ctx)
	return ctx.edge.edgeType == "RideConveyor"
		and ctx.fromNode.tags.conveyor
		and ctx.edge.movingPart ~= nil
end

function RideConveyor:Execute(ctx)
	local humanoid = ctx.humanoid
	local root     = ctx.rootPart
	local toPos    = ctx.toNode.position
	local part     = ctx.edge.movingPart
	local cfg      = ctx.config

	if not part or not part.Parent then return false end

	humanoid.WalkSpeed = cfg.WalkSpeed * 0.5  -- let conveyor do the work
	humanoid:MoveTo(toPos)

	local arrived = false
	local t0      = tick()
	local conn    = humanoid.MoveToFinished:Connect(function(reached)
		arrived = reached
	end)

	while not arrived do
		task.wait(0.1)
		if (root.Position - toPos).Magnitude < cfg.ReachDistance * 1.5 then
			arrived = true
			break
		end
		if tick() - t0 > 20 then break end
	end

	humanoid.WalkSpeed = cfg.WalkSpeed
	conn:Disconnect()
	return arrived or (root.Position - toPos).Magnitude < cfg.ReachDistance * 2
end

function RideConveyor:EstimateCost(ctx)
	return ctx.config.EdgeCost.RideConveyor
end

function RideConveyor:EstimateSuccessRate(_ctx)
	return 0.88
end

function RideConveyor:DebugInfo(ctx)
	return string.format("RideConveyor → (%.1f, %.1f)",
		ctx.toNode.position.X, ctx.toNode.position.Z)
end

return RideConveyor
