local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local inputsModule = require(ServerStorage:WaitForChild("InputsModule"))
local abilitiesModule = require(ServerStorage:WaitForChild("AbilitiesModule"))
local playersModule = require(ServerStorage:WaitForChild("PlayersModule"))
local effectsModule = require(ServerStorage:WaitForChild("EffectsModule"))
local soundsModule = require(ServerStorage:WaitForChild("SoundsModule"))

local highlightEvent = ReplicatedStorage:WaitForChild("HighlightEvent")
local ballTemplate = ServerStorage:WaitForChild("Ball")

local bot1 = workspace:WaitForChild("Bot1")
local bot2 = workspace:WaitForChild("Bot2")
local bots = {bot1, bot2}

local activeBalls = {}

local function removeHighlight(target)
	local character = target.Parent
	if not character then return end

	for _, child in pairs(character:GetChildren()) do
		if child:IsA("Highlight") then
			child:Destroy()
		end
	end
end

local function addHighlight(target)
	local character = target.Parent
	if not character then return end

	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.new(1, 0, 0)
	highlight.OutlineTransparency = 1
	highlight.Parent = character
end

local module = {}
module.__index = module

function module.new(params)
	local self = setmetatable({}, module)
	params = params or {}

	local ball = ballTemplate:Clone()
	ball.Parent = workspace

	self.ball = ball
	self.target = nil
	self.connection = nil 

	self.currentValues = {
		velocity        = params.velocity or Vector3.zero,
		acceleration    = params.acceleration or 0.002,
		jerk            = params.jerk or 0.00005,
		maxDist         = params.maxDist or 100,
		decayPower      = params.decayPower or 0.16,
		dragCoef        = params.dragCoef or 0.02,
		dragPower       = params.dragPower or 1.6,
		deflectStrength = params.deflectStrength or 0.005,
		range           = params.range or 5,
	}

	self.tempValues = {
		velocity        = nil,
		acceleration    = nil,
		jerk            = nil,
		maxDist         = nil,
		decayPower      = nil,
		dragCoef        = nil,
		dragPower       = nil,
		deflectStrength = nil,
		range           = nil,
	}

	self.onDeflect = Instance.new("BindableEvent")

	table.insert(activeBalls, self)
	return self
end

function module:setStat(stat, value)
	local id = effectsModule.addEffect(self, stat)
	self.tempValues[stat] = value
	return id
end

function module:changeStat(stat, value)
	self.currentValues[stat] = value
end

function module:resetStat(stat, id)
	local wasRemoved = effectsModule.removeEffect(self, stat, id)
	if not wasRemoved then return end
	self.tempValues[stat] = nil
end

function module:forceResetStat(stat)
	effectsModule.forceRemoveEffect(self, stat)
	self.tempValues[stat] = nil
end

function module:getStat(stat)
	local value = self.currentValues[stat]
	if not value then return end
	return value
end

function module:deflect()
	local targetPlayer = self:getTargetPlayer()
	local deflectDir
	local currentDeflectStrength = self.tempValues.deflectStrength or self.currentValues.deflectStrength

	if targetPlayer then
		soundsModule.playSoundAtPlayer(targetPlayer, "DeflectSound")

		local cameraCFrame = inputsModule.getCameraCFrame(targetPlayer)
		deflectDir = cameraCFrame.LookVector

		local playerStrength = playersModule.getStat(targetPlayer, "strength") or 0
		currentDeflectStrength += playerStrength
	else
		soundsModule.playSoundAtPart(self.target, "DeflectSound")

		deflectDir = self.target.CFrame.LookVector
	end
	deflectDir = Vector3.new(deflectDir.X, math.max(0, deflectDir.Y) + 0.0001, deflectDir.Z).Unit

	local activeVel = self.tempValues.velocity or self.currentValues.velocity

	self.currentValues.velocity = deflectDir * (activeVel.Magnitude + currentDeflectStrength)

	self.onDeflect:Fire()
