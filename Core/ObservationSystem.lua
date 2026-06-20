-- GoogleMapsRBX/Core/ObservationSystem.lua
-- Tracks moving world objects and builds motion predictions.
-- Fits linear, oscillating, and circular models to position history.
-- ModuleScript: child of Core folder.

local RunService = game:GetService("RunService")

local ObservationSystem = {}
ObservationSystem.__index = ObservationSystem

-- ── Constructor ───────────────────────────────────────────────────────────────

function ObservationSystem.new(config)
	local self = setmetatable({}, ObservationSystem)
	self._config   = config
	self._tracks   = {}        -- [trackId] = TrackData
	self._nextId   = 1
	self._partMap  = {}        -- [part] = trackId
	self._conn     = nil
	self.onModelChanged = nil  -- callback(trackId)
	self:_startHeartbeat()
	return self
end

-- ── Public API ────────────────────────────────────────────────────────────────

function ObservationSystem:Track(part)
	if self._partMap[part] then
		return self._partMap[part]
	end
	local id = self._nextId
	self._nextId = self._nextId + 1
	local track = {
		id        = id,
		part      = part,
		buffer    = {},          -- circular buffer of {t, pos, vel}
		head      = 0,
		count     = 0,
		model     = nil,         -- fitted model
		fitTimer  = 0,
	}
	self._tracks[id]    = track
	self._partMap[part] = id
	return id
end

function ObservationSystem:Untrack(trackId)
	local track = self._tracks[trackId]
	if track then
		self._partMap[track.part] = nil
		self._tracks[trackId]     = nil
	end
end

function ObservationSystem:GetTrackedObjects()
	local out = {}
	for id, track in pairs(self._tracks) do
		out[#out+1] = {
			id         = id,
			part       = track.part,
			model      = track.model,
			sampleCount = track.count,
		}
	end
	return out
end

-- Predict position of tracked object `futureTime` seconds from now.
function ObservationSystem:Predict(trackId, futureTime)
	local track = self._tracks[trackId]
	if not track or not track.model then
		if track and track.part and track.part.Parent then
			return track.part.Position
		end
		return nil
	end
	return self:_applyModel(track.model, futureTime)
end

-- Returns the best time window to jump onto a moving platform.
-- Returns {waitTime, landingPosition, confidence} or nil.
function ObservationSystem:GetOptimalJumpTime(trackId, fromNodePos)
	local track = self._tracks[trackId]
	if not track then return nil end
	local maxRange = self._config.MaxJumpHorizontal
	local horizon  = self._config.PredictionHorizon
	local step     = 0.1
	local best     = nil
	local t        = 0
	while t <= horizon do
		local predicted = self:Predict(trackId, t)
		if predicted then
			local horiz = Vector3.new(
				predicted.X - fromNodePos.X, 0, predicted.Z - fromNodePos.Z
			).Magnitude
			local vert  = predicted.Y - fromNodePos.Y
			if horiz <= maxRange and vert >= -2 and vert <= self._config.MaxJumpHeight then
				local conf = track.model and track.model.confidence or 0.5
				if not best then
					best = { waitTime = t, landingPosition = predicted, confidence = conf }
				end
				break
			end
		end
		t = t + step
	end
	return best
end

-- ── Private: Heartbeat ────────────────────────────────────────────────────────

function ObservationSystem:_startHeartbeat()
	self._conn = RunService.Heartbeat:Connect(function(dt)
		local now = tick()
		for id, track in pairs(self._tracks) do
			if track.part and track.part.Parent then
				self:_sample(track, now)
				track.fitTimer = track.fitTimer + dt
				if track.fitTimer >= self._config.ObsFitInterval then
					track.fitTimer = 0
					local prevModel = track.model
					track.model = self:_fitModel(track)
					if self.onModelChanged then
						self.onModelChanged(id)
					end
				end
			else
				self:Untrack(id)
			end
		end
	end)
end

function ObservationSystem:Destroy()
	if self._conn then self._conn:Disconnect() end
end

-- ── Private: Circular buffer ──────────────────────────────────────────────────

function ObservationSystem:_sample(track, now)
	local buf  = track.buffer
	local size = self._config.ObsBufferSize
	local pos  = track.part.Position
	local vel  = track.part.AssemblyLinearVelocity or Vector3.zero
	local head = (track.head % size) + 1
	buf[head]  = { t = now, pos = pos, vel = vel }
	track.head = head
	if track.count < size then track.count = track.count + 1 end
end

function ObservationSystem:_getSamples(track)
	local buf  = track.buffer
	local size = self._config.ObsBufferSize
	local n    = track.count
	local out  = {}
	for i = 1, n do
		local idx = ((track.head - i - 1) % size) + 1  -- newest first → oldest last
		if buf[idx] then
			out[n - i + 1] = buf[idx]
		end
	end
	return out
end

-- ── Private: Model fitting ────────────────────────────────────────────────────

