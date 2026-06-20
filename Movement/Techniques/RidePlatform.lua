-- GoogleMapsRBX/Movement/Techniques/RidePlatform.lua
-- Jump onto a predicted moving platform position, stand on it,
-- and jump off when the destination node is reachable.

local RidePlatform = {}
RidePlatform.__index = RidePlatform

function RidePlatform.new()
	return setmetatable({}, RidePlatform)
end

function RidePlatform:CanUse(ctx)
	return (ctx.edge.edgeType == "RidePlatform" or ctx.edge.edgeType == "Jump")
		and ctx.fromNode.tags.movingPlatform == nil  -- boarding from solid ground
		and ctx.edge.movingPart ~= nil
end

function RidePlatform:Execute(ctx)
	local humanoid = ctx.humanoid
	local root     = ctx.rootPart
	local edge     = ctx.edge
	local toPos    = ctx.toNode.position
	local cfg      = ctx.config
	local obs      = ctx.observationSystem
	local part     = edge.movingPart

	if not part or not part.Parent then return false end

	local trkId = obs._partMap and obs._partMap[part]
	if not trkId then return false end

	-- Phase 1: find optimal jump window
	local jt = obs:GetOptimalJumpTime(trkId, ctx.fromNode.position)
	if not jt or jt.confidence < 0.3 then
		-- No good window found; try a direct jump attempt
		jt = { waitTime = 0, landingPosition = part.Position, confidence = 0.3 }
	end

	if jt.waitTime > 0.05 then
		task.wait(jt.waitTime)
	end

	-- Phase 2: jump toward predicted landing position
	local landPos = jt.landingPosition
	humanoid.WalkSpeed = cfg.WalkSpeed
	humanoid:MoveTo(landPos)
	humanoid.Jump = true

	-- Wait to land on the platform (check that our base part == platform)
	local t0 = tick()
	local onPlatform = false
	while tick() - t0 < 4 do
		task.wait(0.1)
		if (root.Position - landPos).Magnitude < cfg.ReachDistance * 2 then
			onPlatform = true
			break
		end
	end

	if not onPlatform then return false end

	-- Phase 3: stay on platform until toPos is reachable
	t0 = tick()
	while tick() - t0 < 15 do
		task.wait(0.1)
		-- Keep re-targeting our position (stand still relative to world)
		humanoid:MoveTo(root.Position)

		local toNodeDist = (root.Position - toPos).Magnitude
		local horizDist  = Vector3.new(
			root.Position.X - toPos.X, 0, root.Position.Z - toPos.Z
		).Magnitude

		if horizDist < cfg.MaxJumpHorizontal * 0.7 then
			-- Jump off toward destination
			humanoid:MoveTo(toPos)
			humanoid.Jump = true
			task.wait(1.5)
			break
		end

		-- Anti-fall: if platform vanishes or moves us far away
		if (root.Position - part.Position).Magnitude > 10 then
			break
		end
	end

	return (root.Position - toPos).Magnitude < cfg.ReachDistance * 3
end

function RidePlatform:EstimateCost(ctx)
	return ctx.config.EdgeCost.RidePlatform
end

function RidePlatform:EstimateSuccessRate(ctx)
	local obs    = ctx.observationSystem
	local trkId  = obs._partMap and obs._partMap[ctx.edge.movingPart]
	if not trkId then return 0.4 end
	local model  = obs._tracks[trkId] and obs._tracks[trkId].model
	if model then return model.confidence * 0.85 end
	return 0.5
end

function RidePlatform:DebugInfo(ctx)
	local obs    = ctx.observationSystem
	local trkId  = obs._partMap and obs._partMap[ctx.edge.movingPart]
	local conf   = 0
	if trkId then
		local m = obs._tracks[trkId] and obs._tracks[trkId].model
		if m then conf = m.confidence end
	end
	return string.format("RidePlatform conf=%.2f", conf)
end

return RidePlatform
