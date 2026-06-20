-- GoogleMapsRBX/Movement/Techniques/GapCross.lua
-- High-speed jump across a gap. Approaches at full speed to maintain
-- momentum, then jumps at the lip for maximum horizontal distance.

local GapCross = {}
GapCross.__index = GapCross

function GapCross.new()
	return setmetatable({}, GapCross)
end

function GapCross:CanUse(ctx)
	local e = ctx.edge
	return e.edgeType == "GapCross"
		and ctx.fromNode.tags.hasGap
end

function GapCross:Execute(ctx)
	local humanoid = ctx.humanoid
	local root     = ctx.rootPart
	local fromPos  = ctx.fromNode.position
	local toPos    = ctx.toNode.position
	local cfg      = ctx.config

	-- Approach at full speed for momentum
	humanoid.WalkSpeed = cfg.WalkSpeed * 1.15
	humanoid:MoveTo(toPos)

	local jumped   = false
	local arrived  = false
	local t0       = tick()

	local conn = humanoid.MoveToFinished:Connect(function(reached)
		arrived = reached
	end)

	while not arrived do
		task.wait(0.03)

		local horizTraveled = Vector3.new(
			root.Position.X - fromPos.X, 0, root.Position.Z - fromPos.Z
		).Magnitude
		local totalHoriz = Vector3.new(
			toPos.X - fromPos.X, 0, toPos.Z - fromPos.Z
		).Magnitude

		-- Jump at the lip (70% of horizontal distance reached)
		if not jumped and horizTraveled >= totalHoriz * 0.7 then
			humanoid.Jump = true
			jumped = true
		end

		if (root.Position - toPos).Magnitude < cfg.ReachDistance * 1.5 then
			arrived = true
			break
		end

		if tick() - t0 > 10 then break end
	end

	humanoid.WalkSpeed = cfg.WalkSpeed
	conn:Disconnect()
	return arrived or (root.Position - toPos).Magnitude < cfg.ReachDistance * 2.5
end

function GapCross:EstimateCost(ctx)
	return ctx.config.EdgeCost.GapCross
end

function GapCross:EstimateSuccessRate(ctx)
	local diff = ctx.toNode.position - ctx.fromNode.position
	local horz = Vector3.new(diff.X, 0, diff.Z).Magnitude
	local maxH = ctx.config.MaxJumpHorizontal
	return math.clamp(1 - (horz / maxH) * 0.5, 0.3, 0.9)
end

function GapCross:DebugInfo(ctx)
	local diff = ctx.toNode.position - ctx.fromNode.position
	return string.format("GapCross →%.1f ↕%.1f",
		Vector3.new(diff.X, 0, diff.Z).Magnitude, diff.Y)
end

return GapCross