end

function module:act()
	local ball = self.ball

	self.connection = RunService.Heartbeat:Connect(function(dt)
		if not self.target then
			local randomTarget = self:getRandomTarget()
			self:setTarget(randomTarget)
			return
		end

		local currentAcceleration = self.tempValues.acceleration or self.currentValues.acceleration
		local currentJerk = self.tempValues.jerk or self.currentValues.jerk
		local currentMaxDist = self.tempValues.maxDist or self.currentValues.maxDist
		local currentDecayPower = self.tempValues.decayPower or self.currentValues.decayPower
		local currentDragCoef = self.tempValues.dragCoef or self.currentValues.dragCoef
		local currentDragPower = self.tempValues.dragPower or self.currentValues.dragPower

		local baseRange = self.tempValues.range or self.currentValues.range 
		local lethalRange = baseRange
		local deflectRange = baseRange

		local targetPlayer = self:getTargetPlayer()

		if targetPlayer then
			local playerReach = playersModule.getStat(targetPlayer, "reach") or 0
			deflectRange += playerReach
		end

		local dtScale = dt * 60

		local vectorToTarget = self.target.Position - ball.Position
		local dist = vectorToTarget.Magnitude

		if dist < deflectRange and not effectsModule.hasEffect(self, "controlled") then
			if targetPlayer then
				local deflecting = effectsModule.hasEffect(targetPlayer, "deflecting")
				local invincible = effectsModule.hasEffect(targetPlayer, "invincible")
				if deflecting then
					playersModule.forceResetStat(targetPlayer, "deflecting")
					abilitiesModule.resetCooldown(targetPlayer, "Deflect")
					self:deflect()
					local nextTarget = self:getNextTarget()
					self:setTarget(nextTarget)
					return
				end

				if dist < lethalRange then
					if not invincible then
						local character = targetPlayer.Character
						if not character then return end
						local humanoid = character:FindFirstChild("Humanoid")
						if not humanoid then return end
						humanoid.Health = 0
						soundsModule.playSoundAtPlayer(targetPlayer, "KillSound")
						self:destroy()
						return
					end
				end
			else
				if dist < lethalRange then
					self:deflect()
					local nextTarget = self:getNextTarget()
					self:setTarget(nextTarget)
					return
				end
			end
		end

		local isUsingTempVelocity = (self.tempValues.velocity ~= nil)
		local activeVel = isUsingTempVelocity and self.tempValues.velocity or self.currentValues.velocity

		activeVel += vectorToTarget.Unit * (currentAcceleration * dtScale)

		local radialDir = vectorToTarget.Unit
		local radialVel = radialDir * activeVel:Dot(radialDir)
		local tangentialVel = activeVel - radialVel

		local t = math.clamp(dist / currentMaxDist, 0, 1)
		local curve = t ^ currentDecayPower

		local newTangential = tangentialVel * curve
		local removed = tangentialVel.Magnitude - newTangential.Magnitude
		local addForward = radialDir * removed

		activeVel = radialVel + newTangential + addForward
		local speed = activeVel.Magnitude

		if speed > 0 then
			local dragForce = currentDragCoef * (speed ^ currentDragPower)
			local decayRate = (dragForce / speed) * dtScale
			local dragMultiplier = math.exp(-decayRate)

			activeVel = activeVel * dragMultiplier
		end

		if isUsingTempVelocity then
			self.tempValues.velocity = activeVel
		else
			self.currentValues.velocity = activeVel
		end

		ball.Position = Vector3.new(
			ball.Position.X + (activeVel.X * dtScale), 
			math.max(ball.Position.Y + (activeVel.Y * dtScale), 2), 
			ball.Position.Z + (activeVel.Z * dtScale)
		)

		if not self.tempValues.acceleration then
			self.currentValues.acceleration += currentJerk * dtScale
		end
	end)
