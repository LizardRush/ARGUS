-- GoogleMapsRBX/Movement/Techniques/Walk.lua
-- Standard ground walking between adjacent nodes.

local Walk = {}
Walk.__index = Walk

function Walk.new()
	return setmetatable({}, Walk)
end

function Walk:CanUse(ctx)
	local e = ctx.edge
	return e.edgeType == "Walk"
		and not ctx.fromNode.tags.water
end

function Walk:Execute(ctx)
	local humanoid = ctx.humanoid
	local target   = ctx.toNode.position

	-- Apply speed variation if humanization active
	local cfg   = ctx.config
	local speed = cfg.WalkSpeed
	if ctx.humanize then
		local var = cfg.SpeedVariation
		speed = speed * (1 + (math.random() * 2 - 1) * var)
	end
	humanoid.WalkSpeed = speed

	humanoid:MoveTo(target)

	local arrived, timeout = false, false
	local conn = humanoid.MoveToFinished:Connect(function(reached)
		arrived = reached
		timeout = not reached
	end)

	-- Watchdog: MoveTo times out after 8 s by default in Roblox.
	-- We'll wait up to 10 s, then check distance.
	local t0  = tick()
	local root = ctx.rootPart
	while not arrived and not timeout do
		task.wait(0.05)
		local dist = (root.Position - target).Magnitude
		if dist < ctx.config.ReachDistance then
			arrived = true
			break
		end
		if tick() - t0 > 10 then break end
	end

	conn:Disconnect()
	return arrived
end

function Walk:EstimateCost(ctx)
	return ctx.config.EdgeCost.Walk
end

function Walk:EstimateSuccessRate(ctx)
	if ctx.toNode.tags.hazard then return 0.3 end
	if ctx.toNode.tags.nearWall then return 0.85 end
	return 0.98
end

function Walk:DebugInfo(ctx)
	return string.format("Walk → (%.1f, %.1f, %.1f)",
		ctx.toNode.position.X,
		ctx.toNode.position.Y,
		ctx.toNode.position.Z)
end

return Walk
