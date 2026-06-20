-- GoogleMapsRBX/Movement/Techniques/Swim.lua
-- Navigate through water terrain. Roblox humanoids swim automatically
-- when submerged, so standard MoveTo works; we just flag it separately
-- so the AI can cost it correctly.

local Swim = {}
Swim.__index = Swim

function Swim.new()
	return setmetatable({}, Swim)
end

function Swim:CanUse(ctx)
	return ctx.edge.edgeType == "Swim"
		and ctx.fromNode.tags.water
end

function Swim:Execute(ctx)
	local humanoid = ctx.humanoid
	local root     = ctx.rootPart
	local toPos    = ctx.toNode.position
	local cfg      = ctx.config

	-- Slow down in water
	humanoid.WalkSpeed = cfg.WalkSpeed * 0.6
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
		if tick() - t0 > 20 then break end
	end

	-- Restore speed
	humanoid.WalkSpeed = cfg.WalkSpeed
	conn:Disconnect()
	return arrived or (root.Position - toPos).Magnitude < cfg.ReachDistance * 2
end

function Swim:EstimateCost(ctx)
	return ctx.config.EdgeCost.Swim
end

function Swim:EstimateSuccessRate(_ctx)
	return 0.88
end

function Swim:DebugInfo(ctx)
	return string.format("Swim → (%.1f, %.1f, %.1f)",
		ctx.toNode.position.X, ctx.toNode.position.Y, ctx.toNode.position.Z)
end

return Swim
