-- GoogleMapsRBX/Movement/Techniques/Jump.lua
-- Jump from a lower node to a higher one.

local Jump = {}
Jump.__index = Jump

function Jump.new()
	return setmetatable({}, Jump)
end

function Jump:CanUse(ctx)
	local e    = ctx.edge
	local diff = ctx.toNode.position.Y - ctx.fromNode.position.Y
	return e.edgeType == "Jump"
		and diff >= 0
		and diff <= ctx.config.MaxJumpHeight
end

function Jump:Execute(ctx)
	local humanoid = ctx.humanoid
	local root     = ctx.rootPart
	local fromPos  = ctx.fromNode.position
	local toPos    = ctx.toNode.position
	local cfg      = ctx.config

	humanoid.WalkSpeed = cfg.WalkSpeed

	-- Walk toward a point 1 stud in front of the destination on the arc approach.
	local horizDir = Vector3.new(toPos.X - fromPos.X, 0, toPos.Z - fromPos.Z)
	if horizDir.Magnitude > 0.01 then
		horizDir = horizDir.Unit
	end

	-- Move toward target
	humanoid:MoveTo(toPos)

	-- Trigger jump when close enough to lift-off point
	local startY   = root.Position.Y
	local jumped   = false
	local arrived  = false
	local t0       = tick()

	local conn = humanoid.MoveToFinished:Connect(function(reached)
		arrived = reached
	end)

	while not arrived do
		task.wait(0.03)

		local dist = (root.Position - toPos).Magnitude
		local horizDist = Vector3.new(
			root.Position.X - fromPos.X, 0, root.Position.Z - fromPos.Z
		).Magnitude
		local totalHoriz = Vector3.new(
			toPos.X - fromPos.X, 0, toPos.Z - fromPos.Z
		).Magnitude

		-- Jump when we've traveled 40% of horizontal distance
		if not jumped and horizDist >= totalHoriz * 0.4 then
			humanoid.Jump = true
			jumped = true
		end

		if dist < cfg.ReachDistance then
			arrived = true
			break
		end

		-- Timeout
		if tick() - t0 > 8 then break end

		-- If we jumped and are now descending back near fromPos, the jump failed
		if jumped and root.Position.Y < startY - 1 then
			break
		end
	end

	conn:Disconnect()

	-- Check we actually reached the target node's Y level
	local finalDist = (root.Position - toPos).Magnitude
	return finalDist < cfg.ReachDistance * 2.5
end

function Jump:EstimateCost(ctx)
	return ctx.config.EdgeCost.Jump
end

function Jump:EstimateSuccessRate(ctx)
	local diff = ctx.toNode.position - ctx.fromNode.position
	local h    = math.abs(diff.Y)
	local horz = Vector3.new(diff.X, 0, diff.Z).Magnitude
	local cfg  = ctx.config
	-- Success drops off with height and horizontal distance
	local hFactor = 1 - (h / cfg.MaxJumpHeight) * 0.4
	local dFactor = 1 - (horz / cfg.MaxJumpHorizontal) * 0.3
	return math.clamp(hFactor * dFactor * 0.9, 0.1, 0.95)
end

function Jump:DebugInfo(ctx)
	local diff = ctx.toNode.position - ctx.fromNode.position
	return string.format("Jump ↑%.1f →%.1f",
		diff.Y,
		Vector3.new(diff.X, 0, diff.Z).Magnitude)
end

return Jump
