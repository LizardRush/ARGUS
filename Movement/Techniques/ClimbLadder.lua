-- GoogleMapsRBX/Movement/Techniques/ClimbLadder.lua
-- Navigate a ladder part (tagged "Ladder"). Roblox does not auto-climb
-- non-truss ladders, so we walk the humanoid toward the ladder top
-- while monitoring vertical progress.

local ClimbLadder = {}
ClimbLadder.__index = ClimbLadder

function ClimbLadder.new()
	return setmetatable({}, ClimbLadder)
end

function ClimbLadder:CanUse(ctx)
	return ctx.edge.edgeType == "ClimbLadder"
		and (ctx.fromNode.tags.ladder or ctx.toNode.tags.ladder)
end

function ClimbLadder:Execute(ctx)
	local humanoid = ctx.humanoid
	local root     = ctx.rootPart
	local toPos    = ctx.toNode.position
	local cfg      = ctx.config

	humanoid.WalkSpeed = cfg.WalkSpeed * 0.7
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
		if tick() - t0 > 12 then break end
	end

	conn:Disconnect()
	return (root.Position - toPos).Magnitude < cfg.ReachDistance * 2
end

function ClimbLadder:EstimateCost(ctx)
	return ctx.config.EdgeCost.ClimbLadder
end

function ClimbLadder:EstimateSuccessRate(_ctx)
	return 0.85
end

function ClimbLadder:DebugInfo(ctx)
	return string.format("ClimbLadder ↑%.1f", ctx.toNode.position.Y - ctx.fromNode.position.Y)
end

return ClimbLadder
