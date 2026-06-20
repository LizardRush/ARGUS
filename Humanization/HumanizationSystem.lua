-- GoogleMapsRBX/Humanization/HumanizationSystem.lua
-- Cosmetic layer that makes automated navigation look human.
-- Does NOT affect pathfinding or movement logic.
-- ModuleScript: child of Humanization folder.

local RunService    = game:GetService("RunService")
local TweenService  = game:GetService("TweenService")
local Players       = game:GetService("Players")

local HumanizationSystem = {}
HumanizationSystem.__index = HumanizationSystem

-- ── Constructor ───────────────────────────────────────────────────────────────

function HumanizationSystem.new(config, movementController)
	local self = setmetatable({}, HumanizationSystem)
	self._cfg        = config
	self._ctrl       = movementController
	self._enabled    = true
	self._camera     = true
	self._headTurns  = true
	self._idlePauses = true

	self._idleTimer   = math.random(5, 15)
	self._headTimer   = 0
	self._isTurning   = false

	self._conn        = nil
	self._currentPath = nil  -- flat Vector3 array
	return self
end

-- ── Public API ────────────────────────────────────────────────────────────────

function HumanizationSystem:SetEnabled(v)  self._enabled    = v end
function HumanizationSystem:SetCamera(v)   self._camera     = v end
function HumanizationSystem:SetHeadTurns(v) self._headTurns = v end
function HumanizationSystem:SetIdlePauses(v) self._idlePauses = v end

function HumanizationSystem:SetPath(smoothedPositions)
	self._currentPath = smoothedPositions
end

function HumanizationSystem:Start()
	self:Stop()
	self._conn = RunService.Heartbeat:Connect(function(dt)
		if self._enabled then
			self:_tick(dt)
		end
	end)
end

function HumanizationSystem:Stop()
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
end

-- ── Private tick ─────────────────────────────────────────────────────────────

function HumanizationSystem:_tick(dt)
	local character = Players.LocalPlayer.Character
	if not character then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local cam  = workspace.CurrentCamera

	-- ── Camera follow ──────────────────────────────────────────────────────
	if self._camera and self._currentPath and self._ctrl:IsActive() then
		local wpIdx   = math.min(
			self._ctrl:GetWaypointIndex() + 2,
			self._ctrl:GetWaypointCount()
		)
		local lookAt  = self._currentPath[wpIdx] or root.Position
		local camPos  = cam.CFrame.Position
		local desiredCF = CFrame.new(camPos, lookAt + Vector3.new(0, 1, 0))
		cam.CFrame     = cam.CFrame:Lerp(desiredCF, self._cfg.CameraLag)
	end

	-- ── Idle pauses ────────────────────────────────────────────────────────
	if self._idlePauses and self._ctrl:IsActive() then
		self._idleTimer = self._idleTimer - dt
		if self._idleTimer <= 0 then
			self._idleTimer = math.random(5, 15)
			-- Random pause
			local chance = math.random()
			if chance < self._cfg.PauseProbability * 10 then
				self._ctrl:Pause()
				task.spawn(function()
					local pauseDur = math.random() * self._cfg.PauseMaxDuration
					task.wait(pauseDur)
					self._ctrl:Resume()
				end)
			end
		end
	end

	-- ── Random head turns ──────────────────────────────────────────────────
	if self._headTurns and not self._isTurning then
		self._headTimer = self._headTimer + dt
		if self._headTimer >= 0.05 then
			self._headTimer = 0
			if math.random() < self._cfg.HeadTurnProbability then
				self:_doHeadTurn(character)
			end
		end
	end
end

function HumanizationSystem:_doHeadTurn(character)
	local head = character:FindFirstChild("Head")
	if not head then return end

	self._isTurning = true

	-- Pick a random nearby point
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then self._isTurning = false return end

	local angle   = math.random() * 2 * math.pi
	local dist    = 5 + math.random() * 8
	local lookPt  = root.Position + Vector3.new(
		math.cos(angle) * dist, math.random(-1, 1), math.sin(angle) * dist
	)

	local targetCF  = CFrame.new(head.Position, lookPt)
	local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Sine)
	local tween     = TweenService:Create(head, tweenInfo, { CFrame = targetCF })
	tween:Play()

	local duration = 0.5 + math.random() * 1.0
	task.delay(duration + 0.3, function()
		self._isTurning = false
	end)
end

return HumanizationSystem
