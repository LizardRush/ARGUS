-- GoogleMapsRBX/AI/RouteScorer.lua
-- Assigns a normalized scalar score to a candidate path.
-- Lower score = better route.
-- ModuleScript: child of AI folder.

local RouteScorer = {}
RouteScorer.__index = RouteScorer

function RouteScorer.new(config)
	local self = setmetatable({}, RouteScorer)
	self._cfg = config
	return self
end

-- Returns a score table {total, distance, time, risk, complexity} (all 0..1+)
function RouteScorer:Score(path, straightLineDist)
	if not path or not path.nodes or #path.nodes < 2 then
		return { total = math.huge, distance = 1, time = 1, risk = 1, complexity = 1 }
	end

	local edges = path.edges
	local nodes = path.nodes
	local cfg   = self._cfg

	-- ── Distance component ─────────────────────────────────────────────────
	local totalLength = 0
	for i = 1, #nodes - 1 do
		totalLength = totalLength + (nodes[i+1].position - nodes[i].position).Magnitude
	end
	local slDist = straightLineDist or math.max(1,
		(nodes[#nodes].position - nodes[1].position).Magnitude
	)
	local normalizedDist = totalLength / math.max(1, slDist)

	-- ── Time component (weighted edge cost → estimated travel seconds) ────
	local totalTime = 0
	for _, edge in ipairs(edges) do
		local edgeDist = (edge.toPos - edge.fromPos).Magnitude
		local speed    = cfg.WalkSpeed
		if edge.edgeType == "Swim"  then speed = speed * 0.6
		elseif edge.edgeType == "ClimbLadder" or edge.edgeType == "ClimbTruss" then
			speed = speed * 0.7
		end
		totalTime = totalTime + edge.cost + edgeDist / math.max(1, speed)
	end
	-- Normalize against naive straight-line time at walk speed
	local naiveTime = slDist / cfg.WalkSpeed
	local normalizedTime = totalTime / math.max(1, naiveTime)

	-- ── Risk component ─────────────────────────────────────────────────────
	local riskScore = 0
	for _, node in ipairs(nodes) do
		if node.tags then
			if node.tags.hazard        then riskScore = riskScore + 5 end
			if node.tags.movingPlatform then riskScore = riskScore + 2 end
			if node.tags.water          then riskScore = riskScore + 1.5 end
		end
	end
	local normalizedRisk = math.min(1, riskScore / math.max(1, #nodes))

	-- ── Complexity component ───────────────────────────────────────────────
	local complexityScore = 0
	for _, edge in ipairs(edges) do
		if edge.edgeType ~= "Walk" and edge.edgeType ~= "Fall" then
			complexityScore = complexityScore + 0.5
		end
	end
	local normalizedComplexity = math.min(1, complexityScore / math.max(1, #edges))

	-- ── Weighted sum ──────────────────────────────────────────────────────
	local w  = cfg.RouteScoreWeights
	local total = w.Distance   * normalizedDist
		+ w.Time       * normalizedTime
		+ w.Risk       * normalizedRisk
		+ w.Complexity * normalizedComplexity

	return {
		total      = total,
		distance   = normalizedDist,
		time       = normalizedTime,
		risk       = normalizedRisk,
		complexity = normalizedComplexity,
		edgeCount  = #edges,
		nodeCount  = #nodes,
		rawLength  = totalLength,
		rawTime    = totalTime,
	}
end

-- Generate a human-readable rationale for why a route was selected.
function RouteScorer:Rationale(scoreData, bias)
	local parts = {}
	if scoreData.risk > 0.5 then
		parts[#parts+1] = "HIGH RISK route (avoid hazards/platforms)"
	end
	if scoreData.complexity > 0.5 then
		parts[#parts+1] = "complex movement required"
	end
	if scoreData.distance > 1.5 then
		parts[#parts+1] = "detour route (+". .
			string.format("%.0f%%", (scoreData.distance-1)*100) .. " longer)"
	end
	parts[#parts+1] = string.format("score=%.3f [bias:%s]", scoreData.total, bias or "balanced")
	return table.concat(parts, " | ")
end

return RouteScorer
