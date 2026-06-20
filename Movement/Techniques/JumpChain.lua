-- GoogleMapsRBX/Movement/Techniques/JumpChain.lua
-- Bunny-hop style: chain consecutive Jump edges without a landing pause
-- for obby-style sequences requiring continuous momentum.

local JumpChain = {}
JumpChain.__index = JumpChain

function JumpChain.new()
	return setmetatable({}, JumpChain)
end

-- ctx.nextEdge must be populated by MovementController.
function JumpChain:CanUse(ctx)
	if ctx.edge.edgeType ~= "Jump" then return false end
	return ctx.nextEdge ~= nil and ctx.nextEdge.edgeType == "Jump"
end

function JumpChain:Execute(ctx)
	local humanoid = ctx.humanoid
	local root     = ctx.rootPart
	local toPos    = ctx.toNode.position
	local cfg      = ctx.config

	humanoid.WalkSpeed = cfg.WalkSpeed * 1.1
	humanoid:MoveTo(toPos)
	humanoid.Jump = true

	local t0      = tick()
	local arrived = false
	local conn    = humanoid.MoveToFinished:Connect(function(reached)
		arrived = reached
	end)

	-- Watch for landing (velocity Y becoming negative then near-zero)
	local peakReached = false
	while not arrived do
		task.wait(0.03)

		local velY = root.AssemblyLinearVelocity and root.AssemblyLinearVelocity.Y or 0
		if velY < -2 then peakReached = true end

		-- Re-jump as soon as we start descending (chain jump)
		if peakReached and velY > -5 and velY < 0 then
			humanoid.Jump = true
		end

		if (root.Position - toPos).Magnitude < cfg.ReachDistance * 1.5 then
			arrived = true
			break
		end

		if tick() - t0 > 8 then break end
	end

	humanoid.WalkSpeed = cfg.WalkSpeed
	conn:Disconnect()
	return arrived or (root.Position - toPos).Magnitude < cfg.ReachDistance * 2.5
end

function JumpChain:EstimateCost(ctx)
	return ctx.config.EdgeCost.Jump * 0.85  -- cheaper than two separate jumps
end

function JumpChain:EstimateSuccessRate(ctx)
	local diff = ctx.toNode.position - ctx.fromNode.position
	local h    = math.abs(diff.Y)
	local cfg  = ctx.config
	return math.clamp(0.88 - (h / cfg.MaxJumpHeight) * 0.3, 0.35, 0.88)
end

function JumpChain:DebugInfo(ctx)
	return string.format("JumpChain (next:%s)",
		ctx.nextEdge and ctx.nextEdge.edgeType or "?")
end

return JumpChain
