-- GoogleMapsRBX/Movement/Techniques/ClimbTruss.lua
-- Navigate a TrussPart. Roblox auto-climbs when the humanoid walks
-- into a TrussPart, so we simply drive MoveTo toward the exit position
-- while the engine handles the climbing physics.

local ClimbTruss = {}
ClimbTruss.__index = ClimbTruss

function ClimbTruss.new()
	return setmetatable({}, ClimbTruss)
end

function ClimbTruss:CanUse(ctx)
	return ctx.edge.edgeType == "ClimbTruss"
		and (ctx.fromNode.tags.truss or ctx.toNode.tags.truss)
end

function ClimbTruss:Execute(ctx)
	local humanoid = ctx.humanoid
	local root     = ctx.rootPart
	local toPos    = ctx.toNode.position
	local cfg      = ctx.config

	humanoid.WalkSpeed = cfg.WalkSpeed * 0.8
	humanoid:MoveTo(toPos)

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
		if tick() - t0 > 15 then break end
	end

	conn:Disconnect()
	return arrived or (root.Position - toPos).Magnitude < cfg.ReachDistance * 2
end

function ClimbTruss:EstimateCost(ctx)
	return ctx.config.EdgeCost.ClimbTruss
end

function ClimbTruss:EstimateSuccessRate(_ctx)
	return 0.9
end

function ClimbTruss:DebugInfo(ctx)
	return string.format("ClimbTruss ↕%.1f", ctx.toNode.position.Y - ctx.fromNode.position.Y)
end

return ClimbTruss
