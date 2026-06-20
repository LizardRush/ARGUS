-- GoogleMapsRBX/Movement/Techniques/SafeFall.lua
-- Walk to an edge and fall to a lower node within the safe fall distance.

local SafeFall = {}
SafeFall.__index = SafeFall

function SafeFall.new()
	return setmetatable({}, SafeFall)
end

function SafeFall:CanUse(ctx)
	local e    = ctx.edge
	local diff = ctx.toNode.position.Y - ctx.fromNode.position.Y
	return e.edgeType == "Fall"
		and diff <= 0
		and math.abs(diff) <= ctx.config.MaxFallDistance
end

function SafeFall:Execute(ctx)
	local humanoid = ctx.humanoid
	local root     = ctx.rootPart
	local toPos    = ctx.toNode.position
	local cfg      = ctx.config

	humanoid.WalkSpeed = cfg.WalkSpeed
	humanoid:MoveTo(toPos)

	local arrived = false
	local t0      = tick()
	local conn    = humanoid.MoveToFinished:Connect(function(reached)
		arrived = reached
	end)

	while not arrived do
		task.wait(0.05)
		if (root.Position - toPos).Magnitude < cfg.ReachDistance * 2 then
			arrived = true
			break
		end
		-- If we've dropped to near target Y, consider it a success
		if math.abs(root.Position.Y - toPos.Y) < 2 then
			arrived = true
			break
		end
		if tick() - t0 > 8 then break end
	end

	conn:Disconnect()
	return arrived or (root.Position - toPos).Magnitude < cfg.ReachDistance * 3
end

function SafeFall:EstimateCost(ctx)
	return ctx.config.EdgeCost.Fall
end

function SafeFall:EstimateSuccessRate(ctx)
	local drop = math.abs(ctx.toNode.position.Y - ctx.fromNode.position.Y)
	-- Success rate decreases with fall height
	return math.clamp(1 - (drop / ctx.config.MaxFallDistance) * 0.4, 0.5, 0.97)
end

function SafeFall:DebugInfo(ctx)
	return string.format("SafeFall ↓%.1f",
		math.abs(ctx.toNode.position.Y - ctx.fromNode.position.Y))
end

return SafeFall