function ObservationSystem:_fitModel(track)
	local samples = self:_getSamples(track)
	if #samples < 4 then return nil end

	local linErr  = self:_fitLinear(samples)
	local oscErr  = self:_fitOscillating(samples)

	local model
	if linErr.error <= oscErr.error then
		model = linErr
		model.type = "Linear"
	else
		model = oscErr
		model.type = "Oscillating"
	end

	-- Confidence: 1.0 = perfect fit, decreases with relative error
	local relErr = model.error / (math.max(1, #samples))
	model.confidence = math.max(0, 1 - relErr * 0.1)
	return model
end

function ObservationSystem:_fitLinear(samples)
	-- Fit pos(t) = p0 + v * (t - t0) separately per axis using least squares.
	local n = #samples
	local t0 = samples[1].t
	local sumT, sumT2 = 0, 0
	local sumPx, sumPy, sumPz = 0, 0, 0
	local sumTPx, sumTPy, sumTPz = 0, 0, 0
	for _, s in ipairs(samples) do
		local dt = s.t - t0
		sumT   = sumT   + dt
		sumT2  = sumT2  + dt * dt
		sumPx  = sumPx  + s.pos.X
		sumPy  = sumPy  + s.pos.Y
		sumPz  = sumPz  + s.pos.Z
		sumTPx = sumTPx + dt * s.pos.X
		sumTPy = sumTPy + dt * s.pos.Y
		sumTPz = sumTPz + dt * s.pos.Z
	end
	local denom = n * sumT2 - sumT * sumT
	local vx, vy, vz, px, py, pz
	if math.abs(denom) < 1e-9 then
		px, py, pz = sumPx / n, sumPy / n, sumPz / n
		vx, vy, vz = 0, 0, 0
	else
		vx = (n * sumTPx - sumT * sumPx) / denom
		vy = (n * sumTPy - sumT * sumPy) / denom
		vz = (n * sumTPz - sumT * sumPz) / denom
		px = (sumPx - vx * sumT) / n
		py = (sumPy - vy * sumT) / n
		pz = (sumPz - vz * sumT) / n
	end
	local err = 0
	for _, s in ipairs(samples) do
		local dt  = s.t - t0
		local ex  = px + vx * dt - s.pos.X
		local ey  = py + vy * dt - s.pos.Y
		local ez  = pz + vz * dt - s.pos.Z
		err = err + ex*ex + ey*ey + ez*ez
	end
	return {
		p0    = Vector3.new(px, py, pz),
		vel   = Vector3.new(vx, vy, vz),
		t0    = t0,
		error = err,
	}
end

function ObservationSystem:_fitOscillating(samples)
	-- Simple oscillation model per axis: A*sin(w*t + phi) + c
	-- Estimate w from zero-crossing frequency of (pos - mean).
	local n = #samples
	local t0 = samples[1].t
	-- Compute means
	local mx, my, mz = 0, 0, 0
	for _, s in ipairs(samples) do
		mx = mx + s.pos.X; my = my + s.pos.Y; mz = mz + s.pos.Z
	end
	mx, my, mz = mx/n, my/n, mz/n

	-- Find omega via zero-crossings on the axis with highest variance
	local varX, varY, varZ = 0, 0, 0
	for _, s in ipairs(samples) do
		varX = varX + (s.pos.X - mx)^2
		varY = varY + (s.pos.Y - my)^2
		varZ = varZ + (s.pos.Z - mz)^2
	end
	local axis = "X"
	if varY >= varX and varY >= varZ then axis = "Y"
	elseif varZ >= varX and varZ >= varY then axis = "Z" end
	local m = axis == "X" and mx or (axis == "Y" and my or mz)

	local crossings = 0
	local lastSign  = 0
	for _, s in ipairs(samples) do
		local v = (axis == "X" and s.pos.X or (axis == "Y" and s.pos.Y or s.pos.Z)) - m
		local sg = v >= 0 and 1 or -1
		if lastSign ~= 0 and sg ~= lastSign then crossings = crossings + 1 end
		lastSign = sg
	end
	local duration = samples[n].t - t0
	local omega = crossings > 1 and (math.pi * crossings / duration) or (2 * math.pi / 4)
	omega = math.max(0.1, omega)

	-- Amplitudes: max deviation from mean per axis
	local Ax, Ay, Az = 0, 0, 0
	for _, s in ipairs(samples) do
		Ax = math.max(Ax, math.abs(s.pos.X - mx))
		Ay = math.max(Ay, math.abs(s.pos.Y - my))
		Az = math.max(Az, math.abs(s.pos.Z - mz))
	end

	local err = 0
	for _, s in ipairs(samples) do
		local dt = s.t - t0
		local sinV = math.sin(omega * dt)
		local ex = mx + Ax * sinV - s.pos.X
		local ey = my + Ay * sinV - s.pos.Y
		local ez = mz + Az * sinV - s.pos.Z
		err = err + ex*ex + ey*ey + ez*ez
	end
	return {
		center = Vector3.new(mx, my, mz),
		amp    = Vector3.new(Ax, Ay, Az),
		omega  = omega,
		t0     = t0,
		error  = err,
	}
end

function ObservationSystem:_applyModel(model, futureTime)
	local now = tick()
	if model.type == "Linear" then
		local dt = (now - model.t0) + futureTime
		return model.p0 + model.vel * dt
	elseif model.type == "Oscillating" then
		local dt  = (now - model.t0) + futureTime
		local sinV = math.sin(model.omega * dt)
		return model.center + model.amp * sinV
	end
	return nil
end

return ObservationSystem