end

function module:destroy()
	if self.onDeflect then
		self.onDeflect:Destroy()
	end
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end

	if self.target then
		removeHighlight(self.target)
		local curPlayer = self:getTargetPlayer()
		if curPlayer then
			highlightEvent:FireClient(curPlayer, self.ball, false)
		end
	end

	if self.ball then
		self.ball:Destroy()
	end

	local index = table.find(activeBalls, self)
	if index then
		table.remove(activeBalls, index)
	end
end

function module.getAllTargets()
	local targets = {}

	for _, bot in pairs(bots) do
		local hrp = bot:FindFirstChild("HumanoidRootPart")
		if not hrp then continue end
		table.insert(targets, hrp)
	end

	for _, player in pairs(Players:GetPlayers()) do
		local character = player.Character
		if not character then continue end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChild("Humanoid")
		if not hrp or not humanoid then continue end

		if humanoid.Health <= 0 then continue end
		table.insert(targets, hrp)
	end

	return targets
end

function module:getTargetPlayer()
	local character = self.target.Parent
	return Players:GetPlayerFromCharacter(character)
end

function module:getRandomTarget()
	local curTarget = self.target
	local targets = module.getAllTargets()
	local index = table.find(targets, curTarget)

	if index then table.remove(targets, index) end
	if #targets == 0 then return curTarget end

	local randomIndex = math.random(1, #targets)
	return targets[randomIndex]
end

function module:getNextTarget(mousePos)
	local curTarget = self.target
	local targets = module.getAllTargets()
	local index = table.find(targets, curTarget)

	if index then table.remove(targets, index) end
	if #targets == 0 then return curTarget end

	local targetPlayer = self:getTargetPlayer()

	if targetPlayer then
		mousePos = inputsModule.getMousePos(targetPlayer)
	else
		mousePos = curTarget.Position
	end

	local closestTarget = nil
	local closestDist = math.huge

	for _, target in pairs(targets) do
		local dist = (target.Position - mousePos).Magnitude
		if dist > closestDist then continue end

		closestDist = dist
		closestTarget = target
	end

	return closestTarget
end

function module:setTarget(nextTarget)
	if self.target then
		local curPlayer = self:getTargetPlayer()
		if curPlayer then
			highlightEvent:FireClient(curPlayer, self.ball, false)
		end
		removeHighlight(self.target)
	end

	self.target = nextTarget

	local targetPlayer = self:getTargetPlayer()
	if targetPlayer then
		highlightEvent:FireClient(targetPlayer, self.ball, true)
	end
	addHighlight(self.target)
end

function module.getActiveBalls()
	return activeBalls
end

function module.getNearestBall(player)
	local character = player.Character
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local nearestBall = nil
	local nearestDist = math.huge

	for _, ball in pairs(activeBalls) do
		local dist = (ball.ball.Position - hrp.Position).Magnitude
		if dist > nearestDist then continue end

		nearestDist = dist
		nearestBall = ball
	end
	return nearestBall
end

function module.getBallsInRadius(position, range, targetedPlayerOnly)
	local ballsFound = {}
	for _, b in pairs(activeBalls) do
		if not b.ball or not b.ball.Parent then continue end
		local dist = (b.ball.Position - position).Magnitude
		if dist <= range then
			if targetedPlayerOnly and b:getTargetPlayer() ~= targetedPlayerOnly then
				continue
			end
			table.insert(ballsFound, b)
		end
	end
	return ballsFound
end

function module.getNearestTargetToPosition(position, ignoreTarget)
	if not position then return nil end
	local targets = module.getAllTargets()
	local closestTarget = nil
	local closestDist = math.huge

	for _, target in pairs(targets) do
		if target == ignoreTarget then continue end
		local dist = (target.Position - position).Magnitude
		if dist < closestDist then
			closestDist = dist
			closestTarget = target
		end
	end

	return closestTarget
end

return module
